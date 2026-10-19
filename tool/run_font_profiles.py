"""Capture serial CanvasKit arms with fixed fonts; never qualifies the full gate."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlparse


FONT_ID = 'roboto-3.015-noto-sans-arabic-2.012-v1'
FONT_NAMES = {'Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf',
              'NotoSansArabic-Regular.ttf'}


def validate_font_capture(report):
    audit = report['fontAudit']
    if (audit['overflow'] is not False or audit['externalRequests'] or
            audit['assetsCompleteBeforeReady'] is not True or audit['reportsReady'] is not True):
        raise ValueError('Incomplete font audit')
    first = audit['firstReadyAt']
    if not isinstance(first, (float, int)) or not math.isfinite(first):
        raise ValueError('Invalid first-ready timestamp')
    complete = set()
    if not 4 <= len(audit['requests']) <= 64:
        raise ValueError('Missing/overflowed font request evidence')
    for request in audit['requests']:
        url = urlparse(request['url'])
        if url.scheme != 'http' or url.netloc != '127.0.0.1:8765':
            raise ValueError('External font request')
        if request.get('failure'):
            raise ValueError('Font transfer failed')
        if url.path.startswith('/assets/assets/benchmark_fonts/'):
            if (request['status'] != 200 or
                    not 0 <= request['startedAt'] <= request.get('finishedAt', math.inf) <= first):
                raise ValueError('Font asset not complete before readiness')
            complete.add(url.path.rsplit('/', 1)[-1])
    if complete != FONT_NAMES or not report['ready'] or not report['runs']:
        raise ValueError('Missing fixed fonts or readiness rows')
    for row in report['ready'] + [run['load'] for run in report['runs']]:
        fonts = row['fonts']
        if fonts['ready'] is not True or fonts['manifest'] != FONT_ID:
            raise ValueError('Uncontrolled font manifest/readiness')
        if not isinstance(fonts['registrationMs'], (float, int)) or not 0 <= fonts['registrationMs'] < math.inf:
            raise ValueError('Missing font preparation time')


def hashes():
    paths = sorted(Path('lib').rglob('*.dart')) + sorted(Path('test').rglob('*.dart'))
    paths += sorted(Path('assets/benchmark_fonts').glob('*'))
    paths += [Path('pubspec.yaml'), Path('pubspec.lock')]
    paths += [p for p in sorted(Path('tool').glob('*')) if p.is_file()]
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def run(command, log, timeout):
    with log.open('w') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node', required=True)
    parser.add_argument('--playwright', required=True)
    parser.add_argument('--chrome', required=True)
    parser.add_argument('--output', type=Path, default=Path('benchmark_results/execution-05'))
    args = parser.parse_args()
    root = args.output
    root.mkdir(parents=True, exist_ok=True)
    manifest = {'sourceHashes': hashes(), 'runs': [], 'renderingGateQualified': False,
                'comparison': 'new controlled-font baseline; not historical font-isolated causation'}
    manifest['host'] = {'platform': platform.platform(), 'machine': platform.machine()}
    version = subprocess.run(['flutter', '--version', '--machine'], capture_output=True,
                             text=True, timeout=30, check=True)
    manifest['sdk'] = json.loads(version.stdout)
    try:
        for variant in ['direct', 'vector', 'layers']:
            # Refuse to attach to an unrelated server already using this port.
            with socket.socket() as probe:
                # Match HTTPServer: a closed prior arm can leave TIME_WAIT
                # connections without a listening process owning the port.
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                probe.bind(('127.0.0.1', 8765))
            build = ['flutter', 'build', 'web', '--no-pub', '--profile',
                     '--no-web-resources-cdn', '--no-wasm-dry-run',
                     '--dart-define=PHASE0_AUTORUN=true', '--dart-define=PHASE03_SUITE=true',
                     '--dart-define=PHASE02_TILES=false', '--dart-define=WB_RETAINED_EXPERIMENT=true',
                     '--dart-define=WB_RETAINED_RANGES=' + str(variant == 'vector').lower(),
                     '--dart-define=WB_RETAINED_LAYERS=' + str(variant == 'layers').lower(),
                     '--dart-define=WB_LAYER_INTERLEAVED=true', '-t', 'lib/benchmark_main.dart']
            row = {'variant': variant, 'buildCommand': build,
                   'freeBytesBeforeBuild': shutil.disk_usage('.').free}
            manifest['runs'].append(row)
            row['buildExitCode'] = run(build, root / f'{variant}-build.log', 900)
            if row['buildExitCode'] != 0:
                raise RuntimeError('Profile build failed: ' + variant)
            # Include every possible local engine route before capture, and fonts.
            paths = [Path('build/web/main.dart.js'), Path('build/web/flutter_bootstrap.js')]
            paths += [Path('build/web/assets/FontManifest.json'),
                      Path('build/web/assets/AssetManifest.bin')]
            paths += sorted(Path('build/web/canvaskit').rglob('*.wasm'))
            paths += sorted(Path('build/web/canvaskit').rglob('*.js'))
            paths += sorted(Path('build/web/assets/assets/benchmark_fonts').glob('*'))
            row['binaryHashesBeforeCapture'] = {
                str(p.relative_to('build/web')): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in paths}
            server_command = [sys.executable, 'tool/serve_benchmark.py', '--isolated']
            with (root / f'{variant}-server.log').open('w') as server_log:
                server = subprocess.Popen(server_command, stdout=server_log, stderr=subprocess.STDOUT)
                row['serverCommand'] = server_command
                try:
                    for _ in range(40):
                        if server.poll() is not None:
                            raise RuntimeError('Owned loopback server failed to start')
                        try:
                            with urllib.request.urlopen('http://127.0.0.1:8765/', timeout=.5):
                                break
                        except OSError:
                            time.sleep(.1)
                    else:
                        raise RuntimeError('Loopback server readiness timed out')
                    collector = [args.node, 'tool/run_web_benchmark.mjs', '--playwright', args.playwright,
                                 '--executable', args.chrome, '--hardware-metal', '--stop-after', '4',
                                 '--timeout', '120', '--expect-backend', 'canvaskit',
                                 '--require-local-fonts', '--output', str(root / f'web-{variant}.json')]
                    row['collectorCommand'] = collector
                    row['collectorExitCode'] = run(collector, root / f'{variant}-collector.log', 150)
                    if row['collectorExitCode'] != 0:
                        raise RuntimeError('Collector/font audit failed: ' + variant)
                    validate_font_capture(json.loads((root / f'web-{variant}.json').read_text()))
                    row['fontCaptureValidated'] = True
                    if variant == 'layers':
                        startup = [args.node, 'tool/inspect_web_startup.mjs', '--playwright', args.playwright,
                                   '--executable', args.chrome, '--block-external', '--output',
                                   str(root / 'startup-local-only.json')]
                        row['startupCommand'] = startup
                        row['startupExitCode'] = run(startup, root / 'startup-local-only.log', 110)
                        if row['startupExitCode'] != 0:
                            raise RuntimeError('Local-only startup audit failed')
                finally:
                    server.terminate()
                    try:
                        server.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        server.kill()
                        server.wait()
                    row['ownedServerStopped'] = True
            row['sourceHashesUnchanged'] = hashes() == manifest['sourceHashes']
            row['freeBytesAfterCapture'] = shutil.disk_usage('.').free
            if not row['sourceHashesUnchanged']:
                raise RuntimeError('Sources changed during capture')
            print('Captured ' + variant + ' with font readiness audit', flush=True)
        manifest['summaryExitCode'] = run(
            [sys.executable, 'tool/summarize_layers.py', '--root', str(root), '--interleaved'],
            root / 'summary.log', 30)
        manifest['complete'] = manifest['summaryExitCode'] == 0
        if not manifest['complete']:
            raise RuntimeError('Matched controls/distribution validation failed')
    except Exception as error:
        manifest['error'] = str(error)
        raise
    finally:
        (root / 'profile-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
