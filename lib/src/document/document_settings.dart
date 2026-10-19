/// Canvas appearance in document values, independent of UI rendering objects.
final class CanvasSettings {
  CanvasSettings({this.backgroundColor = 0xffffffff, GridSettings? grid})
    : grid = grid ?? GridSettings() {
    _requireColor(backgroundColor, 'backgroundColor');
  }

  final int backgroundColor;
  final GridSettings grid;
}

final class GridSettings {
  GridSettings({
    this.visible = false,
    this.spacing = 20,
    this.color = 0xffe0e0e0,
  }) {
    if (!spacing.isFinite || spacing <= 0) {
      throw ArgumentError.value(spacing, 'spacing');
    }
    _requireColor(color, 'color');
  }

  final bool visible;

  /// Distance in world units; screen density is a renderer concern.
  final double spacing;
  final int color;
}

/// Describes an original asset without assuming a filesystem or storage backend.
final class DocumentAssetReference {
  DocumentAssetReference({
    required this.id,
    required this.mimeType,
    this.pixelWidth,
    this.pixelHeight,
    this.byteLength,
    String? sha256,
  }) : sha256 = sha256?.toLowerCase() {
    _requireIdentifier(id, 'id');
    if (RegExp(
          r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$',
        ).stringMatch(mimeType) !=
        mimeType) {
      throw ArgumentError.value(mimeType, 'mimeType');
    }
    if ((pixelWidth == null) != (pixelHeight == null)) {
      throw ArgumentError('Asset dimensions must be provided together.');
    }
    if (mimeType.toLowerCase().startsWith('image/') && pixelWidth == null) {
      throw ArgumentError(
        'Image references require original pixel dimensions.',
      );
    }
    for (final dimension in [pixelWidth, pixelHeight]) {
      if (dimension != null &&
          (dimension <= 0 || dimension > _maximumSafeInt)) {
        throw ArgumentError.value(dimension, 'pixelDimensions');
      }
    }
    if (byteLength != null &&
        (byteLength! <= 0 || byteLength! > _maximumSafeInt)) {
      throw ArgumentError.value(byteLength, 'byteLength');
    }
    if (this.sha256 != null &&
        (this.sha256!.length != 64 ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(this.sha256!))) {
      throw ArgumentError.value(sha256, 'sha256');
    }
  }

  final String id;
  final String mimeType;
  final int? pixelWidth;
  final int? pixelHeight;
  final int? byteLength;

  /// A declared digest; verification against bytes belongs to asset import.
  final String? sha256;
}

/// A logical font reference; this does not assert availability or a license.
final class DocumentFontReference {
  DocumentFontReference({
    required this.id,
    required this.family,
    this.assetId,
  }) {
    _requireIdentifier(id, 'id');
    _requireIdentifier(family, 'family');
    if (assetId != null) _requireIdentifier(assetId!, 'assetId');
  }

  final String id;
  final String family;

  /// Optional original font asset, when embedding is permitted separately.
  final String? assetId;
}

/// Caller-provided metadata; constructing a snapshot never reads the clock.
final class DocumentMetadata {
  DocumentMetadata({
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.createdWithVersion,
    this.modifiedWithVersion,
    this.minimumReaderVersion = 1,
  }) : createdAt = createdAt.toUtc(),
       modifiedAt = modifiedAt.toUtc() {
    if (this.modifiedAt.isBefore(this.createdAt)) {
      throw ArgumentError('Modification time precedes creation time.');
    }
    if (minimumReaderVersion < 1 || minimumReaderVersion > _maximumSafeInt) {
      throw ArgumentError.value(minimumReaderVersion, 'minimumReaderVersion');
    }
    if (createdWithVersion != null) {
      _requireIdentifier(createdWithVersion!, 'createdWithVersion');
    }
    if (modifiedWithVersion != null) {
      _requireIdentifier(modifiedWithVersion!, 'modifiedWithVersion');
    }
  }

  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? createdWithVersion;
  final String? modifiedWithVersion;

  /// Minimum document-format reader version, rather than an app version.
  final int minimumReaderVersion;
}

const _maximumSafeInt = 9007199254740991;

void _requireIdentifier(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name);
}

void _requireColor(int value, String name) {
  if (value < 0 || value > 0xffffffff) throw ArgumentError.value(value, name);
}
