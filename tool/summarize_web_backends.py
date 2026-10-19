"""Validate matched local web engine diagnostics; never qualify a rendering gate."""
import argparse
import json
import math
from pathlib import Path
from urllib.parse import urlparse

from summarize_phase03 import quantiles, summarize


VARIANTS = ('canvaskit', 'skwasm-single', 'skwasm-multi')
WORKLOADS = [('normal', 'editSingle'), ('dense', 'editSingle'),
             ('dense', 'editMulti'), ('dense', 'editInterleaved')]
COMMIT_COLUMNS = ['schedulerTime', 'totalCpu', 'geometryCpu',
                  'synchronizationCpu', 'indexCpu', 'invalidationCpu',
                  'validationCpu', 'resolvedCount', 'synchronizedCount']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate_backend(raw, variant):
    audit = raw['backendAudit']
    require(audit['resourceOverflow'] is False and audit['expectedBackend'] == variant,
            'backend resource evidence overflowed or requested backend differs')
    wasm = variant != 'canvaskit'
    multi = variant == 'skwasm-multi'
    isolated = variant != 'skwasm-single'
    require(audit['canvasKitLoaded'] is (not wasm), 'CanvasKit loaded probe disagrees with variant')
    require(audit['skwasmLoaded'] is wasm, 'skwasm loaded probe disagrees with variant')
    require(audit['skwasmIsMultiThreaded'] is (multi if wasm else None),
            'actual skwasm thread probe disagrees with variant')
    require(audit['crossOriginIsolated'] is isolated, 'unexpected origin isolation')
    require(type(audit['sharedArrayBufferAvailable']) is bool, 'missing SAB capability probe')
    if multi:
        require(audit['sharedArrayBufferAvailable'], 'multi-thread skwasm requires SAB capability')
    headers = audit['documentHeaders']
    if isolated:
        require(headers['coop'] == 'same-origin' and headers['coep'] == 'require-corp',
                'isolated experiment requires exact local COOP/COEP headers')
    else:
        require(headers['coop'] in (None, '') and headers['coep'] in (None, ''),
                'single-thread control must omit isolation headers')
    workers = audit['workerUrls']
    require(isinstance(workers, list) and all(isinstance(url, str) and url for url in workers),
            'invalid worker URL evidence')
    if multi:
        require(workers, 'multi-thread skwasm has no observed worker URL evidence')
    resources = audit['resources']
    require(isinstance(resources, list) and resources, 'missing engine resource evidence')
    successful_paths = []
    app_path = '/main.dart.wasm' if wasm else '/main.dart.js'
    require(any(urlparse(r['url']).path == app_path and 200 <= r['status'] < 300
                for r in resources), 'missing successful app compiler artifact response')
    for resource in resources:
        require(isinstance(resource['url'], str) and type(resource['status']) is int,
                'invalid resource response evidence')
        path = urlparse(resource['url']).path.lower()
        if ('canvaskit' in path or 'skwasm' in path) and path.endswith(('.js', '.wasm', '.mjs')):
            require(200 <= resource['status'] < 300 or resource['status'] == 304,
                    'failed engine resource response')
            successful_paths.append(path)
    engine = 'skwasm' if wasm else 'canvaskit'
    require(any(engine in path and path.endswith('.wasm') for path in successful_paths),
            f'no successful {engine} wasm response corroborates the loaded probe')


def validate_run(run, variant):
    require(run['compiler'] == ('dart2js' if variant == 'canvaskit' else 'dart2wasm'),
            'compiler disagrees with intended engine experiment')
    require(run['mode'] == 'profile' and run['platform'] == 'web' and run['optimized'] is True,
            'expected optimized web Profile capture')
    require(run['retainedExperiment'] is True and run['retainedEnabled'] is True,
            'vector retained experiment must be enabled')
    require(run['layersEnabled'] is False and run['layers'] is None,
            'on-screen layer experiment must be disabled')
    require(run['tilesEnabled'] is False and run['tiles'] is None,
            'tile cache must be disabled')
    require(run['overviewBytes'] == run['warmupMs'] == 0, 'overview or warmup contaminates control')
    require(run['viewportChanged'] is False and
            run['lifecycleChanges'] == run['viewFocusChanges'] == 0,
            'viewport, focus or lifecycle changed during capture')
    require(run['cpu']['commandToFirstPaintRecordMs'] > 0,
            'missing first-use CPU record clock')
    frames = run['frameSeriesMicros']
    require(isinstance(frames, list) and frames, 'missing frame series')
    require(all(len(row) == 4 and all(finite_number(v) and v >= 0 for v in row)
                for row in frames), 'invalid frame series samples')
    require(all(a[0] <= b[0] for a, b in zip(frames, frames[1:])),
            'frame scheduler timestamps regress')
    values = {'stage': [max(f[1], f[2]) for f in frames],
              'build': [f[1] for f in frames], 'raster': [f[2] for f in frames],
              'totalSpan': [f[3] for f in frames]}
    for name, samples in values.items():
        distribution = run['frames'][name]
        require(distribution['observed'] == distribution['retained'] == len(frames),
                f'{name} frame distribution truncated or incomplete')
        for key, value in quantiles(samples).items():
            if key != 'samples':
                require(finite_number(distribution[key]) and
                        math.isclose(distribution[key], value, abs_tol=0.000001),
                        f'{name}/{key} disagrees with complete frame series')
    count = 16 if run['workload'] in ('editMulti', 'editInterleaved') else 1
    ids, indices = run['activeEditIds'], run['activeEditPaintIndices']
    require(len(ids) == len(set(ids)) == count, 'wrong active edit ID count')
    require(len(indices) == count and indices == sorted(set(indices)) and
            all(type(i) is int and i >= 0 for i in indices), 'invalid active paint indices')
    if run['workload'] == 'editInterleaved':
        require(all(b - a > 1 for a, b in zip(indices, indices[1:])),
                'interleaved row does not span separated paint indices')
    require(run['commitSeriesColumns'] == COMMIT_COLUMNS, 'unexpected commit series schema')
    commits = run['commitSeriesMicros']
    require(commits and len(commits) == run['editCount'], 'incomplete commit series')
    require(all(len(c) == len(COMMIT_COLUMNS) and
                all(finite_number(v) and v >= 0 for v in c) and c[7] == c[8] == count
                for c in commits), 'commit width or resolved/synchronized counts disagree')
    require(all(a[0] <= b[0] for a, b in zip(commits, commits[1:])),
            'commit scheduler timestamps regress')
    cache = run['retained']
    require(cache['builds'] > 0 and cache['reuses'] > 0 and cache['disposed'] is False,
            'vector cache was not exercised or was disposed')
    require(cache['activeCount'] == count and cache['activeOverflow'] is False,
            'vector active membership overflow or mismatch')
    require(0 <= cache['approximateBytes'] <= cache['peakApproximateBytes'] <=
            cache['limitApproximateBytes'] == 16 * 1024 * 1024, 'vector byte bound violated')
    require(0 < cache['pictures'] <= cache['pictureLimit'] == 128 and
            cache['rangeSize'] == 256, 'vector picture count or chunk contract changed')
    require(cache['directFallbacks'] == 0 and cache['firstPaintRecordCpuMs'] is not None,
            'unexpected vector direct fallback or missing first-use record')
    require(run['imageSide'] == 1024 and run['imageOriginals'] == 4 and
            run['imageReferences'] == 100 and run['decodedPixelBytes'] == 16 * 1024 * 1024,
            'controlled image fixture changed')


def validate_reports(reports):
    """Return summaries only after all captures and matching controls validate."""
    for variant in VARIANTS:
        raw = reports[variant]
        try:
            require(raw['complete'] is False and raw['diagnosticComplete'] is True and
                    raw['boundedDiagnosticStopAfter'] == 4, 'expected bounded four-row diagnostic')
            require(not any(raw.get(k) for k in ('error', 'errors', 'collectorError', 'rpcErrors')),
                    'collector or runtime errors present')
            require([(r['scene'], r['workload']) for r in raw['runs']] == WORKLOADS,
                    'unexpected workload sequence')
            require(raw['environment']['gpuCompositing'] == 'enabled', 'hardware compositing unavailable')
            validate_backend(raw, variant)
            for run in raw['runs']:
                try:
                    validate_run(run, variant)
                except (KeyError, TypeError, ValueError) as error:
                    raise ValueError(f"{run['scene']}/{run['workload']}: {error}") from error
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f'{variant}: {error}') from error
    baseline = reports['canvaskit']
    for variant, raw in reports.items():
        require(raw['environment'] == baseline['environment'],
                f'{variant}: browser, GPU or browser viewport differs from baseline')
        for before, after in zip(baseline['runs'], raw['runs']):
            for field in ('viewport', 'activeEditIds', 'activeEditPaintIndices', 'imageReferences',
                          'imageSide', 'imageOriginals', 'decodedPixelBytes'):
                require(before[field] == after[field], f'{variant}: matched control differs: {field}')
            for field in ('visibleP50', 'visibleMax'):
                require(before['cpu'][field] == after['cpu'][field],
                        f'{variant}: visible density differs: {field}')
    output = {'boundedDiagnosticOnly': True, 'renderingGateQualified': False,
              'physicalInputOrPresentationValidated': False,
              'engineStageTimesArePresentationTimes': False,
              'originIsolationHeadersAreProductionRecommendation': False,
              'comparisonScope': 'Local profile engine/compiler/thread diagnostics with matched scenes; '
                                 'no isolation-only or compiler-only causal attribution.',
              'variants': {}}
    for variant, raw in reports.items():
        result = summarize(raw)
        result.update(environment=raw['environment'], backendAudit=raw['backendAudit'])
        for row, run in zip(result['runs'], raw['runs']):
            # Keep every received sample, not just selected quantiles.
            for field in ('compiler', 'retained', 'activeEditIds', 'activeEditPaintIndices',
                          'viewport', 'imageSide', 'imageOriginals', 'imageReferences',
                          'decodedPixelBytes', 'frameSeriesMicros', 'commitSeriesColumns',
                          'commitSeriesMicros', 'viewFocusChanges'):
                row[field] = run[field]
        output['variants'][variant] = result
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('benchmark_results/execution-04'))
    args = parser.parse_args()
    try:
        reports = {v: json.loads((args.root / f'web-{v}-vector.json').read_text()) for v in VARIANTS}
        output = validate_reports(reports)
    except (OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f'Backend diagnostics rejected: {error}\n')
    path = args.root / 'web-backends-summary.json'
    path.write_text(json.dumps(output, indent=2, allow_nan=False) + '\n')
    print(f'Validated matched bounded web backend diagnostics: {path}; rendering gate remains unqualified.')
    for index, name in enumerate(WORKLOADS):
        print('/'.join(name), {v: raw['runs'][index]['frames']['stage']['p95Ms']
                               for v, raw in reports.items()})


if __name__ == '__main__':
    main()
