import 'package:flutter/material.dart';

import 'src/editor/workspace_page.dart';
import 'src/persistence/board_store.dart';
import 'src/theme/blanko_brand.dart';

void main() => runApp(const WhiteboardApp());

class WhiteboardApp extends StatelessWidget {
  const WhiteboardApp({super.key, this.store});
  final BoardStore? store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: BlankoBrand.appName,
    debugShowCheckedModeBanner: false,
    theme: BlankoTheme.light,
    darkTheme: BlankoTheme.dark,
    home: WorkspacePage(store: store),
  );
}
