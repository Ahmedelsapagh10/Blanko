import 'document_settings.dart';
import 'element.dart';

/// Pure document state, independent of renderer resources and session history.
final class BoardDocument {
  factory BoardDocument({
    required String id,
    required int revision,
    required Iterable<DocumentElement> elements,
    int schemaVersion = currentVersion,
    String? workspaceId,
    String title = '',
    CanvasSettings? canvasSettings,
    Iterable<DocumentAssetReference>? assets,
    Iterable<DocumentFontReference>? fontReferences,
    DocumentMetadata? metadata,
  }) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (workspaceId != null && workspaceId.trim().isEmpty) {
      throw ArgumentError.value(workspaceId, 'workspaceId');
    }
    if (revision < 0 || revision > maximumDocumentRevision) {
      throw ArgumentError.value(revision, 'revision');
    }
    if (schemaVersion != currentVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported version.',
      );
    }
    if (metadata != null && metadata.minimumReaderVersion > schemaVersion) {
      throw ArgumentError('Metadata requires a newer document-format reader.');
    }

    final assetSnapshot = assets == null
        ? null
        : List<DocumentAssetReference>.unmodifiable(assets);
    final fontSnapshot = fontReferences == null
        ? null
        : List<DocumentFontReference>.unmodifiable(fontReferences);
    final assetsById = <String, DocumentAssetReference>{};
    for (final asset in assetSnapshot ?? const <DocumentAssetReference>[]) {
      if (assetsById.containsKey(asset.id)) {
        throw ArgumentError('Duplicate asset ID: ${asset.id}');
      }
      assetsById[asset.id] = asset;
    }
    final fontsById = <String, DocumentFontReference>{};
    for (final font in fontSnapshot ?? const <DocumentFontReference>[]) {
      if (fontsById.containsKey(font.id)) {
        throw ArgumentError('Duplicate font ID: ${font.id}');
      }
      if (font.assetId != null &&
          assetSnapshot != null &&
          !assetsById.containsKey(font.assetId)) {
        throw ArgumentError('Missing original asset for font ${font.id}.');
      }
      fontsById[font.id] = font;
    }

    final snapshot = List<DocumentElement>.unmodifiable(elements);
    final byId = <ElementId, DocumentElement>{};
    final children = <ElementId?, List<DocumentElement>>{};
    for (final element in snapshot) {
      final content = element.content;
      if (content is ImageElementContent && assetSnapshot != null) {
        final asset = assetsById[content.assetId];
        if (asset == null ||
            !asset.mimeType.toLowerCase().startsWith('image/')) {
          throw ArgumentError('Missing image asset for ${element.id}.');
        }
      }
      final fontId = switch (content) {
        TextElementContent(:final style) => style.fontId,
        StickyNoteElementContent(:final style) => style.fontId,
        _ => null,
      };
      if (fontId != null &&
          fontSnapshot != null &&
          !fontsById.containsKey(fontId)) {
        throw ArgumentError('Missing font reference for ${element.id}.');
      }
      if (element.revision > revision) {
        throw ArgumentError('Element ${element.id} exceeds document revision.');
      }
      if (byId.containsKey(element.id)) {
        throw ArgumentError('Duplicate element ID: ${element.id}');
      }
      byId[element.id] = element;
      children.putIfAbsent(element.parentId, () => []).add(element);
    }
    for (final element in snapshot) {
      final parentId = element.parentId;
      if (parentId != null &&
          !(byId[parentId]?.content.canOwnChildren ?? false)) {
        throw ArgumentError('Missing or non-owning parent for ${element.id}.');
      }
    }

    final stack = <DocumentElement>[
      ...(children[null] ?? const <DocumentElement>[]).reversed,
    ];
    final preorder = <DocumentElement>[];
    while (stack.isNotEmpty) {
      final element = stack.removeLast();
      preorder.add(element);
      stack.addAll(
        (children[element.id] ?? const <DocumentElement>[]).reversed,
      );
    }
    if (preorder.length != snapshot.length) {
      throw ArgumentError('Document ownership contains a cycle.');
    }

    return BoardDocument._(
      id,
      schemaVersion,
      revision,
      workspaceId,
      title,
      canvasSettings ?? CanvasSettings(),
      assetSnapshot,
      fontSnapshot,
      metadata,
      snapshot,
      Map.unmodifiable(byId),
      Map.unmodifiable({
        for (final entry in children.entries)
          entry.key: List<DocumentElement>.unmodifiable(entry.value),
      }),
      List.unmodifiable(preorder),
    );
  }

  BoardDocument._(
    this.id,
    this.schemaVersion,
    this.revision,
    this.workspaceId,
    this.title,
    this.canvasSettings,
    this.assets,
    this.fontReferences,
    this.metadata,
    this.elements,
    this.byId,
    this.children,
    this.preorder,
  );

  static const currentVersion = 1;

  final String id;
  final int schemaVersion;
  final int revision;

  /// Local identity is allocated independently when binding a portable snapshot.
  final String? workspaceId;
  final String title;
  final CanvasSettings canvasSettings;

  /// Null denotes an unresolved legacy snapshot; a supplied list is authoritative.
  /// Persistence/import integration must supply and validate complete manifests.
  final List<DocumentAssetReference>? assets;

  /// Null is unresolved; an explicit list must declare every text/note font ID.
  final List<DocumentFontReference>? fontReferences;

  /// Null preserves legacy snapshots without fabricating creation timestamps.
  final DocumentMetadata? metadata;

  /// The sole order source: relative occurrence determines sibling order.
  final List<DocumentElement> elements;
  final Map<ElementId, DocumentElement> byId;
  final Map<ElementId?, List<DocumentElement>> children;

  /// Derived depth-first order; owning subtrees remain contiguous.
  final List<DocumentElement> preorder;

  List<DocumentElement> childrenOf(ElementId? parentId) =>
      children[parentId] ?? const [];
}
