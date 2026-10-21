import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../document/document.dart';
import '../document/document_codec.dart';
import '../document/document_geometry.dart';
import '../document/document_settings.dart';
import '../document/element.dart';
import '../persistence/board_store.dart';
import '../persistence/portable_project.dart'
    show maximumPortableAssetBytes, maximumPortableOriginalBytes;

/// App-owned clipboard. Original bytes outlive their source board; no OS access.
/// Paste stages assets only. The caller commits the returned forest atomically.
final class EditorClipboard extends ChangeNotifier {
  _ClipboardContent? _content;
  int _generation = 0;
  bool _disposed = false;

  bool get hasContent => !_disposed && _content != null;

  Future<void> copy(
    BoardDocument document,
    Iterable<ElementId> roots,
    BoardStore? store,
  ) async {
    if (_disposed) throw StateError('Clipboard is closed.');
    final generation = ++_generation;
    final requested = roots.toSet();
    if (requested.isEmpty ||
        requested.any((id) => !document.byId.containsKey(id))) {
      throw StateError('Select existing elements to copy.');
    }
    final rootIds = requested.where((id) {
      var parent = document.byId[id]!.parentId;
      while (parent != null) {
        if (requested.contains(parent)) return false;
        parent = document.byId[parent]!.parentId;
      }
      return true;
    }).toSet();
    final included = <ElementId>{};
    for (final element in document.preorder) {
      if (rootIds.contains(element.id) || included.contains(element.parentId)) {
        included.add(element.id);
      }
    }
    final geometry = DocumentGeometry(document);
    final elements = <DocumentElement>[];
    final imageIds = <String>{}, fontIds = <String>{};
    for (final element in document.elements) {
      if (!included.contains(element.id)) continue;
      final content = element.content;
      switch (content) {
        case ImageElementContent(:final assetId):
          imageIds.add(assetId);
        case TextElementContent(:final style) ||
            StickyNoteElementContent(:final style):
          fontIds.add(style.fontId);
        default:
          break;
      }
      if (rootIds.contains(element.id)) {
        var opacity = element.opacity;
        var locked = element.locked;
        var parent = document.byId[element.parentId];
        while (parent != null) {
          opacity *= parent.opacity;
          locked = locked || parent.locked;
          parent = document.byId[parent.parentId];
        }
        elements.add(
          DocumentElement(
            id: element.id,
            transform: geometry.worldTransformOf(element.id),
            revision: element.revision,
            locked: locked,
            opacity: opacity,
            content: content,
          ),
        );
      } else {
        elements.add(element);
      }
    }
    final fonts = [
      for (final font
          in document.fontReferences ?? const <DocumentFontReference>[])
        if (fontIds.contains(font.id)) font,
    ];
    if (fonts.length != fontIds.length) {
      throw StateError('Copied text has an unresolved font reference.');
    }
    final assetIds = {
      ...imageIds,
      for (final font in fonts)
        if (font.assetId != null) font.assetId!,
    };
    final assets = [
      for (final asset in document.assets ?? const <DocumentAssetReference>[])
        if (assetIds.contains(asset.id)) asset,
    ];
    if (assets.length != assetIds.length) {
      throw StateError('Copied elements have an unresolved original asset.');
    }
    var declaredBytes = 0;
    for (final asset in assets) {
      final length = asset.byteLength;
      if (length == null || length > maximumPortableAssetBytes) {
        throw StateError(
          'Clipboard originals require declared sizes up to 16 MiB each.',
        );
      }
      declaredBytes += length;
    }
    if (declaredBytes > maximumPortableOriginalBytes) {
      throw StateError('Clipboard originals exceed the 32 MiB limit.');
    }
    final fragment = BoardDocument(
      id: 'clipboard',
      revision: document.revision,
      elements: elements,
      assets: assets,
      fontReferences: fonts,
    );
    DocumentGeometry(fragment);
    DocumentCodec.encode(fragment);
    if (assets.isNotEmpty && store == null) {
      throw StateError('Original image storage is unavailable.');
    }
    final originals = <String, Uint8List>{};
    for (final asset in assets) {
      final bytes = await store!.readAsset(asset.id);
      _checkCopy(generation);
      if (bytes == null || bytes.isEmpty || bytes.length != asset.byteLength) {
        throw StateError(
          'Original asset ${asset.id} is missing or has an invalid size.',
        );
      }
      originals[asset.id] = Uint8List.fromList(bytes).asUnmodifiableView();
    }
    _checkCopy(generation);
    _content = _ClipboardContent(fragment, Map.unmodifiable(originals));
    notifyListeners();
  }

  Future<BoardDocument> preparePaste(
    BoardStore? store, {
    bool Function()? isCancelled,
  }) async {
    final content = _content;
    if (_disposed || content == null) {
      throw StateError('Copy elements before pasting.');
    }
    void check() {
      if (_disposed ||
          !identical(content, _content) ||
          (isCancelled?.call() ?? false)) {
        throw StateError('Paste was cancelled.');
      }
    }

    check();
    if (store != null && !store.writable) {
      throw StateError('This board is read-only.');
    }
    if (content.originals.isNotEmpty && store == null) {
      throw StateError('Original image storage is unavailable.');
    }
    final prefix =
        'clip-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${math.Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
    final remap = <String, String>{};
    for (final id in content.originals.keys) {
      remap[id] = '$prefix-${remap.length}';
    }
    final source = content.document;
    final fontRemap = <String, String>{};
    for (final font in source.fontReferences!) {
      fontRemap[font.id] = font.assetId == null
          ? font.id
          : '$prefix-font-${fontRemap.length}';
    }
    ElementTextStyle remapStyle(ElementTextStyle style) => ElementTextStyle(
      fontId: fontRemap[style.fontId]!,
      fontSize: style.fontSize,
      color: style.color,
    );
    ElementContent remapContent(ElementContent original) => switch (original) {
      ImageElementContent(:final assetId, :final bounds) => ImageElementContent(
        assetId: remap[assetId]!,
        bounds: bounds,
      ),
      TextElementContent() => TextElementContent(
        text: original.text,
        bounds: original.bounds,
        style: remapStyle(original.style),
        direction: original.direction,
        alignment: original.alignment,
        sizing: original.sizing,
      ),
      StickyNoteElementContent() => StickyNoteElementContent(
        text: original.text,
        bounds: original.bounds,
        style: remapStyle(original.style),
        backgroundColor: original.backgroundColor,
        direction: original.direction,
        alignment: original.alignment,
        sizing: original.sizing,
      ),
      _ => original,
    };
    final result = BoardDocument(
      id: 'clipboard',
      revision: source.revision,
      elements: [
        for (final element in source.elements)
          element.copyWith(content: remapContent(element.content)),
      ],
      assets: [
        for (final asset in source.assets!)
          DocumentAssetReference(
            id: remap[asset.id]!,
            mimeType: asset.mimeType,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            byteLength: asset.byteLength,
            sha256: asset.sha256,
          ),
      ],
      fontReferences: [
        for (final font in source.fontReferences!)
          DocumentFontReference(
            id: fontRemap[font.id]!,
            family: font.family,
            assetId: font.assetId == null ? null : remap[font.assetId],
          ),
      ],
    );
    DocumentCodec.encode(result);
    // Complete collision checks before staging any bytes. Fresh IDs never
    // replace existing originals, even if the destination is the source store.
    for (final id in remap.values) {
      if (await store!.readAsset(id) != null) {
        throw StateError(
          'Clipboard asset identity already exists. Retry paste.',
        );
      }
      check();
    }
    for (final entry in remap.entries) {
      check();
      await store!.writeAsset(
        entry.value,
        Uint8List.fromList(content.originals[entry.key]!),
      );
      check();
    }
    check();
    return result;
  }

  void _checkCopy(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Clipboard copy was superseded.');
    }
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    _content = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _content = null;
    super.dispose();
  }
}

final class _ClipboardContent {
  const _ClipboardContent(this.document, this.originals);
  final BoardDocument document;
  final Map<String, Uint8List> originals;
}
