"""Summarize measured Phase 0.1 artifacts; never substitutes for running them."""
import gzip
import json
import math
from pathlib import Path

ROOT = Path('benchmark_results/phase01')

def read(path):
    if not path.exists():
        path = Path(str(path) + '.gz')
    if path.suffix == '.gz':
        with gzip.open(path, 'rt') as handle:
            return json.load(handle)
    return json.loads(path.read_text())

def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[math.ceil(len(ordered) * p / 100) - 1]

def native_trace(path):
    data = read(path)
    events = data.get('traceEvents', [])
    end = max((e.get('ts', 0) for e in events), default=0)
    begin = end - 12000000
    stacks = {}
    durations = {}
    for event in events:
        key = (event.get('pid'), event.get('tid'))
        if event.get('ph') == 'B':
            stacks.setdefault(key, []).append(event)
        elif event.get('ph') == 'E' and stacks.get(key):
            opening = stacks[key].pop()
            if opening.get('name') != event.get('name'):
                continue
            start = opening.get('ts', 0)
            if start >= begin and event.get('ts', 0) >= start:
                durations.setdefault(opening.get('name'), []).append((event['ts'] - start) / 1000)
    names = ['Rasterizer::DrawToSurfaces', 'LayerTree::Paint', 'PAINT', 'PipelineFull',
             'GrMtlPipelineState *GrMtlPipelineStateBuilder::finalize(const GrProgramDesc &, const GrProgramInfo &, const GrMtlPrecompiledLibraries *)']
    return {name: {'count': len(durations.get(name, [])), 'p95Ms': percentile(durations.get(name, []), 95)} for name in names}

def main():
    result = {'comparisons': [], 'diagnostics': {}, 'nativeMemory': {}, 'browserMemory': {}, 'nativeTraces': {}, 'nativeCpu': {}}
    for target in ['macos', 'web']:
        before, after = [read(ROOT / f'{target}-{variant}.json') for variant in ['before', 'after']]
        assert before['complete'] and after['complete']
        assert len(before['runs']) == len(after['runs']) == 11
        old = {(r['scene'], r['workload']): r for r in before['runs']}
        for row in after['runs']:
            previous = old[(row['scene'], row['workload'])]
            assert row['mode'] == previous['mode'] == 'profile'
            assert row['viewport'] == previous['viewport']
            assert row['frames']['stage']['observed'] > 0
            assert not row['viewportChanged'] and not previous['viewportChanged']
            assert row['lifecycleChanges'] == previous['lifecycleChanges'] == 0
            assert row['overviewBytes'] <= 16*1024*1024
            result['comparisons'].append({'target': target, 'scene': row['scene'], 'workload': row['workload'],
                'beforeFrames': previous['frames'], 'afterFrames': row['frames'],
                'beforeCpu': previous['cpu'], 'afterCpu': row['cpu'],
                'beforeLoad': previous['load'], 'afterLoad': row['load'],
                'beforeHit': previous['hitTest'], 'afterHit': row['hitTest']})
        result['diagnostics'][target] = after.get('diagnostics', [])
        if target == 'macos':
            for variant, data in [('before', before), ('after', after)]:
                checkpoints = [d['forcedGcMemoryUsage'] for d in data['diagnostics'] if 'forcedGcMemoryUsage' in d]
                result['nativeMemory'][variant] = {'peakRssMiB': max(s['rssKiB'] for s in data['rssSamples']) / 1024,
                    'forcedGcCheckpoints': checkpoints, 'lastRssMiB': data['rssSamples'][-1]['rssKiB'] / 1024}
                result['nativeTraces'][variant] = native_trace(ROOT / f'macos-{variant}.camera.timeline.json')
                cpu = read(ROOT / f'macos-{variant}.camera.cpu.json')
                top = sorted(cpu['functions'], key=lambda f: f.get('exclusiveTicks', 0), reverse=True)[:12]
                result['nativeCpu'][variant] = {'sampleCount': cpu['sampleCount'], 'samplePeriodMicros': cpu['samplePeriod'],
                    'topSelfTicks': [{'name': f.get('function', {}).get('name'), 'self': f.get('exclusiveTicks'), 'inclusive': f.get('inclusiveTicks')} for f in top]}
        else:
            for variant, data in [('before', before), ('after', after)]:
                heaps = [d.get('approximateJsHeap', {}).get('usedJSHeapSize') for d in data['runs'] + data.get('diagnostics', []) if d.get('approximateJsHeap')]
                result['browserMemory'][variant] = {'approximatePeakJsHeapMiB': max(heaps) / 1024 / 1024 if heaps else None,
                    'cycleHeaps': [{'cycle': d['cycle'], 'heap': d.get('approximateJsHeap')} for d in data.get('diagnostics', []) if d.get('kind') == 'openClose']}
    (ROOT / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print('Validated 22 primary frame workloads and saved summary.json')

if __name__ == '__main__':
    main()
