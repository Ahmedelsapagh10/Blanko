"""Validate bounded dirty-repair diagnostics; never certify a rendering gate."""

import argparse
import json
from pathlib import Path

from summarize_phase03 import summarize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('benchmark_results/execution-01'))
    parser.add_argument('--target', choices=['web', 'macos'], default='web')
    args = parser.parse_args()
    reports = [json.loads((args.root / f'{args.target}-{name}.json').read_text())
               for name in ['reference', 'repair']]
    expected = [('normal', 'editSingle'), ('dense', 'editSingle'), ('dense', 'editMulti')]
    for enabled, report in zip([False, True], reports):
        assert report.get('diagnosticComplete') is True
        assert report.get('boundedDiagnosticStopAfter') == 3
        assert not report['complete'], 'This validator is only for bounded diagnostics.'
        assert [(r['scene'], r['workload']) for r in report['runs']] == expected
        assert not report.get('errors') and not report.get('error')
        for run in report['runs']:
            assert run['mode'] == 'profile'
            assert run['tilesEnabled'] and run['recovery']
            assert run['tiles']['dirtyRepair'] is enabled
            assert not run['viewportChanged'] and run['lifecycleChanges'] == 0
            frames = run['frames']['stage']
            assert frames['observed'] == frames['retained'] == len(run['frameSeriesMicros'])
            assert frames['retained'] > 0
            cache = run['tiles']
            assert cache['errors'] == 0
            assert cache['peakBytes'] <= cache['limitBytes'] == 64 * 1024 * 1024
            assert cache['pinnedHandles'] in (0, 1)
            if enabled:
                assert cache['repairs'] > 0, 'The candidate must actually exercise repair.'
    before, after = reports
    if args.target == 'web':
        assert before['environment'] == after['environment']
        assert before['environment']['gpuCompositing'] == 'enabled'
    for a, b in zip(before['runs'], after['runs']):
        assert a['viewport'] == b['viewport']
    output = {
        'target': args.target,
        'boundedDiagnosticOnly': True,
        'renderingGateQualified': False,
        'physicalInputOrPresentationValidated': False,
        'reference': summarize(before),
        'repair': summarize(after),
    }
    path = args.root / f'{args.target}-dirty-repair-summary.json'
    path.write_text(json.dumps(output, indent=2) + '\n')
    print(f'Validated three matched {args.target} profile diagnostics; no gate qualification.')
    for a, b in zip(before['runs'], after['runs']):
        print(f"{a['scene']}/{a['workload']}: stage P95 "
              f"{a['frames']['stage']['p95Ms']} -> {b['frames']['stage']['p95Ms']} ms; "
              f"repairs={b['tiles']['repairs']}, replayed={b['tiles']['repairReplayedEntries']}")


if __name__ == '__main__':
    main()
