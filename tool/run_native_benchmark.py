"""Run the already-built Phase 0 profile app and sample process RSS at 1 Hz."""

import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading
import time
import re
import os
import urllib.request
import urllib.parse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', default='build/macos/Build/Products/Profile/whiteboard.app/Contents/MacOS/whiteboard')
    parser.add_argument('--output', default='benchmark_results/macos-profile.json')
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--trace', action='store_true')
    parser.add_argument('--memory', action='store_true')
    parser.add_argument('--cpu-profile', action='store_true')
    parser.add_argument('--stop-after', type=int)
    parser.add_argument('--progress-timeout', type=int, default=0,
        help='Stop incomplete if no benchmark event arrives for this many seconds.')
    args = parser.parse_args()
    app = Path(args.app).resolve()
    if not app.is_file():
        parser.error('Build the profile app with PHASE0_AUTORUN=true first.')
    started = time.monotonic()
    launch_env=os.environ.copy()
    if args.cpu_profile:
        flag_count=int(launch_env.get('FLUTTER_ENGINE_SWITCHES','0'))+1
        launch_env['FLUTTER_ENGINE_SWITCHES']=str(flag_count)
        launch_env[f'FLUTTER_ENGINE_SWITCH_{flag_count}']='enable-dart-profiling=true'
    process = subprocess.Popen([str(app)],env=launch_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines = queue.Queue()
    service_urls = []
    rpc_errors = []
    def rpc(method, **params):
        if not service_urls: return None
        try:
            url = service_urls[0] + method + '?' + urllib.parse.urlencode(params)
            with urllib.request.urlopen(url, timeout=4) as response:
                result=json.load(response)
            if 'error' in result and len(rpc_errors)<32:
                rpc_errors.append({'method':method,'error':result['error'].get('message')})
            return result.get('result')
        except Exception:
            return None


    def read_output():
        for line in process.stdout:
            match=re.search(r'http://127\.0\.0\.1:\d+/[^\s]*/', line)
            if match and not service_urls: service_urls.append(match.group(0))
            if 'PHASE0_' in line:
                lines.put(line[line.index('PHASE0_'):].strip())

    threading.Thread(target=read_output, daemon=True).start()
    report = {'complete': False, 'rssSamplingSeconds': 1, 'cpuProfilingEnabled':args.cpu_profile, 'ready': [], 'runs': [], 'diagnostics': [], 'rssSamples': []}
    next_sample = 0
    last_boundary = 0
    last_progress = started
    try:
        while time.monotonic() - started < args.timeout:
            now = time.monotonic() - started
            if args.progress_timeout and time.monotonic() - last_progress > args.progress_timeout:
                report['error'] = f'No benchmark event for {args.progress_timeout} seconds; collection incomplete.'
                break
            if now >= next_sample:
                sample = subprocess.run(['ps', '-o', 'rss=', '-p', str(process.pid)], capture_output=True, text=True, timeout=2)
                if sample.stdout.strip().isdigit():
                    report['rssSamples'].append({'seconds': round(now, 3), 'rssKiB': int(sample.stdout.strip())})
                next_sample = now + 1
            try:
                line = lines.get(timeout=0.1)
            except queue.Empty:
                if process.poll() is not None:
                    report['error'] = f'App exited before suite completion: {process.returncode}'
                    break
                continue
            last_progress = time.monotonic()
            prefix, _, payload = line.partition(' ')
            now = time.monotonic() - started
            if prefix == 'PHASE0_READY':
                ready = json.loads(payload)
                ready['receivedSinceLaunchMs'] = round(now * 1000, 3)
                report['ready'].append(ready)
                print(json.dumps({'ready':ready['scene'],'loadMs':ready.get('loadToInteractiveMs')}),flush=True)
                last_boundary = now
                if args.trace: report['timelineFlags']=rpc('getVMTimelineFlags')
            elif prefix == 'PHASE0_RESULT':
                result = json.loads(payload)
                samples = [s['rssKiB'] for s in report['rssSamples'] if last_boundary <= s['seconds'] <= now]
                result['sampledRssKiBPeak'] = max(samples) if samples else None
                report['runs'].append(result)
                if args.trace and result['scene']=='dense' and result['workload'] in ['camera','withoutText','overview']:
                    suffix=result['workload']
                    timeline=rpc('getVMTimeline')
                    if timeline:
                        trace_path=Path(args.output).with_suffix('.'+suffix+'.timeline.json')
                        trace_path.parent.mkdir(parents=True,exist_ok=True)
                        trace_path.write_text(json.dumps(timeline))
                        result['timelineFile']=str(trace_path)
                    vm=rpc('getVM')
                    if vm and vm.get('isolates') and timeline:
                        end=timeline.get('timeOriginMicros',0)+timeline.get('timeExtentMicros',0)
                        cpu=rpc('getCpuSamples',isolateId=vm['isolates'][0]['id'],timeOriginMicros=max(0,end-12000000),timeExtentMicros=12000000)
                        if cpu:
                            cpu_path=Path(args.output).with_suffix('.'+suffix+'.cpu.json')
                            cpu_path.write_text(json.dumps(cpu))
                            result['cpuFile']=str(cpu_path)
                last_boundary = now
                print(json.dumps({'scene': result['scene'], 'workload': result['workload'], 'stage': result['frames']['stage']}), flush=True)
                if args.stop_after and len(report['runs'])>=args.stop_after:
                    report['diagnosticComplete']=True
                    report['boundedDiagnosticStopAfter']=args.stop_after
                    break
            elif prefix == 'PHASE0_DIAGNOSTIC':
                diagnostic=json.loads(payload)
                if (args.trace or args.memory) and ((diagnostic.get('kind')=='openClose' and diagnostic.get('cycle') in [0,3,7,11,15]) or diagnostic.get('kind')=='stressMemory'):
                    vm=rpc('getVM')
                    if vm and vm.get('isolates'):
                        allocation=rpc('getAllocationProfile', isolateId=vm['isolates'][0]['id'], gc='true')
                        if allocation: diagnostic['forcedGcMemoryUsage']=allocation.get('memoryUsage')
                diagnostic['receivedSeconds']=round(now,3)
                report['diagnostics'].append(diagnostic)
                print(json.dumps(diagnostic),flush=True)
            elif prefix == 'PHASE0_SUITE_DONE':
                expected = json.loads(payload)['runs']
                report['complete'] = len(report['runs']) == expected
                if args.trace:
                    timeline=rpc('getVMTimeline')
                    if timeline:
                        trace_path=Path(args.output).with_suffix('.timeline.json')
                        trace_path.write_text(json.dumps(timeline))
                        report['timelineFile']=str(trace_path)
                    vm=rpc('getVM')
                    if vm and vm.get('isolates'):
                        if timeline:
                            end=timeline.get('timeOriginMicros',0)+timeline.get('timeExtentMicros',0)
                            cpu=rpc('getCpuSamples',isolateId=vm['isolates'][0]['id'],timeOriginMicros=max(0,end-60000000),timeExtentMicros=60000000)
                            if cpu:
                                cpu_path=Path(args.output).with_suffix('.cpu.json')
                                cpu_path.write_text(json.dumps(cpu))
                                report['cpuFile']=str(cpu_path)
                    report['vmServiceAvailable']=bool(service_urls)
                break
            elif prefix == 'PHASE0_SUITE_FAILED':
                report['error'] = payload
                break
        else:
            report['error'] = f'Suite exceeded {args.timeout} seconds.'
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        report['rpcErrors']=rpc_errors
        report['elapsedSeconds'] = round(time.monotonic() - started, 3)
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print(f'Saved {output}; complete={report["complete"]}', flush=True)
    return 0 if report['complete'] or report.get('diagnosticComplete') else 1


if __name__ == '__main__':
    raise SystemExit(main())
