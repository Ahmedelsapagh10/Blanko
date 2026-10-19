"""Audit pinned local font bytes and fixture glyph coverage; not shaping proof."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'assets/benchmark_fonts/manifest.json'
ASCII_UI = set(range(32, 127)) | {ord('·'), ord('…')}
ARABIC = {ord(char) for char in 'فكرة جديدة'}
EXPECTED = {
    'Roboto-Regular.ttf': (400, '3.015'),
    'Roboto-Medium.ttf': (500, '3.015'),
    'Roboto-Bold.ttf': (700, '3.015'),
    'NotoSansArabic-Regular.ttf': (400, '2.012'),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_slice(data, offset, length):
    require(0 <= offset <= len(data) and 0 <= length <= len(data) - offset,
            'sfnt offset or length is outside the containing table')
    return data[offset:offset + length]


def number(data, offset, fmt='H'):
    return struct.unpack('>' + fmt, read_slice(data, offset, struct.calcsize(fmt)))[0]


def tables(data):
    require(data[:4] == b'\x00\x01\x00\x00', 'expected a TrueType sfnt')
    result = {}
    for index in range(number(data, 4)):
        tag, checksum, offset, length = struct.unpack(
            '>4sIII', read_slice(data, 12 + index * 16, 16))
        tag = tag.decode('ascii')
        require(tag not in result, 'duplicate sfnt table')
        result[tag] = (read_slice(data, offset, length),
                       {'offset': offset, 'bytes': length, 'checksum': checksum})
    return result


def names(data):
    records = []
    storage = number(data, 4)
    for index in range(number(data, 2)):
        platform, encoding, language, name_id, length, offset = struct.unpack(
            '>6H', read_slice(data, 6 + index * 12, 12))
        if name_id not in (1, 2, 5, 6, 16, 17):
            continue
        raw = read_slice(data, storage + offset, length)
        if platform in (0, 3):
            value = raw.decode('utf-16-be')
        elif platform == 1 and encoding == 0:
            value = raw.decode('mac_roman')
        else:
            continue
        records.append({'id': name_id, 'platform': platform, 'encoding': encoding,
                        'language': language, 'value': value})
    return records


def cmap_subtables(data):
    result = []
    for index in range(number(data, 2)):
        platform, encoding, offset = struct.unpack(
            '>HHI', read_slice(data, 4 + index * 8, 8))
        if not (platform == 0 or platform == 3 and encoding in (1, 10)):
            continue
        fmt = number(data, offset)
        if fmt not in (4, 12):
            continue
        length = number(data, offset + (2 if fmt == 4 else 4),
                        'H' if fmt == 4 else 'I')
        result.append((read_slice(data, offset, length),
                       {'platform': platform, 'encoding': encoding, 'format': fmt}))
    require(result, 'no supported Unicode cmap format 4 or 12')
    return result


def glyph_id(data, point):
    if number(data, 0) == 12:
        for index in range(number(data, 12, 'I')):
            start, end, glyph = struct.unpack('>III', read_slice(data, 16 + index * 12, 12))
            require(start <= end <= 0x10ffff, 'invalid cmap 12 group')
            if start <= point <= end:
                return glyph + point - start
        return 0
    if point > 0xffff:
        return 0
    count_x2 = number(data, 6)
    require(count_x2 > 0 and count_x2 % 2 == 0, 'invalid cmap 4 segment count')
    count = count_x2 // 2
    for index in range(count):
        end = number(data, 14 + index * 2)
        start = number(data, 16 + count * 2 + index * 2)
        if not start <= point <= end:
            continue
        delta = number(data, 16 + count * 4 + index * 2, 'h')
        range_address = 16 + count * 6 + index * 2
        range_offset = number(data, range_address)
        if not range_offset:
            return (point + delta) & 0xffff
        glyph = number(data, range_address + range_offset + (point - start) * 2)
        return (glyph + delta) & 0xffff if glyph else 0
    return 0


def coverage(subtables, points, glyph_count):
    present = set()
    for point in points:
        glyphs = [glyph_id(data, point) for data, _ in subtables]
        require(all(glyph < glyph_count for glyph in glyphs), 'cmap references invalid glyph')
        if any(glyphs):
            present.add(point)
    return present


def require_coverage(present, required):
    missing = sorted(required - present)
    require(not missing, 'missing required glyphs: ' + ', '.join(f'U+{p:04X}' for p in missing))


def audit(manifest):
    require(manifest['id'] == 'roboto-3.015-noto-sans-arabic-2.012-v1', 'unexpected manifest ID')
    require(manifest['license'] == 'SIL Open Font License 1.1', 'unexpected license')
    require(len(manifest['assets']) == len(EXPECTED), 'unexpected font asset count')
    results = []
    seen = set()
    for asset in manifest['assets']:
        path = Path(asset['path'])
        filename = path.name
        require(path.parent.as_posix() == 'assets/benchmark_fonts' and filename in EXPECTED,
                'unexpected font asset path')
        require(filename not in seen, 'duplicate asset')
        seen.add(filename)
        data = (ROOT / path).read_bytes()
        require(len(data) == asset['bytes'], filename + ': byte length mismatch')
        require(sha256(data) == asset['sha256'], filename + ': SHA-256 mismatch')
        license_path = Path(asset['licensePath'])
        require(license_path.parent.as_posix() == 'assets/benchmark_fonts', 'unexpected license path')
        license_bytes = (ROOT / license_path).read_bytes()
        require(sha256(license_bytes) == asset['licenseSha256'], 'license SHA-256 mismatch')
        license_text = license_bytes.decode('utf-8')
        require('Copyright' in license_text and
                'SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007' in license_text and
                'This Font Software is licensed under the SIL Open Font License, Version 1.1.' in license_text,
                'missing copyright/OFL notice')
        directory = tables(data)
        name_records = names(directory['name'][0])
        weight = number(directory['OS/2'][0], 4)
        expected_weight, version = EXPECTED[filename]
        require(weight == expected_weight, 'unexpected OS/2 weight')
        versions = sorted({entry['value'] for entry in name_records if entry['id'] == 5})
        require(versions and all(version in value for value in versions), 'unexpected font version')
        arabic = filename.startswith('Noto')
        if arabic:
            require('GSUB' in directory and 'GPOS' in directory, 'Arabic requires GSUB and GPOS')
        required = ARABIC if arabic else ASCII_UI
        subtables = cmap_subtables(directory['cmap'][0])
        present = coverage(subtables, ASCII_UI | ARABIC, number(directory['maxp'][0], 4))
        require_coverage(present, required)
        results.append({
            'path': path.as_posix(), 'bytes': len(data), 'sha256': sha256(data),
            'licensePath': license_path.as_posix(), 'licenseSha256': sha256(license_bytes),
            'copyright': license_text.splitlines()[0], 'weightClass': weight,
            'versions': versions, 'nameRecords': name_records,
            'tables': {tag: metadata for tag, (_, metadata) in sorted(directory.items())},
            'unicodeCmaps': [metadata for _, metadata in subtables],
            'requiredCodepoints': [f'U+{point:04X}' for point in sorted(required)],
            'coveredCorpusCodepoints': [f'U+{point:04X}' for point in sorted(present)],
            'missingRequiredCodepoints': [], 'hasGSUB': 'GSUB' in directory,
            'hasGPOS': 'GPOS' in directory,
        })
    return results


def negative_checks(manifest):
    tests = []
    bad_hash = copy.deepcopy(manifest)
    bad_hash['assets'][0]['sha256'] = '0' * 64
    bad_license = copy.deepcopy(manifest)
    bad_license['assets'][0]['licenseSha256'] = '0' * 64
    for label, operation in (
        ('tampered font hash', lambda: audit(bad_hash)),
        ('tampered license hash', lambda: audit(bad_license)),
        ('missing literal backslash coverage', lambda: require_coverage(ASCII_UI - {92}, ASCII_UI)),
        ('missing Arabic glyph coverage', lambda: require_coverage(ARABIC - {ord('ف')}, ARABIC)),
    ):
        try:
            operation()
        except ValueError as error:
            tests.append({'case': label, 'rejected': True, 'reason': str(error)})
        else:
            raise ValueError('negative check accepted: ' + label)
    return tests


def prepare_web_tests(assets):
    """Regenerate ignored copies served by Flutter's Chrome test harness."""
    destination = ROOT / 'test/benchmark_font_assets'
    require(not destination.is_symlink(), 'test font fixture directory must not be a symlink')
    prepared = []
    for asset in assets:
        source = ROOT / asset['path']
        data = source.read_bytes()
        require(len(data) == asset['bytes'] and sha256(data) == asset['sha256'],
                'source font changed after audit: ' + asset['path'])
        target = destination / source.name
        require(not target.is_symlink(), 'test font fixture must not be a symlink')
        prepared.append((target, data, asset['sha256']))
    destination.mkdir(parents=True, exist_ok=True)
    for target, data, expected_hash in prepared:
        target.write_bytes(data)
        require(sha256(target.read_bytes()) == expected_hash,
                'copied test font SHA-256 mismatch: ' + str(target))
    print(f'Prepared and hash-verified {len(prepared)} generated Chrome test fonts in {destination}. '
          'Regenerate with --prepare-web-tests after checkout or generated-fixture cleanup.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'benchmark_results/execution-05/font-assets.json')
    parser.add_argument('--prepare-web-tests', action='store_true',
                        help='After auditing, regenerate ignored TTF copies under test/benchmark_font_assets '
                             'for Flutter Chrome tests; run after checkout or fixture cleanup.')
    args = parser.parse_args()
    manifest_bytes = (ROOT / MANIFEST).read_bytes()
    manifest = json.loads(manifest_bytes)
    report = {
        'manifest': MANIFEST, 'manifestId': manifest['id'],
        'manifestSha256': sha256(manifest_bytes),
        'scope': 'Local pinned font asset integrity, metadata and nonzero glyph coverage only.',
        'corpus': {'ascii': 'U+0020..U+007E inclusive, including literal backslash U+005C',
                   'arabic': 'فكرة جديدة', 'additionalUi': '·…'},
        'limitations': [
            'Does not verify Arabic shaping, visual fidelity, text metrics or browser font readiness.',
            'Does not establish coverage of arbitrary user text or Unicode.',
            'Release archive hashes and source commits are recorded provenance, not re-downloaded by this audit.',
        ],
        'assets': audit(manifest), 'negativeChecks': negative_checks(manifest), 'passed': True,
    }
    if args.prepare_web_tests:
        prepare_web_tests(report['assets'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(f'PASS: {len(report["assets"])} font assets; {len(report["negativeChecks"])} malformed cases rejected; {args.output}')


if __name__ == '__main__':
    main()
