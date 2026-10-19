"""Validate bounded direct/retained profile pairs without certifying a gate."""

import argparse
import json
from pathlib import Path

from summarize_phase03 import summarize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('benchmark_results/execution-02'))
    parser.add_argument('--target', choices=['web', 'macos'], default='web')
    args = parser.parse_args()
    reports = [json.loads((args.root / f'{args.target}-{name}.json').read_text())
               for name in ['direct', 'retained']]
    expected = [('normal', 'editSingle'), ('dense', 'editSingle'), ('dense', 'editMulti')]
    for enabled, report in zip([False, True], reports):
        assert report.get('diagnosticComplete') is True
        assert report.get('boundedDiagnosticStopAfter') == 3
        assert not report['complete']
        assert not report.get('error') and not report.get('errors') and not report.get('collectorError')
        assert [(r['scene'], r['workload']) for r in report['runs']] == expected
        for run in report['runs']:
            assert run['mode'] == 'profile' and run['optimized'] is True
            assert run['platform'] == ('web' if args.target == 'web' else 'macOS')
            assert run['retainedExperiment'] is True
            assert run['retainedEnabled'] is enabled
            assert not run['tilesEnabled'] and run['tiles'] is None
            assert run['overviewBytes'] == 0 and run['warmupMs'] == 0
            assert not run['viewportChanged'] and run['lifecycleChanges'] == 0
            assert run['viewFocusChanges'] == 0
            assert run['cpu']['commandToFirstPaintRecordMs'] > 0
            samples = run['frames']['stage']
            assert samples['observed'] == samples['retained'] == len(run['frameSeriesMicros'])
            assert samples['retained'] > 0
            count = 16 if run['workload'] == 'editMulti' else 1
            assert len(set(run['activeEditIds'])) == len(run['activeEditIds']) == count
            commits = run['commitSeriesMicros']
            assert commits and len(commits) == run['editCount']
            columns = run['commitSeriesColumns']
            resolved = columns.index('resolvedCount')
            synchronized = columns.index('synchronizedCount')
            assert all(len(row) == len(columns) and row[resolved] == row[synchronized] == count
                       for row in commits)
            if enabled:
                cache = run['retained']
                assert cache['builds'] > 0 and cache['reuses'] > 0
                assert cache['clears'] >= 1 and cache['firstPaintRecordCpuMs'] is not None
                assert cache['peakApproximateBytes'] <= cache['limitApproximateBytes'] == 16 * 1024 * 1024
                assert cache['pictures'] <= cache['pictureLimit'] == 128
                assert cache['activeCount'] == len(run['activeEditIds']) <= 32
                assert not cache['activeOverflow']
            else:
                assert run['retained'] is None
    before, after = reports
    if args.target == 'web':
        assert before['environment'] == after['environment']
        assert before['environment']['gpuCompositing'] == 'enabled'
    for a, b in zip(before['runs'], after['runs']):
        assert a['viewport'] == b['viewport']
        assert a['activeEditIds'] == b['activeEditIds']
        assert a['imageSide'] == b['imageSide'] == 1024
        assert a['decodedPixelBytes'] == b['decodedPixelBytes']
    summaries = [summarize(r) for r in reports]
    for result, raw in zip(summaries, reports):
        for row, run in zip(result['runs'], raw['runs']):
            row['retained'] = run['retained']
            row['activeEditIds'] = run['activeEditIds']
    output = {
        'target': args.target,
        'boundedDiagnosticOnly': True,
        'renderingGateQualified': False,
        'physicalInputOrPresentationValidated': False,
        'approximatePictureBytesAreTotalMemory': False,
        'direct': summaries[0],
        'retained': summaries[1],
    }
    path = args.root / f'{args.target}-retained-summary.json'
    path.write_text(json.dumps(output, indent=2) + '\n')
    print(f'Validated three matched {args.target} profile diagnostics; no gate qualification.')
    for a, b in zip(before['runs'], after['runs']):
        print(f"{a['scene']}/{a['workload']}: stage P95 "
              f"{a['frames']['stage']['p95Ms']} -> {b['frames']['stage']['p95Ms']} ms; "
              f"builds={b['retained']['builds']}, reuses={b['retained']['reuses']}")


if __name__ == '__main__':
    main()
