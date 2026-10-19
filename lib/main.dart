import 'package:flutter/material.dart';

import 'src/editor/editor_page.dart';

void main() => runApp(const WhiteboardApp());

class WhiteboardApp extends StatelessWidget {
  const WhiteboardApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Whiteboard',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
      useMaterial3: true,
    ),
    home: const EditorPage(),
  );
}
