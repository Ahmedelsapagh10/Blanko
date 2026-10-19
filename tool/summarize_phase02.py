"""Validate and compare actual Phase 0.2 profile collections."""
import argparse
import json
from pathlib import Path

ROOT = Path('benchmark_results/phase02')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targets', nargs='+', choices=['macos','web'], default=['macos','web'])
    args = parser.parse_args()
    result = {'comparisons': [], 'memory': {}, 'diagnostics': {}, 'targets':args.targets}
    for target in args.targets:
        source = {}
        for variant in ['before', 'after']:
            data = json.loads((ROOT / f'{target}-{variant}.json').read_text())
            assert data['complete'] and len(data['runs']) == 12
            assert not data.get('error') and not data.get('errors')
            assert not data.get('rpcErrors')
            for row in data['runs']:
                assert row['mode'] == 'profile'
                assert row['tilesEnabled'] == (variant == 'after')
                assert not row['viewportChanged'] and row['lifecycleChanges'] == 0
                assert row['frames']['stage']['observed'] > 0
                assert row['frames']['stage']['retained'] == row['frames']['stage']['observed'], 'Truncated primary frame distribution'
                assert row['frameVsyncIntervals']['retained'] == row['frameVsyncIntervals']['observed']
                if row.get('tiles'):
                    assert row['tiles']['bytes'] <= row['tiles']['limitBytes']
                    assert row['tiles']['peakBytes'] <= row['tiles']['limitBytes']
                    assert row['tiles']['errors'] == 0
            cycles = [d for d in data['diagnostics'] if d.get('kind') == 'openClose']
            assert len(cycles) == 16
            assert all(d['disposed'] and d['imageHandlesAfterDispose'] == 0 and d['paragraphsAfterDispose'] == 0 for d in cycles)
            source[variant] = {(r['scene'], r['workload']): r for r in data['runs']}
            result['diagnostics'][f'{target}-{variant}'] = data['diagnostics']
            rss = data.get('rssSamples', [])
            stress = [d for d in data['diagnostics'] if d.get('kind') == 'stressMemory']
            gc = [d['forcedGcMemoryUsage'] for d in stress if d.get('forcedGcMemoryUsage')]
            heaps = [d['approximateJsHeap']['usedJSHeapSize'] for d in stress if d.get('approximateJsHeap')]
            result['memory'][f'{target}-{variant}'] = {
                'rssInitialMiB': rss[0]['rssKiB']/1024 if rss else None,
                'rssPeakMiB': max(s['rssKiB'] for s in rss)/1024 if rss else None,
                'rssFinalMiB': rss[-1]['rssKiB']/1024 if rss else None,
                'stressForcedGc': gc,
                'approximateJsStressInitialMiB': heaps[0]/1048576 if heaps else None,
                'approximateJsStressPeakMiB': max(heaps)/1048576 if heaps else None,
                'approximateJsStressFinalMiB': heaps[-1]/1048576 if heaps else None,
                'finalJsHeap': data.get('finalJsHeap'),
            }
        if target == 'web':
            env = [json.loads((ROOT/f'web-{v}.environment.json').read_text()) for v in ['before', 'after']]
            assert env[0] == env[1], 'Browser/backend changed during comparison'
            assert env[0]['gpuCompositing'] == 'enabled'
        for key, after in source['after'].items():
            before = source['before'][key]
            assert before['viewport'] == after['viewport']
            result['comparisons'].append({'target': target, 'scene': key[0], 'workload': key[1], 'before': before, 'after': after})
    (ROOT/'summary.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f'Validated {len(result["comparisons"])} matched workload pairs, cache bounds and {len(args.targets)*32} disposal cycles.')


if __name__ == '__main__':
    main()
