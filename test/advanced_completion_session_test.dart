import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

void main() {
  for (final lockedOwner in [false, true]) {
    test(
      'clear all rejects ${lockedOwner ? 'owner' : 'descendant'} lock without changing history',
      () {
        final group = ElementId('group'), child = ElementId('child');
        final session = BoardSession(
          document: BoardDocument(
            id: 'locked-clear',
            revision: 0,
            elements: [
              DocumentElement(
                id: group,
                locked: lockedOwner,
                content: const GroupElementContent(),
              ),
              DocumentElement(
                id: child,
                parentId: group,
                locked: !lockedOwner,
                content: ShapeElementContent(
                  kind: ShapeKind.rectangle,
                  bounds: Bounds2(0, 0, 10, 20),
                  fillColor: 0xff2563eb,
                ),
              ),
            ],
          ),
        );
        final locked = lockedOwner ? group : child;
        expect(session.setLockedMany([locked], false), isTrue);
        expect(session.undo(), isTrue);
        final before = session.document;
        expect(session.canRedo, isTrue);
        expect(session.clearAll(), isFalse);
        expect(session.document, same(before));
        expect(session.canUndo, isFalse);
        expect(session.canRedo, isTrue);
        expect(session.redo(), isTrue);
        final unlocked = session.document;
        expect(session.clearAll(), isTrue);
        expect(session.document.elements, isEmpty);
        expect(session.document.revision, unlocked.revision + 1);
        expect(session.undo(), isTrue);
        expect(session.document.byId.keys, unlocked.byId.keys);
        expect(session.document.byId[child]!.parentId, group);
        expect(session.document.byId[locked]!.locked, isFalse);
        expect(session.redo(), isTrue);
        expect(session.document.elements, isEmpty);
      },
    );
  }
}
