import 'dart:convert';
import 'dart:typed_data';

import '../document/document.dart';
import '../document/document_codec.dart';
import '../document/document_geometry.dart';
import '../document/document_settings.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';
import '../viewport/camera.dart';
import 'board_store.dart';

const maximumPortableFileBytes = 64 * 1024 * 1024;
const maximumPortableAssetBytes = 16 * 1024 * 1024;
const maximumPortableOriginalBytes = 32 * 1024 * 1024;

/// Validated independent snapshot. CRC32 detects corruption, not authenticity.
final class PortableProject {
  PortableProject._(this.snapshot, Map<String, Uint8List> assets)
    : assets = Map.unmodifiable({
        for (final entry in assets.entries)
          entry.key: entry.value.asUnmodifiableView(),
      });

  final BoardSnapshot snapshot;
  final Map<String, Uint8List> assets;
}

Future<Uint8List> exportPortableProject(
  BoardSnapshot snapshot,
  BoardStore store,
) async {
  // Resolve all declarations before reading potentially large originals.
  DocumentCodec.encode(snapshot.document);
  final document = _referencedDocument(snapshot.document);
  final assets = <String, Uint8List>{};
  var totalBytes = 0;
  for (final reference in document.assets!) {
    final bytes = await store.readAsset(reference.id);
    if (bytes == null) {
      throw StateError(
        'Original image ${reference.id} is unavailable. Retry after restoring the image.',
      );
    }
    _validateOriginal(reference, bytes);
    totalBytes += bytes.length;
    if (totalBytes > maximumPortableOriginalBytes) {
      throw const FormatException(
        'Original images exceed the 32 MiB project limit.',
      );
    }
    assets[reference.id] = bytes;
  }
  final payload = jsonEncode({
    'document': DocumentCodec.encode(document),
    'camera': [
      snapshot.camera.translation.x,
      snapshot.camera.translation.y,
      snapshot.camera.zoom,
    ],
    'savedAt': snapshot.savedAt.toUtc().toIso8601String(),
    'assets': [
      for (final entry in assets.entries)
        {
          'id': entry.key,
          'byteLength': entry.value.length,
          'crc32': _crc32(entry.value),
          'data': base64Encode(entry.value),
        },
    ],
  });
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'blanko.project',
        'version': 1,
        'payload': payload,
        'crc32': _crc32(utf8.encode(payload)),
      }),
    ),
  );
  if (bytes.length > maximumPortableFileBytes) {
    throw const FormatException('Project file exceeds the 64 MiB limit.');
  }
  return bytes;
}

PortableProject decodePortableProject(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maximumPortableFileBytes) {
    throw const FormatException(
      'Project file must contain between 1 byte and 64 MiB.',
    );
  }
  try {
    final envelope = _object(_decodeJson(utf8.decode(bytes)), [
      'format',
      'version',
      'payload',
      'crc32',
    ]);
    if (envelope['format'] != 'blanko.project' || envelope['version'] != 1) {
      throw const FormatException(
        'Unsupported Blanko project version. The current board has not changed.',
      );
    }
    final payloadSource = _string(envelope['payload']);
    if (envelope['crc32'] != _crc32(utf8.encode(payloadSource))) {
      throw const FormatException(
        'Project checksum does not match. The file may be incomplete or corrupt.',
      );
    }
    final payload = _object(_decodeJson(payloadSource), [
      'document',
      'camera',
      'savedAt',
      'assets',
    ]);
    final document = DocumentCodec.decode(_string(payload['document']));
    final references = _validateReferences(document);
    final cameraValues = payload['camera'];
    if (cameraValues is! List ||
        cameraValues.length != 3 ||
        cameraValues.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('Invalid project viewport.');
    }
    final snapshot = BoardSnapshot(
      document: document,
      camera: Camera(
        translation: Point2(
          (cameraValues[0] as num).toDouble(),
          (cameraValues[1] as num).toDouble(),
        ),
        zoom: (cameraValues[2] as num).toDouble(),
      ),
      version: 1,
      savedAt: DateTime.parse(_string(payload['savedAt'])).toUtc(),
    );
    final values = payload['assets'];
    if (values is! List || values.length != references.length) {
      throw const FormatException(
        'Project must include exactly its referenced original images.',
      );
    }
    final assets = <String, Uint8List>{};
    var totalBytes = 0;
    for (final value in values) {
      final entry = _object(value, ['id', 'byteLength', 'crc32', 'data']);
      final id = _string(entry['id']);
      final reference = references[id];
      final length = entry['byteLength'];
      if (reference == null ||
          assets.containsKey(id) ||
          length is! int ||
          length < 1 ||
          length > maximumPortableAssetBytes) {
        throw const FormatException(
          'Invalid or duplicate original image declaration.',
        );
      }
      totalBytes += length;
      if (totalBytes > maximumPortableOriginalBytes) {
        throw const FormatException(
          'Original images exceed the 32 MiB project limit.',
        );
      }
      final encoded = _string(entry['data']);
      if (encoded.length != ((length + 2) ~/ 3) * 4) {
        throw const FormatException(
          'Original image size does not match its declaration.',
        );
      }
      final original = base64Decode(encoded);
      if (original.length != length || _crc32(original) != entry['crc32']) {
        throw const FormatException('Original image checksum does not match.');
      }
      _validateOriginal(reference, original);
      assets[id] = original;
    }
    return PortableProject._(snapshot, assets);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'Invalid Blanko project. The current board has not changed.',
    );
  }
}

/// Publishes a new independent board only after every original is durable.
/// A failed write may leave unattached assets; existing boards are untouched.
Future<BoardSnapshot> importPortableProject(
  PortableProject project,
  BoardStore store, {
  required String boardId,
  required String assetPrefix,
}) async {
  if (!store.writable) throw StateError('This workspace is read-only.');
  if (boardId.trim().isEmpty ||
      !RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(assetPrefix)) {
    throw ArgumentError(
      'A fresh board identity and safe asset prefix are required.',
    );
  }
  final source = project.snapshot.document;
  DocumentCodec.encode(source);
  final references = _validateReferences(source);
  if (references.length != project.assets.length) {
    throw const FormatException('Incomplete project originals.');
  }
  final remap = <String, String>{};
  var sequence = 0;
  var totalBytes = 0;
  for (final reference in references.values) {
    final bytes = project.assets[reference.id];
    if (bytes == null) throw const FormatException('Missing original image.');
    _validateOriginal(reference, bytes);
    totalBytes += bytes.length;
    remap[reference.id] = '$assetPrefix-${sequence++}';
  }
  if (totalBytes > maximumPortableOriginalBytes) {
    throw const FormatException('Project originals exceed 32 MiB.');
  }
  final document = BoardDocument(
    id: boardId,
    revision: source.revision,
    schemaVersion: source.schemaVersion,
    workspaceId: null,
    title: source.title,
    canvasSettings: source.canvasSettings,
    metadata: source.metadata,
    fontReferences: source.fontReferences,
    assets: [
      for (final reference in references.values)
        DocumentAssetReference(
          id: remap[reference.id]!,
          mimeType: reference.mimeType,
          pixelWidth: reference.pixelWidth,
          pixelHeight: reference.pixelHeight,
          byteLength: reference.byteLength,
        ),
    ],
    elements: [
      for (final element in source.elements)
        if (element.content case ImageElementContent(
          :final assetId,
          :final bounds,
        ))
          element.copyWith(
            content: ImageElementContent(
              assetId: remap[assetId]!,
              bounds: bounds,
            ),
          )
        else
          element,
    ],
  );
  DocumentGeometry(document);
  final snapshot = BoardSnapshot(
    document: document,
    camera: project.snapshot.camera,
    version: 1,
    savedAt: project.snapshot.savedAt,
  );
  snapshot.encode();
  // Complete validation, including collision checks, before the first mutation.
  if (await store.readBoard(boardId) != null) {
    throw const StorageConflict('Import requires a new board identity.');
  }
  for (final id in remap.values) {
    if (await store.readAsset(id) != null) {
      throw const StorageConflict(
        'Import asset identity already exists. Retry import.',
      );
    }
  }
  for (final entry in remap.entries) {
    await store.writeAsset(entry.value, project.assets[entry.key]!);
  }
  await store.writeBoard(snapshot, expectedVersion: null);
  return snapshot;
}

BoardDocument _referencedDocument(BoardDocument document) {
  final imageIds = <String>{};
  final fontIds = <String>{};
  for (final element in document.elements) {
    switch (element.content) {
      case ImageElementContent(:final assetId):
        imageIds.add(assetId);
      case TextElementContent(:final style) ||
          StickyNoteElementContent(:final style):
        fontIds.add(style.fontId);
      default:
        break;
    }
  }
  final result = BoardDocument(
    id: document.id,
    revision: document.revision,
    schemaVersion: document.schemaVersion,
    workspaceId: null,
    title: document.title,
    canvasSettings: document.canvasSettings,
    metadata: document.metadata,
    assets: [
      for (final asset in document.assets!)
        if (imageIds.contains(asset.id)) asset,
    ],
    fontReferences: [
      for (final font in document.fontReferences!)
        if (fontIds.contains(font.id)) font,
    ],
    elements: document.elements,
  );
  _validateReferences(result);
  return result;
}

Map<String, DocumentAssetReference> _validateReferences(
  BoardDocument document,
) {
  final imageIds = <String>{};
  for (final element in document.elements) {
    if (element.content case ImageElementContent(:final assetId)) {
      imageIds.add(assetId);
    }
  }
  final references = {
    for (final reference in document.assets ?? const <DocumentAssetReference>[])
      reference.id: reference,
  };
  if (references.length != imageIds.length ||
      !imageIds.every(references.containsKey)) {
    throw const FormatException(
      'Project may only declare original images referenced by its document.',
    );
  }
  for (final font
      in document.fontReferences ?? const <DocumentFontReference>[]) {
    if (font.id != 'editor-sans-v1' ||
        font.family != 'Roboto' ||
        font.assetId != null) {
      throw const FormatException(
        'This project uses an unsupported font. Only the bundled editor font is portable in this version.',
      );
    }
  }
  var declaredOriginalBytes = 0;
  for (final reference in references.values) {
    if (reference.sha256 != null) {
      throw const FormatException(
        'SHA256 asset declarations are not supported by this project version.',
      );
    }
    if (!const {
          'image/png',
          'image/jpeg',
          'image/webp',
          'image/gif',
          'image/bmp',
        }.contains(reference.mimeType.toLowerCase()) ||
        reference.byteLength == null ||
        reference.byteLength! > maximumPortableAssetBytes) {
      throw const FormatException(
        'Project image declarations require supported MIME types and original sizes up to 16 MiB.',
      );
    }
    declaredOriginalBytes += reference.byteLength!;
    if (declaredOriginalBytes > maximumPortableOriginalBytes) {
      throw const FormatException(
        'Original images exceed the 32 MiB project limit.',
      );
    }
  }
  return references;
}

void _validateOriginal(DocumentAssetReference reference, Uint8List bytes) {
  if (bytes.isEmpty ||
      bytes.length > maximumPortableAssetBytes ||
      bytes.length != reference.byteLength) {
    throw const FormatException(
      'Original image bytes do not match their declared length or exceed 16 MiB.',
    );
  }
}

Map<String, dynamic> _object(Object? value, List<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.length != fields.length ||
      !fields.every(value.containsKey)) {
    throw const FormatException('Missing or unsupported project fields.');
  }
  return value;
}

String _string(Object? value) => value is String
    ? value
    : throw const FormatException('Expected project text.');

Object? _decodeJson(String source) {
  // Bound nesting and reject duplicate fields before platform JSON decoding.
  final objects = <Set<String>?>[];
  final expectingKeys = <bool>[];
  for (var i = 0; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 34) {
      final start = i;
      var escaped = false;
      for (i++; i < source.length; i++) {
        final next = source.codeUnitAt(i);
        if (!escaped && next == 34) break;
        if (!escaped && next == 92) {
          escaped = true;
        } else {
          escaped = false;
        }
      }
      if (i >= source.length) {
        throw const FormatException('Unterminated project string.');
      }
      if (objects.isNotEmpty && expectingKeys.last && objects.last != null) {
        if (!objects.last!.add(
          jsonDecode(source.substring(start, i + 1)) as String,
        )) {
          throw const FormatException('Duplicate project field.');
        }
        expectingKeys[expectingKeys.length - 1] = false;
      }
    } else if (code == 123 || code == 91) {
      objects.add(code == 123 ? <String>{} : null);
      expectingKeys.add(code == 123);
      if (objects.length > 16) {
        throw const FormatException('Excessive project nesting.');
      }
    } else if (code == 125 || code == 93) {
      if (objects.isEmpty) {
        throw const FormatException('Unbalanced project JSON.');
      }
      objects.removeLast();
      expectingKeys.removeLast();
    } else if (code == 44 && objects.isNotEmpty && objects.last != null) {
      expectingKeys[expectingKeys.length - 1] = true;
    }
  }
  return jsonDecode(source);
}

final _crcTable = List<int>.generate(256, (value) {
  var crc = value;
  for (var bit = 0; bit < 8; bit++) {
    crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return crc;
}, growable: false);

String _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}
