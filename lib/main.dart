import 'package:flutter/material.dart';

import 'src/editor/workspace_page.dart';
import 'src/persistence/board_store.dart';

void main() => runApp(const WhiteboardApp());

class WhiteboardApp extends StatelessWidget {
  const WhiteboardApp({super.key, this.store});
  final BoardStore? store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Whiteboard',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
      useMaterial3: true,
    ),
    home: WorkspacePage(store: store),
  );
}
