import 'board_store.dart';
import 'unsupported_board_store.dart'
    if (dart.library.io) 'file_board_store.dart'
    if (dart.library.js_interop) 'web_board_store.dart'
    as platform;

Future<BoardStore> openBoardStore() => platform.createBoardStore();
