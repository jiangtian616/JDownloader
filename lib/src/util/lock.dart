import 'dart:async';

import 'package:j_downloader/src/file/file_manager.dart';

class Lock {
  late StreamController<({AsyncValueCallback func, Completer completer})> _sc;
  late StreamSubscription<({AsyncValueCallback func, Completer completer})> _ss;

  Future? _currentOperation;

  Lock() {
    _sc = StreamController<({AsyncValueCallback func, Completer completer})>();

    _ss = _sc.stream.listen((item) async {
      _ss.pause();
      try {
        _currentOperation = item.func.call();
        item.completer.complete(await _currentOperation);
        _currentOperation = null;
      } finally {
        _ss.resume();
      }
    });
  }

  Future<T> lock<T>(AsyncValueCallback<T> operation) async {
    if (_sc.isClosed) {
      throw StateError('Lock is disposed');
    }

    Completer<T> completer = Completer<T>();
    _sc.add((func: operation, completer: completer));
    return completer.future;
  }

  Future<void> dispose() async {
    await _ss.cancel();
    await _sc.close();
    await _currentOperation;
  }
}
