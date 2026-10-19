"""Run each test file in a fresh process to bound temporary compiler output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def hashes():
    paths = sorted(Path('lib').rglob('*.dart')) + sorted(Path('test').rglob('*.dart'))
    paths += [Path('pubspec.yaml'), Path('pubspec.lock')]
    paths += sorted(Path('assets/benchmark_fonts').glob('*'))
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['host', 'chrome'], default='host')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, 'tool/verify_benchmark_fonts.py',
                    '--prepare-web-tests'], check=True)
    files = sorted(Path('test').rglob('*_test.dart'))
    report = {'platform': args.platform, 'complete': False, 'testFiles': [str(p) for p in files],
              'sourceHashes': hashes(), 'runs': [], 'passed': 0,
              'chromeExecutable': os.environ.get('CHROME_EXECUTABLE')}
    try:
        for path in files:
            command = ['flutter', 'test', '--no-pub', '--concurrency=1']
            if args.platform == 'chrome':
                command += ['--platform', 'chrome']
            command.append(str(path))
            log = args.output.parent / f'{args.platform}-{path.stem}.log'
            with log.open('w') as output:
                result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
            matches = re.findall(r'\+(\d+): All tests passed!', log.read_text())
            passed = int(matches[-1]) if matches else 0
            success = result.returncode == 0 and bool(matches)
            report['runs'].append({'file': str(path), 'command': command,
                                   'exitCode': result.returncode, 'passed': passed,
                                   'success': success, 'log': str(log)})
            print(f'{args.platform}: {path}: {passed} passed; success={success}', flush=True)
            if not success:
                report['error'] = f'Incomplete/failed test file: {path}'
                break
            report['passed'] += passed
        report['sourceHashesUnchanged'] = hashes() == report['sourceHashes']
        report['complete'] = (bool(files) and len(report['runs']) == len(files)
                              and all(r['success'] for r in report['runs'])
                              and report['sourceHashesUnchanged'])
    finally:
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
