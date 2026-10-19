"""Validate matched on-screen layer diagnostics, without certifying rendering."""
import argparse
import json
from pathlib import Path

from summarize_phase03 import summarize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('benchmark_results/execution-03'))
    parser.add_argument('--target', choices=['web', 'macos'], default='web')
    parser.add_argument('--variants', nargs='+', choices=['direct', 'vector', 'layers'],
                        default=['direct', 'vector', 'layers'])
    parser.add_argument('--interleaved', action='store_true')
    parser.add_argument('--dense-only', action='store_true',
                        help='Report only dense rows; explicitly preserve excluded controls.')
    args = parser.parse_args()
    assert args.variants[0] == 'direct' and 'layers' in args.variants
    assert len(set(args.variants)) == len(args.variants)
    expected = [('normal', 'editSingle'), ('dense', 'editSingle'), ('dense', 'editMulti')]
    if args.interleaved:
        expected.append(('dense', 'editInterleaved'))
    expected_capture = expected[:]
    if args.dense_only:
        assert args.target == 'macos'
        expected = [row for row in expected if row[0] == 'dense']
    reports = {}
    excluded = {}
    for variant in args.variants:
        raw = json.loads((args.root / f'{args.target}-{variant}.json').read_text())
        assert raw.get('diagnosticComplete') is True and not raw['complete']
        assert raw['boundedDiagnosticStopAfter'] == len(expected_capture)
        assert not any(raw.get(key) for key in ['error', 'errors', 'collectorError', 'rpcErrors'])
        assert [(r['scene'], r['workload']) for r in raw['runs']] == expected_capture
        excluded[variant] = [
            {k: run[k] for k in ['scene', 'workload', 'viewportChanged',
                                 'lifecycleChanges', 'viewFocusChanges']}
            for run in raw['runs'] if (run['scene'], run['workload']) not in expected
        ]
        raw['runs'] = [run for run in raw['runs']
                       if (run['scene'], run['workload']) in expected]
        for run in raw['runs']:
            assert run['mode'] == 'profile' and run['optimized'] is True
            assert run['platform'] == ('web' if args.target == 'web' else 'macOS')
            assert run['retainedExperiment'] is True
            assert run['retainedEnabled'] is (variant == 'vector')
            assert run['layersEnabled'] is (variant == 'layers')
            assert not run['tilesEnabled'] and run['tiles'] is None
            assert run['overviewBytes'] == 0 and run['warmupMs'] == 0
            assert not run['viewportChanged']
            assert run['lifecycleChanges'] == run['viewFocusChanges'] == 0
            assert run['cpu']['commandToFirstPaintRecordMs'] > 0
            stage = run['frames']['stage']
            assert stage['observed'] == stage['retained'] == len(run['frameSeriesMicros']) > 0
            count = 16 if run['workload'] in ['editMulti', 'editInterleaved'] else 1
            assert len(set(run['activeEditIds'])) == len(run['activeEditIds']) == count
            indices = run['activeEditPaintIndices']
            assert len(indices) == count and indices == sorted(set(indices))
            if run['workload'] == 'editInterleaved':
                assert all(b - a > 1 for a, b in zip(indices, indices[1:]))
            commits = run['commitSeriesMicros']
            assert commits and len(commits) == run['editCount']
            columns = run['commitSeriesColumns']
            resolved, synced = columns.index('resolvedCount'), columns.index('synchronizedCount')
            assert all(len(c) == len(columns) and c[resolved] == c[synced] == count for c in commits)
            if variant == 'layers':
                cache = run['layers']
                assert run['retained'] is None
                fallback = run['workload'] == 'editInterleaved' and cache['directFallbacks'] > 0
                if fallback:
                    # Lifetime counters include the ready viewport before active
                    # indices are installed; no cached subtree survives this run.
                    assert cache['layers'] == cache['approximatePictureBytes'] == 0
                    assert cache['estimatedRasterExposureBytes'] == cache['reuses'] == 0
                    assert cache['engineSubmissions'] <= cache['builds']
                    assert cache['firstPaintRecordCpuMs'] is None
                else:
                    assert cache['builds'] > 0 and cache['reuses'] > 0
                    assert 0 < cache['engineSubmissions'] <= cache['builds']
                    assert cache['firstPaintRecordCpuMs'] is not None
                    assert cache['directFallbacks'] == 0
                assert cache['clears'] > 0
                assert cache['activeCount'] == count and not cache['activeOverflow']
                assert 0 <= cache['layers'] <= cache['layerLimit'] == 33
                assert cache['peakApproximatePictureBytes'] <= cache['pictureByteLimit'] == 16 * 1024 * 1024
                assert cache['peakEstimatedRasterExposureBytes'] <= cache['rasterEstimateLimit'] == 64 * 1024 * 1024
            elif variant == 'vector':
                cache = run['retained']
                assert run['layers'] is None
                assert cache['builds'] > 0 and cache['reuses'] > 0
                assert cache['activeCount'] == count and not cache['activeOverflow']
                assert cache['peakApproximateBytes'] <= cache['limitApproximateBytes'] == 16 * 1024 * 1024
            else:
                assert run['layers'] is None and run['retained'] is None
            assert run['imageSide'] == 1024 and run['imageOriginals'] == 4
        reports[variant] = raw
    baseline = reports['direct']
    for raw in reports.values():
        if args.target == 'web':
            assert raw['environment'] == baseline['environment']
            assert raw['environment']['gpuCompositing'] == 'enabled'
        for before, after in zip(baseline['runs'], raw['runs']):
            for field in ['viewport', 'activeEditIds', 'activeEditPaintIndices', 'imageReferences', 'decodedPixelBytes']:
                assert before[field] == after[field]
            for field in ['visibleP50', 'visibleMax']:
                assert before['cpu'][field] == after['cpu'][field]
    output = {'target': args.target, 'boundedDiagnosticOnly': True,
              'partialRowComparison': args.dense_only, 'excludedRows': excluded,
              'renderingGateQualified': False, 'physicalInputOrPresentationValidated': False,
              'estimatedRasterExposureIsTotalGpuMemory': False, 'variants': {}}
    for variant, raw in reports.items():
        result = summarize(raw)
        for row, run in zip(result['runs'], raw['runs']):
            row.update(layers=run['layers'], retained=run['retained'], activeEditIds=run['activeEditIds'])
        output['variants'][variant] = result
    suffix = '-dense' if args.dense_only else ''
    path = args.root / f'{args.target}-layers{suffix}-summary.json'
    path.write_text(json.dumps(output, indent=2) + '\n')
    print(f'Validated {args.target} bounded diagnostics; rendering gate remains unqualified.')
    for i, name in enumerate(expected):
        print('/'.join(name), {v: r['runs'][i]['frames']['stage']['p95Ms'] for v, r in reports.items()})


if __name__ == '__main__':
    main()
