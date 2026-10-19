"""Validate and summarize matched Phase 0.3 profile captures without editing history."""
import argparse
import bisect
import json
import math
from pathlib import Path


def quantiles(values):
    values = sorted(values)
    return {'samples': len(values), **{
        f'p{p}Ms': values[math.ceil(len(values)*p/100)-1]/1000 if values else None
        for p in (50, 95, 99)}}


def summarize(report):
    rows = []
    for run in report['runs']:
        series = run.get('frameSeriesMicros', [])
        commits = run.get('commitSeriesMicros', [])
        times = [c[0] for c in commits]
        near, between = [], []
        for timestamp, build, raster, _ in series:
            i = bisect.bisect_right(times, timestamp)-1
            (near if i >= 0 and timestamp-times[i] <= 100000 else between).append(max(build,raster))
        rows.append({
            'scene': run['scene'], 'workload': run['workload'],
            'viewportChanged':run['viewportChanged'],'lifecycleChanges':run['lifecycleChanges'],
            'frames': run['frames'], 'cadence': run['frameVsyncIntervals'],
            'cpu': run['cpu'], 'load': run['load'], 'tiles': run['tiles'],
            'commitCount': len(commits),
            'commitStages': {name:quantiles([c[i] for c in commits]) for i,name in enumerate([
                'totalCpu','geometryCpu','synchronizationCpu','indexCpu',
                'invalidationCpu','validationCpu'],1)},
            'resolvedCounts': sorted(set(c[7] for c in commits)),
            'synchronizedCounts': sorted(set(c[8] for c in commits)),
            'framesWithin100msOfLatestCommitSchedulerTimestamp': quantiles(near),
            'otherFrames': quantiles(between),
            'slowFramesOver16_7ms': sum(max(f[1],f[2]) > 16700 for f in series),
            'slowFramesWithin100ms': sum(v > 16700 for v in near),
        })
    memory = [d for d in report['diagnostics'] if d.get('kind') == 'stressMemory']
    heaps = [d['approximateJsHeap']['usedJSHeapSize'] for d in memory if d.get('approximateJsHeap')]
    cycles = [d for d in report['diagnostics'] if d.get('kind')=='openClose']
    return {'complete':report['complete'], 'runs':rows,
        'stressJsHeapBytes': {'initial':heaps[0] if heaps else None,
            'peak':max(heaps) if heaps else None, 'last':heaps[-1] if heaps else None,
            'steadyLast5Mean':sum(heaps[-5:])/len(heaps[-5:]) if heaps else None},
        'finalJsHeap':report.get('finalJsHeap'), 'rendererCycles':len(cycles),
        'rssSamples':report.get('rssSamples'),
        'diagnostics':report['diagnostics']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targets',nargs='+',default=['web'])
    parser.add_argument('--cold',action='store_true')
    parser.add_argument('--allow-native-lifecycle-diagnostics',action='store_true')
    args=parser.parse_args()
    root=Path('benchmark_results/phase03')
    output={}
    for target in args.targets:
        reports=[json.loads((root/f'{target}-{variant}.json').read_text()) for variant in ['before','after']]
        before,after=reports
        assert before['complete'] and after['complete'], 'Partial runs cannot qualify.'
        assert len(before['runs']) == len(after['runs']) == 20
        control_warnings=[]
        for a,b in zip(before['runs'],after['runs']):
            assert (a['scene'],a['workload'])==(b['scene'],b['workload'])
            assert a['viewport']==b['viewport']
            assert a['mode']==b['mode']=='profile'
            assert a['recovery'] is False and b['recovery'] is True
            for run in (a,b):
                assert run['tilesEnabled'] is True
                assert not run['viewportChanged']
                if run['lifecycleChanges']:
                    assert target=='macos' and args.allow_native_lifecycle_diagnostics
                    control_warnings.append({'variant':'before' if run is a else 'after',
                        'scene':run['scene'],'workload':run['workload'],
                        'lifecycleChanges':run['lifecycleChanges']})
                assert run['frames']['stage']['observed']==run['frames']['stage']['retained']
                assert len(run['frameSeriesMicros'])==run['frames']['stage']['retained']
                assert run['tiles']['errors']==0
                assert run['tiles']['bytes']<=run['tiles']['limitBytes']
        if target=='web':
            assert before['environment']==after['environment']
            assert not before['errors'] and not after['errors']
        for report in reports:
            cycles=[d for d in report['diagnostics'] if d.get('kind')=='openClose']
            assert len(cycles)==16
            assert all(d['disposed'] and d['imageHandlesAfterDispose']==d['paragraphsAfterDispose']==0 and d['tilesAfterDispose']['bytes']==0 for d in cycles)
        output[target]={'collectionControlsClean':not control_warnings,'controlWarnings':control_warnings,
            'before':summarize(before),'after':summarize(after)}
        if args.cold:
            audits={}
            cold_reports=[]
            for variant in ['before','after']:
                report=json.loads((root/f'{target}-cold-{variant}.json').read_text())
                cold_reports.append(report)
                assert report['complete'] and not report['runs']
                cases=[d for d in report['diagnostics'] if d.get('kind')=='coldWallAudit']
                assert [(d['scene'],d['session']) for d in cases]==[
                    ('normal',0),('normal',1),('dense',0),('dense',1)]
                for case in cases:
                    assert case['mode']=='profile'
                    assert case['zoomNormalizedBeforeOpen'] is True
                    assert not case['viewportChanged']
                    if case['lifecycleChanges']:
                        assert target=='macos' and args.allow_native_lifecycle_diagnostics
                        output[target]['coldControlWarning']=True
                    assert case['recovery']==(variant=='after')
                    assert case['oldRendererDisposed'] is True
                    assert case['oldImagesAfterDispose']==case['oldParagraphsAfterDispose']==0
                    assert case['tiles']['errors']==0
                    assert case['tiles']['bytes']<=case['tiles']['limitBytes']
                    assert case['tiles']['peakBytes']<=case['tiles']['limitBytes']
                    assert case['tiles']['pending'] is False
                    for frames in [case['openingFrames'],case['evictionFrames'],*[op['frames'] for op in case['operations']]]:
                        assert frames['stage']['observed']==frames['stage']['retained']
                    assert case['tiles']['evictions']>case['evictBefore']['evictions']
                    assert case['returnToEvictedViewMs']>0
                    assert [op['operation'] for op in case['operations']]==[
                        'firstZoomBucket','visibleCommitRebuild']
                    first_zoom=case['operations'][0]
                    assert first_zoom['after']['builds']>first_zoom['before']['builds'], 'First zoom must actually be cold.'
                audits[variant]=cases
            assert [d['viewport'] for d in audits['before']]==[d['viewport'] for d in audits['after']]
            if target=='web':
                assert cold_reports[0]['environment']==cold_reports[1]['environment']==before['environment']
            output[target]['coldWallAudit']=audits

    (root/'summary.json').write_text(json.dumps(output,indent=2)+'\n')
    qualified=sum(v['collectionControlsClean'] for v in output.values())
    print(f'Validated {qualified} clean paired target(s); {len(output)-qualified} diagnostic pair(s) with explicit control warnings. 20 workloads each, no frame truncation.')


if __name__=='__main__':
    main()
