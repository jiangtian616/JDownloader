import 'dart:async';
import 'dart:io';

typedef AsyncValueCallback<T> = Future<T> Function();

class FileManager {
  final String path;

  bool _readReady = false;
  File? _file;
  RandomAccessFile? _readRaf;
  StreamController<({AsyncValueCallback func, Completer completer})>? _readSC;
  StreamSubscription<({AsyncValueCallback func, Completer completer})>? _readSS;
  Future? _currentReadOperation;

  bool _writeReady = false;
  RandomAccessFile? _writeRaf;
  StreamController<({AsyncValueCallback func, Completer completer})>? _writeSC;
  StreamSubscription<({AsyncValueCallback func, Completer completer})>? _writeSS;
  Future? _currentWriteOperation;

  FileManager(this.path);

  Future<void> truncate(int length) async {
    await _writeOperation(() => _writeRaf!.truncate(length));
  }

  Future<void> writeFrom(List<int> buffer, {int? position}) async {
    await _writeOperation(() async {
      if (position != null) {
        await _writeRaf!.setPosition(position);
      }
      await _writeRaf!.writeFrom(buffer);
    });
  }

  Future<void> close() async {
    await _closeRead();
    await _closeWrite();
  }

  Future<T> _readOperation<T>(AsyncValueCallback<T> operation) async {
    await _initRead();

    if (_readSC!.isClosed) {
      throw StateError('Read stream is closed');
    }

    Completer<T> completer = Completer<T>();

    _readSC!.add((func: operation, completer: completer));

    return completer.future;
  }

  Future<T> _writeOperation<T>(AsyncValueCallback<T> operation) async {
    await _initWrite();

    if (_writeSC!.isClosed) {
      throw StateError('Write stream is closed');
    }

    Completer<T> completer = Completer<T>();

    _writeSC!.add((func: operation, completer: completer));

    return completer.future;
  }

  Future<void> _initRead() async {
    if (_readReady) {
      return;
    }

    _file ??= File(path);
    _readRaf = await File(path).open(mode: FileMode.read);

    _readSC = StreamController<({AsyncValueCallback func, Completer completer})>();
    _readSS = _readSC!.stream.listen((item) async {
      _readSS!.pause();
      try {
        _currentReadOperation = item.func.call();
        item.completer.complete(await _currentReadOperation);
        _currentReadOperation = null;
      } finally {
        _readSS!.resume();
      }
    });

    _readReady = true;
  }

  Future<void> _initWrite() async {
    if (_writeReady) {
      return;
    }

    _file ??= File(path);
    _writeRaf = await File(path).open(mode: FileMode.writeOnlyAppend);

    _writeSC = StreamController<({AsyncValueCallback func, Completer completer})>();
    _writeSS = _writeSC!.stream.listen((item) async {
      _writeSS!.pause();
      try {
        _currentWriteOperation = item.func.call();
        item.completer.complete(await _currentWriteOperation);
        _currentWriteOperation = null;
      } finally {
        _writeSS!.resume();
      }
    });

    _writeReady = true;
  }

  Future<void> _closeRead() async {
    if (!_readReady) {
      return;
    }

    await _readSS!.cancel();
    await _readSC!.close();
    await _currentReadOperation;
    await _readRaf!.flush();
    await _readRaf!.close();

    _readReady = false;
    _readRaf = null;
    _readSC = null;
    _readSS = null;
  }

  Future<void> _closeWrite() async {
    if (!_writeReady) {
      return;
    }

    await _writeSS!.cancel();
    await _writeSC!.close();
    await _currentWriteOperation;
    await _writeRaf!.flush();
    await _writeRaf!.close();

    _writeReady = false;
    _writeRaf = null;
    _writeSC = null;
    _writeSS = null;
  }
}
