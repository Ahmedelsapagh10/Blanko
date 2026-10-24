import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/editor/editor_clipboard.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

final _bounds = Bounds2(0, 0, 240, 120);
final _style = ElementTextStyle(
  fontId: 'sans',
  fontSize: 24,
  color: 0xff123456,
);
RichTextData _rich(List<Object?> delta) =>
    RichTextData.fromJson({'version': 1, 'delta': delta});
RichTextData _sample() => _rich([
  {
    'insert': 'Hello ',
    'attributes': {'bold': true, 'color': '#aabbcc'},
  },
  {
    'insert': 'مرحبا 👩‍💻',
    'attributes': {'font': 'Noto Sans Arabic', 'size': 30, 'italic': true},
  },
  {
    'insert': '\n',
    'attributes': {'direction': 'rtl', 'align': 'right', 'list': 'bullet'},
  },
]);
TextElementContent _content(String text, {RichTextData? rich}) =>
    TextElementContent(
      text: text,
      bounds: _bounds,
      style: _style,
      richText: rich,
    );
BoardDocument _document(ElementContent content) => BoardDocument(
  id: 'rich-board',
  revision: 0,
  assets: [],
  elements: [DocumentElement(id: ElementId('text'), content: content)],
  fontReferences: [DocumentFontReference(id: 'sans', family: 'Roboto')],
);

void main() {
  test('canonical snapshot is deeply immutable and preserves Unicode', () {
    final rich = _sample();
    expect(rich.plainText, 'Hello مرحبا 👩‍💻');
    expect((rich.delta.first['attributes'] as Map)['color'], '#AABBCC');
    expect((rich.delta[1]['attributes'] as Map)['size'], '30');
    expect(() => rich.delta.add({'insert': '!'}), throwsUnsupportedError);
    expect(
      () => rich.delta.first['insert'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => (rich.delta.first['attributes'] as Map)['bold'] = false,
      throwsUnsupportedError,
    );
    expect(
      _rich([
        {'insert': 'a'},
        {'insert': 'b\n'},
      ]).delta,
      [
        {'insert': 'ab\n'},
      ],
    );
    expect(
      _rich([
        {'insert': '\n\n'},
      ]).plainText,
      '\n',
    );
  });

  test('rejects malformed or unsupported content without flattening', () {
    for (final delta in <List<Object?>>[
      [],
      [
        {'insert': 'missing newline'},
      ],
      [
        {
          'insert': {'image': 'embed'},
        },
      ],
      [
        {'retain': 4},
      ],
      [
        {'delete': 1},
      ],
      [
        {'insert': ''},
      ],
      [
        {
          'insert': '\n',
          'attributes': {'unknown': true},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'bold': false},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'size': 'huge'},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'size': 7},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'size': 145},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'color': 'red'},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'font': 'unknown'},
        },
      ],
      [
        {
          'insert': 'word\n',
          'attributes': {'align': 'right'},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'direction': 'auto'},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'link': 'javascript:alert(1)'},
        },
      ],
      [
        {
          'insert': '\n',
          'attributes': {'link': 'https://'},
        },
      ],
      [
        {'insert': '\n', 'attributes': null},
      ],
      [
        {'insert': '\n', 'unexpected': 2},
      ],
    ]) {
      expect(() => _rich(delta), throwsFormatException, reason: '$delta');
    }
    expect(
      () => RichTextData.fromJson({
        'version': 2,
        'delta': [
          {'insert': '\n'},
        ],
      }),
      throwsFormatException,
    );
    expect(() => RichTextData.fromJson(null), throwsFormatException);
    expect(
      () => _rich([
        {'insert': '${'a' * RichTextData.maximumTextLength}\n'},
      ]),
      throwsFormatException,
    );
    expect(() => _content('different', rich: _sample()), throwsArgumentError);
  });

  test('supports safe links and complete supported inline attributes', () {
    for (final link in [
      'https://blanko.example/path',
      'http://blanko.example',
      'mailto:hello@example.org',
    ]) {
      final rich = _rich([
        {
          'insert': 'x',
          'attributes': {
            'bold': true,
            'italic': true,
            'underline': true,
            'strike': true,
            'size': '8',
            'font': 'Roboto',
            'background': '#80AABBCC',
            'link': link,
          },
        },
        {
          'insert': '\n',
          'attributes': {
            'align': 'justify',
            'direction': 'ltr',
            'list': 'ordered',
          },
        },
      ]);
      expect(rich.plainText, 'x');
    }
  });

  test('legacy text stays legacy; mixed rich text and notes round trip', () {
    final plain = DocumentCodec.encode(_document(_content('Legacy عربي')));
    expect(plain, isNot(contains('richText')));
    expect(
      (DocumentCodec.decode(plain).elements.single.content
              as TextElementContent)
          .richText,
      isNull,
    );
    for (final content in <ElementContent>[
      _content(_sample().plainText, rich: _sample()),
      StickyNoteElementContent(
        text: _sample().plainText,
        richText: _sample(),
        bounds: _bounds,
        style: _style,
        backgroundColor: 0xffffff00,
      ),
    ]) {
      final encoded = DocumentCodec.encode(_document(content));
      final decoded = DocumentCodec.decode(encoded);
      expect(DocumentCodec.encode(decoded), encoded);
      final root = jsonDecode(encoded) as Map;
      final value =
          ((root['elements'] as List).single as Map)['content'] as Map;
      value['text'] = 'stale';
      expect(
        () => DocumentCodec.decode(jsonEncode(root)),
        throwsFormatException,
      );
    }
  });

  test('resize, undo redo and clipboard preserve rich formatting', () async {
    final rich = _sample();
    final session = BoardSession(
      document: _document(_content(rich.plainText, rich: rich)),
    );
    final id = session.document.elements.single.id;
    expect(session.resize(id, Bounds2(0, 0, 400, 200)), isTrue);
    expect(
      (session.document.byId[id]!.content as TextElementContent).richText,
      same(rich),
    );
    expect(session.undo(), isTrue);
    expect(session.redo(), isTrue);
    final clipboard = EditorClipboard();
    addTearDown(clipboard.dispose);
    await clipboard.copy(session.document, [id], null);
    final pasted = await clipboard.preparePaste(null);
    expect(
      (pasted.elements.single.content as TextElementContent).richText!.toJson(),
      rich.toJson(),
    );
  });

  test(
    'text checkpoints are revisioned with one board undo for the session',
    () {
      final session = BoardSession(document: _document(_content('original')));
      final id = session.document.elements.single.id;
      session.beginTextEdit(_content('original'), Point2.zero, id: id);
      expect(session.updateTextEdit(_content('one')), isTrue);
      final firstRevision = session.document.revision;
      expect(session.updateTextEdit(_content('two')), isTrue);
      expect(session.document.revision, greaterThan(firstRevision));
      expect(session.canUndo, isFalse);
      expect(() => session.clearAll(), throwsStateError);
      session.finishTextEdit();
      expect(session.undo(), isTrue);
      expect(
        (session.document.byId[id]!.content as TextElementContent).text,
        'original',
      );
      expect(session.canUndo, isFalse);
      expect(session.redo(), isTrue);
      expect(
        (session.document.byId[id]!.content as TextElementContent).text,
        'two',
      );
    },
  );

  test(
    'cancel restores existing text, removes new text and increments revisions',
    () {
      final session = BoardSession(document: _document(_content('original')));
      final id = session.document.elements.single.id;
      session.beginTextEdit(_content('original'), Point2.zero, id: id);
      session.updateTextEdit(_content('discard'));
      final revision = session.document.revision;
      session.finishTextEdit(cancel: true);
      expect(session.document.revision, greaterThan(revision));
      expect(
        (session.document.byId[id]!.content as TextElementContent).text,
        'original',
      );
      expect(session.canUndo, isFalse);
      final added = session.beginTextEdit(_content('new'), Point2(30, 40));
      session.finishTextEdit(cancel: true);
      expect(session.document.byId[added], isNull);
      final blank = session.beginTextEdit(_content(''), Point2.zero);
      session.finishTextEdit();
      expect(session.document.byId[blank], isNull);
      expect(session.canUndo, isFalse);
    },
  );

  test('new rich text finish and automatic finish on undo remain coherent', () {
    final session = BoardSession();
    final rich = _sample();
    final id = session.beginTextEdit(
      _content('', rich: null),
      Point2(50, 60),
      font: DocumentFontReference(id: 'sans', family: 'Roboto'),
    );
    session.updateTextEdit(_content(rich.plainText, rich: rich));
    expect(session.undo(), isTrue);
    expect(session.hasTextEdit, isFalse);
    expect(session.document.byId[id], isNull);
    expect(session.redo(), isTrue);
    final restored = session.document.byId[id]!;
    expect((restored.content as TextElementContent).richText, same(rich));
    expect(restored.transform, Transform2.translation(50, 60));
  });
}
