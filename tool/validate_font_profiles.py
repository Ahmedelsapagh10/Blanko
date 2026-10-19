"""Audit fixed-font profile evidence without qualifying the rendering gate."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
from urllib.parse import urlparse

from run_font_profiles import FONT_ID, FONT_NAMES, validate_font_capture
from summarize_phase03 import quantiles
from summarize_web_backends import (
    COMMIT_COLUMNS, WORKLOADS, finite_number, require, validate_backend,
)


VARIANTS = ('direct', 'vector', 'layers')
MIB = 1024 * 1024
ORIGIN = ('http', '127.0.0.1:8765')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate_fonts(raw):
    validate_font_capture(raw)
    audit = raw['fontAudit']
    require(set(audit['expected']) == FONT_NAMES and len(audit['expected']) == 4,
            'unexpected requested font manifest')
    # Corroborate the collector flags against every observed request, including
    # foreign requests whose externalRequests classification was falsified.
    for request in audit['requests']:
        url = urlparse(request['url'])
        require((url.scheme, url.netloc) == ORIGIN, 'foreign font request')
        require(request['status'] == 200 and not request.get('failure'),
                'font transfer failure')
        require(all(finite_number(request[k]) for k in ('startedAt', 'finishedAt')) and
                0 <= request['startedAt'] <= request['finishedAt'] <= audit['firstReadyAt'],
                'observed font transfer did not finish before first READY')
    require(len(raw['ready']) == 5, 'missing scene READY record')
    for row in raw['ready'] + [run['load'] for run in raw['runs']]:
        require(row['fonts']['families'] ==
                ['WhiteboardBenchmarkLatin', 'WhiteboardBenchmarkArabic'],
                'unexpected registered font families')


def validate_run(run, variant):
    require(run['compiler'] == 'dart2js', 'unknown or unexpected compiler')
    require(run['platform'] == 'web' and run['mode'] == 'profile' and
            run['optimized'] is True, 'expected optimized web Profile capture')
    require(run['recovery'] is False and run['dirtyRepair'] is False and
            run['retainedExperiment'] is True, 'unexpected remediation mode')
    require(run['retainedEnabled'] is (variant == 'vector') and
            run['layersEnabled'] is (variant == 'layers'), 'wrong cache experiment arm')
    require(run['tilesEnabled'] is False and run['tiles'] is None and
            run['overviewBytes'] == run['warmupMs'] == 0, 'warmup/overview/tile control changed')
    require(run['viewportChanged'] is False and
            run['lifecycleChanges'] == run['viewFocusChanges'] == 0,
            'viewport, lifecycle or focus contamination')
    require(run['viewport'] == dict(canvasWidth=1200, canvasHeight=542,
                                    windowWidth=1200, windowHeight=796, dpr=1),
            'unexpected canvas viewport')
    visible = 199 if run['scene'] == 'normal' else 5638
    require(run['cpu']['visibleP50'] == run['cpu']['visibleMax'] == visible,
            'visible density changed')
    require(run['imageSide'] == 1024 and run['imageOriginals'] == 4 and
            run['imageReferences'] == 100 and run['decodedPixelBytes'] == 16 * MIB,
            'controlled image fixture changed')
    require(run['textLayouts'] == 2000, 'text fixture changed')
    require(finite_number(run['cpu']['commandToFirstPaintRecordMs']) and
            run['cpu']['commandToFirstPaintRecordMs'] > 0, 'missing first-use recording clock')
    frames = run['frameSeriesMicros']
    require(isinstance(frames, list) and frames and
            all(len(f) == 4 and all(finite_number(v) and v >= 0 for v in f) for f in frames),
            'invalid complete four-column frame series')
    require(all(a[0] <= b[0] for a, b in zip(frames, frames[1:])),
            'frame scheduler timestamps regress')
    distributions = {}
    for name, samples in dict(build=[f[1] for f in frames], raster=[f[2] for f in frames],
                              stage=[max(f[1], f[2]) for f in frames],
                              totalSpan=[f[3] for f in frames]).items():
        reported = run['frames'][name]
        require(reported['observed'] == reported['retained'] == len(frames),
                f'{name}: omitted or truncated frames')
        distribution = quantiles(samples)
        for key, expected in distribution.items():
            if key != 'samples':
                require(finite_number(reported[key]) and
                        math.isclose(reported[key], expected, abs_tol=0.000001),
                        f'{name}/{key}: quantile differs from full series')
        distributions[name] = distribution
    count = 16 if run['workload'] in ('editMulti', 'editInterleaved') else 1
    ids, indices = run['activeEditIds'], run['activeEditPaintIndices']
    require(len(ids) == len(set(ids)) == count and all(isinstance(i, str) and i for i in ids),
            'active edit IDs malformed')
    require(len(indices) == count and indices == sorted(set(indices)) and
            all(type(i) is int and i >= 0 for i in indices), 'active paint indices malformed')
    if run['workload'] == 'editInterleaved':
        require(all(b - a > 1 for a, b in zip(indices, indices[1:])),
                'interleaved IDs do not span separated paint indices')
    require(run['commitSeriesColumns'] == COMMIT_COLUMNS, 'unknown commit series schema')
    commits = run['commitSeriesMicros']
    require(commits and len(commits) == run['editCount'] and
            all(len(c) == 9 and all(finite_number(v) and v >= 0 for v in c) and
                c[7] == c[8] == count for c in commits), 'incomplete or invalid commit series')
    require(all(a[0] <= b[0] for a, b in zip(commits, commits[1:])),
            'commit scheduler timestamps regress')
    if variant == 'vector':
        cache = run['retained']
        require(run['layers'] is None and cache['disposed'] is False and
                cache['builds'] > 0 and cache['reuses'] > 0 and
                cache['directFallbacks'] == 0, 'vector cache not exercised safely')
        require(cache['activeCount'] == count and cache['activeOverflow'] is False,
                'vector active overflow')
        require(0 <= cache['approximateBytes'] <= cache['peakApproximateBytes'] <=
                cache['limitApproximateBytes'] == 16 * MIB and
                0 < cache['pictures'] <= cache['pictureLimit'] == 128 and cache['rangeSize'] == 256,
                'vector memory or picture cap changed')
    elif variant == 'layers':
        cache = run['layers']
        require(run['retained'] is None and cache['disposed'] is False and
                cache['activeCount'] == count and cache['activeOverflow'] is False,
                'layer ownership/active overflow')
        require(0 <= cache['layers'] <= cache['layerLimit'] == 33 and
                0 <= cache['approximatePictureBytes'] <= cache['peakApproximatePictureBytes'] <=
                cache['pictureByteLimit'] == 16 * MIB and
                0 <= cache['estimatedRasterExposureBytes'] <= cache['peakEstimatedRasterExposureBytes'] <=
                cache['rasterEstimateLimit'] == 64 * MIB and
                cache['rasterEstimateAllocationFactor'] == 2, 'layer memory or layer cap changed')
        if run['workload'] == 'editInterleaved':
            require(cache['directFallbacks'] > 0 and cache['layers'] == cache['reuses'] ==
                    cache['approximatePictureBytes'] == cache['estimatedRasterExposureBytes'] == 0 and
                    cache['firstPaintRecordCpuMs'] is None and
                    cache['engineSubmissions'] <= cache['builds'], 'unsafe interleaved fallback')
        else:
            require(cache['directFallbacks'] == 0 and cache['builds'] > 0 and cache['reuses'] > 0 and
                    0 < cache['engineSubmissions'] <= cache['builds'] and
                    cache['firstPaintRecordCpuMs'] is not None, 'layer subtree not exercised')
    else:
        require(run['retained'] is None and run['layers'] is None, 'direct arm contains a cache')
    return {'scene': run['scene'], 'workload': run['workload'], 'frames': distributions,
            'commitCount': len(commits), 'resolvedAndSynchronizedCount': count,
            'stageFramesOver16_7ms': sum(max(f[1], f[2]) > 16700 for f in frames)}


def validate_reports(reports, manifest, startup):
    require(manifest['complete'] is True and manifest['summaryExitCode'] == 0 and
            manifest['renderingGateQualified'] is False and not manifest.get('error'),
            'profile runner incomplete or failed')
    require([r['variant'] for r in manifest['runs']] == list(VARIANTS), 'profile arms missing')
    baseline = reports['direct']
    output = {}
    for variant, capture in zip(VARIANTS, manifest['runs']):
        raw = reports[variant]
        require(raw['complete'] is False and raw['diagnosticComplete'] is True and
                raw['boundedDiagnosticStopAfter'] == 4, 'not the bounded four-row diagnostic')
        require(not any(raw.get(k) for k in ('error', 'errors', 'collectorError', 'rpcErrors')),
                'collector/runtime errors')
        require([(r['scene'], r['workload']) for r in raw['runs']] == WORKLOADS,
                'incomplete workload sequence')
        require(raw['environment'] == baseline['environment'] and
                raw['environment']['gpuCompositing'] == 'enabled', 'browser/GPU controls differ')
        validate_backend(raw, 'canvaskit')
        validate_fonts(raw)
        require(capture['buildExitCode'] == capture['collectorExitCode'] == 0 and
                capture['sourceHashesUnchanged'] is capture['fontCaptureValidated'] is
                capture['ownedServerStopped'] is True, 'runner did not validate/close its arm')
        artifacts = capture['binaryHashesBeforeCapture']
        require(all(isinstance(h, str) and re.fullmatch('[0-9a-f]{64}', h)
                    for h in artifacts.values()), 'invalid artifact SHA-256')
        for response in raw['backendAudit']['resources']:
            url = urlparse(response['url'])
            require((url.scheme, url.netloc) == ORIGIN and url.path.lstrip('/') in artifacts,
                    'observed engine/compiler artifact lacks before-capture provenance')
        require(all(k in artifacts for k in ('assets/FontManifest.json', 'assets/AssetManifest.bin')),
                'missing compiled asset manifests')
        output[variant] = [validate_run(run, variant) for run in raw['runs']]
        for before, after in zip(baseline['runs'], raw['runs']):
            for field in ('viewport', 'activeEditIds', 'activeEditPaintIndices', 'imageSide',
                          'imageOriginals', 'imageReferences', 'decodedPixelBytes'):
                require(before[field] == after[field], f'matched control differs: {field}')
    require(startup['diagnosticOnly'] is True and startup['renderingGateQualified'] is False and
            startup['blockedExternal'] == startup['errors'] == startup['console'] == [],
            'local-only startup incomplete or external/error contamination')
    require(startup['firstReady']['fonts']['ready'] is True and
            startup['firstReady']['fonts']['manifest'] == FONT_ID, 'startup fonts not ready')
    require(finite_number(startup['navigationToReadyWallMs']) and
            startup['navigationToReadyWallMs'] > 0, 'missing startup ready timestamp')
    fonts = set()
    for request in startup['requests']:
        url = urlparse(request['url'])
        require((url.scheme, url.netloc) == ORIGIN, 'foreign startup request')
        require(request.get('status') == 200 and not request.get('failure'),
                'startup request not successful')
        require(finite_number(request['endMs']) and
                0 <= request['startMs'] <= request['endMs'] <= startup['navigationToReadyWallMs'],
                'startup request unfinished at READY')
        if url.path.startswith('/assets/assets/benchmark_fonts/'):
            fonts.add(url.path.rsplit('/', 1)[-1])
    require(fonts == FONT_NAMES, 'startup missing fixed-font transfers')
    return output


def read_asset_manifest(data):
    """Read only string/list/map values used by this captured Flutter manifest."""
    cursor = 0

    def size():
        nonlocal cursor
        first = data[cursor]
        cursor += 1
        if first < 254:
            return first
        width = 2 if first == 254 else 4
        value = int.from_bytes(data[cursor:cursor + width], 'little')
        cursor += width
        return value

    def read():
        nonlocal cursor
        tag = data[cursor]
        cursor += 1
        count = size()
        if tag == 7:
            result = data[cursor:cursor + count].decode('utf-8')
            cursor += count
            return result
        if tag == 12:
            return [read() for _ in range(count)]
        if tag == 13:
            return {read(): read() for _ in range(count)}
        raise ValueError('unsupported captured AssetManifest value tag')

    result = read()
    require(cursor == len(data), 'AssetManifest trailing or incomplete bytes')
    return result


def validate_files(manifest, font_audit, asset_manifest):
    require(font_audit['passed'] is True and asset_manifest['id'] == FONT_ID ==
            font_audit['manifestId'], 'font integrity audit or identity failed')
    require(sha256('assets/benchmark_fonts/manifest.json') == font_audit['manifestSha256'],
            'font asset manifest digest changed')
    for path, expected in manifest['sourceHashes'].items():
        require(sha256(path) == expected, f'captured source changed: {path}')
    fonts = {a['path']: a for a in font_audit['assets']}
    require(set(fonts) == {a['path'] for a in asset_manifest['assets']}, 'font asset set differs')
    for asset in asset_manifest['assets']:
        path = asset['path']
        require(sha256(path) == asset['sha256'] == fonts[path]['sha256'] and
                Path(path).stat().st_size == asset['bytes'] == fonts[path]['bytes'],
                'trusted source font digest or size differs')
        require(sha256(asset['licensePath']) == asset['licenseSha256'] ==
                fonts[path]['licenseSha256'], 'trusted font license digest differs')
        require(fonts[path]['missingRequiredCodepoints'] == [], 'required font corpus not covered')
        for capture in manifest['runs']:
            hashes = capture['binaryHashesBeforeCapture']
            require(hashes['assets/' + path] == asset['sha256'],
                    'compiled font digest differs from trusted source')
            require(hashes['assets/assets/benchmark_fonts/manifest.json'] ==
                    font_audit['manifestSha256'], 'compiled font asset manifest differs')
    # Earlier app/bootstrap files were overwritten by later builds. Their recorded
    # hashes remain evidence; current final-arm bytes can be checked independently.
    final_hashes = manifest['runs'][-1]['binaryHashesBeforeCapture']
    for path, expected in final_hashes.items():
        require(sha256(Path('build/web') / path) == expected, f'final compiled artifact changed: {path}')
    stable_keys = set(final_hashes) - {'main.dart.js', 'flutter_bootstrap.js'}
    require(all(all(c['binaryHashesBeforeCapture'].get(k) == final_hashes[k] for k in stable_keys)
                for c in manifest['runs']), 'engine/font/asset bytes differ across arms')
    compiled = read_asset_manifest(Path('build/web/assets/AssetManifest.bin').read_bytes())
    for asset in asset_manifest['assets']:
        require(compiled[asset['path']] == [{'asset': asset['path']}],
                'compiled asset manifest omitted or remapped fixed font')
    default_fonts = json.loads(Path('build/web/assets/FontManifest.json').read_text())
    roboto = [entry for entry in default_fonts if entry['family'] == 'Roboto']
    require(roboto == [{'family': 'Roboto', 'fonts': [{'asset': 'assets/benchmark_fonts/Roboto-Regular.ttf'}]}],
            'engine default Roboto alias is not pinned locally')
    return {'capturedSourceHashesVerified': len(manifest['sourceHashes']),
            'finalCompiledArtifactsVerified': len(final_hashes),
            'stableEngineAndAssetArtifactsMatchedAcrossArms': len(stable_keys),
            'trustedFontAssetsVerified': len(fonts), 'compiledAssetManifestDecoded': True}


def negative_checks(reports, manifest, startup, font_audit, asset_manifest):
    checks = []

    def reject(name, change):
        r, m, s, f, a = copy.deepcopy((reports, manifest, startup, font_audit, asset_manifest))
        change(r, m, s, f, a)
        try:
            validate_reports(r, m, s)
            validate_files(m, f, a)
        except (ValueError, KeyError, TypeError, IndexError) as error:
            checks.append({'case': name, 'rejected': True, 'reason': str(error)})
            return
        raise ValueError('Malformed evidence was accepted: ' + name)

    reject('omitted frame', lambda r, *_: r['direct']['runs'][0]['frameSeriesMicros'].pop())
    reject('wrong raster P95', lambda r, *_: r['vector']['runs'][1]['frames']['raster'].update(p95Ms=0))
    reject('font finished after READY', lambda r, *_: r['layers']['fontAudit']['requests'][-1].update(
        finishedAt=r['layers']['fontAudit']['firstReadyAt'] + 1))
    reject('foreign font despite empty externalRequests', lambda r, *_: r['direct']['fontAudit']['requests'][0].update(
        url='https://fonts.gstatic.com/foreign.ttf'))
    reject('wrong font manifest', lambda r, *_: r['vector']['runs'][0]['load']['fonts'].update(manifest='other'))
    reject('unknown compiler', lambda r, *_: r['direct']['runs'][0].update(compiler='unknown'))
    reject('focus control contamination', lambda r, *_: r['layers']['runs'][1].update(viewFocusChanges=1))
    reject('vector memory cap raised', lambda r, *_: r['vector']['runs'][1]['retained'].update(limitApproximateBytes=32 * MIB))
    reject('layer raster cap exceeded', lambda r, *_: r['layers']['runs'][1]['layers'].update(peakEstimatedRasterExposureBytes=65 * MIB))
    reject('failed engine resource', lambda r, *_: r['direct']['backendAudit']['resources'][1].update(status=500))
    reject('observed engine route not hashed before capture', lambda r, m, *_:
           m['runs'][0]['binaryHashesBeforeCapture'].pop('canvaskit/chromium/canvaskit.wasm'))
    reject('compiled font hash differs', lambda r, m, *_:
           m['runs'][0]['binaryHashesBeforeCapture'].update({'assets/assets/benchmark_fonts/Roboto-Regular.ttf': '0' * 64}))
    reject('partial commit series', lambda r, *_: r['vector']['runs'][2]['commitSeriesMicros'].pop())
    reject('wrong resolved count', lambda r, *_: r['layers']['runs'][2]['commitSeriesMicros'][0].__setitem__(7, 1))
    reject('different active IDs', lambda r, *_: r['vector']['runs'][0].update(activeEditIds=['different']))
    reject('visible density changed', lambda r, *_: r['direct']['runs'][1]['cpu'].update(visibleMax=10000))
    reject('local-only startup attempted external resource', lambda r, m, s, *_:
           s['blockedExternal'].append('https://example.com/font.ttf'))
    reject('trusted font asset manifest changed', lambda r, m, s, f, a:
           a['assets'][0].update(sha256='0' * 64))
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('benchmark_results/execution-05'))
    args = parser.parse_args()
    root = args.root
    try:
        reports = {v: json.loads((root / f'web-{v}.json').read_text()) for v in VARIANTS}
        manifest = json.loads((root / 'profile-manifest.json').read_text())
        startup = json.loads((root / 'startup-local-only.json').read_text())
        font_audit = json.loads((root / 'font-assets.json').read_text())
        asset_manifest = json.loads(Path('assets/benchmark_fonts/manifest.json').read_text())
        rows = validate_reports(reports, manifest, startup)
        files = validate_files(manifest, font_audit, asset_manifest)
        negatives = negative_checks(reports, manifest, startup, font_audit, asset_manifest)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        parser.exit(1, f'Fixed-font evidence rejected: {error}\n')
    output = {'passed': True, 'boundedDiagnosticOnly': True, 'renderingGateQualified': False,
              'physicalInputOrPresentationValidated': False,
              'alignedSubpixelTextFidelityQualified': False,
              'comparison': 'New fixed-font baseline; historical differences do not isolate font causation.',
              'environment': reports['direct']['environment'], 'files': files,
              'variants': rows, 'fontRequestsFinishedBeforeReady': True,
              'externalFontRequestsObserved': 0, 'localOnlyStartupPassed': True,
              'localOnlyStartupToReadyWallMs': startup['navigationToReadyWallMs'],
              'negativeChecks': negatives,
              'auditToolNotPresentAtCapture': {'path': 'tool/validate_font_profiles.py',
                                             'sha256': sha256(__file__)},
              'limitations': [
                  'Engine frame stages and totalSpan are not presentation or physical input latency.',
                  'Four edit rows do not qualify navigation, cold caches, long-running memory or the full gate.',
                  'Dense viewport has 5,638 visible elements in a 10,000-element document.',
                  'Font glyph coverage/readiness is not complete visual fidelity or arbitrary Unicode coverage.',
                  'Before-capture artifact digests are runner records, not independent network body digests.',
                  'Earlier app/bootstrap bytes were overwritten; final-arm and stable engine/font bytes remain checked.',
                  'Raster exposure caps are estimates, not measured total GPU memory.',
              ]}
    path = root / 'font-profile-validation.json'
    path.write_text(json.dumps(output, indent=2, allow_nan=False) + '\n')
    print(f'Validated 12 fixed-font profile rows and {len(negatives)} rejected negative cases: {path}')
    for i, name in enumerate(WORKLOADS):
        print('/'.join(name), {v: rows[v][i]['frames']['stage']['p95Ms'] for v in VARIANTS})


if __name__ == '__main__':
    main()
