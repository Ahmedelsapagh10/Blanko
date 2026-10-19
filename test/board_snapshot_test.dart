import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

void main() {
  BoardSnapshot snapshot() => BoardSnapshot(
    document: BoardDocument(
      id: 'snapshot',
      revision: 0,
      elements: [],
      assets: [],
      fontReferences: [],
    ),
    camera: Camera(translation: Point2(-1234.5, 5678), zoom: .25),
    version: 4,
    savedAt: DateTime.utc(2026, 10, 19),
  );
  test(
    'local record preserves viewport, storage generation and document separately',
    () {
      final before = snapshot(),
          after = BoardSnapshot.decode(snapshot().encode());
      expect(after.encode(), before.encode());
      expect(after.document.revision, 0);
      expect(after.version, 4);
      expect(after.camera.translation, before.camera.translation);
    },
  );
  test('corrupt and future local envelopes cannot become editable boards', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (m) => m['version'] = 2,
      (m) => m['generation'] = 0,
      (m) => m['camera'] = [1e300, 0, .02],
      (m) => m['camera'] = [0, 0, 100],
      (m) => m['savedAt'] = 'invalid',
      (m) => m['unknown'] = true,
    ]) {
      final map = jsonDecode(snapshot().encode()) as Map<String, dynamic>;
      change(map);
      expect(
        () => BoardSnapshot.decode(jsonEncode(map)),
        throwsFormatException,
      );
    }
  });
}
