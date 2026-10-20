import 'dart:convert';

import '../document/document.dart';
import '../document/document_codec.dart';
import '../geometry/geometry.dart';
import '../viewport/camera.dart';

/// A committed document plus local viewport, separate from session undo history.
final class BoardSnapshot {
  BoardSnapshot({
    required this.document,
    required this.camera,
    required this.version,
    required this.savedAt,
  }) {
    if (version < 1 || version > 9007199254740991) {
      throw ArgumentError.value(version, 'version');
    }
    final limit = 1e9 * camera.zoom;
    if (camera.translation.x.abs() > limit ||
        camera.translation.y.abs() > limit) {
      throw ArgumentError('The saved viewport is outside the supported world.');
    }
  }
  final BoardDocument document;
  final Camera camera;
  final int version;
  final DateTime savedAt;

  String encode() => jsonEncode({
    'format': 'whiteboard.local',
    'version': 1,
    'generation': version,
    'document': DocumentCodec.encode(document),
    'camera': [camera.translation.x, camera.translation.y, camera.zoom],
    'savedAt': savedAt.toUtc().toIso8601String(),
  });

  static BoardSnapshot decode(String source) {
    if (source.length > 140 * 1024 * 1024) {
      throw const FormatException('Local board exceeds the supported size.');
    }
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      if (map.length != 6 ||
          map['format'] != 'whiteboard.local' ||
          map['version'] != 1) {
        throw const FormatException('Unsupported local board format.');
      }
      final values = map['camera'] as List<dynamic>;
      if (values.length != 3) throw const FormatException('Invalid viewport.');
      return BoardSnapshot(
        document: DocumentCodec.decode(map['document'] as String),
        camera: Camera(
          translation: Point2(
            (values[0] as num).toDouble(),
            (values[1] as num).toDouble(),
          ),
          zoom: (values[2] as num).toDouble(),
        ),
        version: map['generation'] as int,
        savedAt: DateTime.parse(map['savedAt'] as String).toUtc(),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid local board data.');
    }
  }
}

final class StorageConflict implements Exception {
  const StorageConflict([
    this.message =
        'This board changed in another session. Reopen it before editing.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Implementations acknowledge only committed durable writes. No memory fallback.
abstract interface class BoardStore {
  Future<void> initialize();
  bool get writable;
  String get location;
  Future<List<BoardSnapshot>> listBoards();
  Future<BoardSnapshot?> readBoard(String id);

  /// Null expectedVersion creates a board; otherwise compare-and-swap exactly.
  Future<void> writeBoard(
    BoardSnapshot snapshot, {
    required int? expectedVersion,
  });
  Future<void> deleteBoard(String id);
  Future<String?> readLastBoard();
  Future<void> writeLastBoard(String id);
  Future<void> close();
}
