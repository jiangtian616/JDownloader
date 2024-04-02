import 'dart:async';
import 'dart:io';
import 'package:j_downloader/src/util/lock.dart';

typedef AsyncValueCallback<T> = Future<T> Function();

class FileManager {
  final String path;
  File? _file;

  bool _readReady = false;
  RandomAccessFile? _readRaf;
  Lock? _readLock;

  bool _writeReady = false;
  RandomAccessFile? _writeRaf;
  Lock? _writeLock;

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
    print('close FileManager');
  }

  Future<T> _readOperation<T>(AsyncValueCallback<T> operation) async {
    await _initRead();
    return _readLock!.lock(operation);
  }

  Future<T> _writeOperation<T>(AsyncValueCallback<T> operation) async {
    await _initWrite();
    print('write start');
    T result = await _writeLock!.lock(operation);
    print('write end');
    return result;
  }

  Future<void> _initRead() async {
    if (_readReady) {
      return;
    }

    _file ??= File(path);
    _readRaf = await File(path).open(mode: FileMode.read);
    _readLock = Lock();
    _readReady = true;
  }

  Future<void> _initWrite() async {
    if (_writeReady) {
      return;
    }

    _file ??= File(path);
    _writeRaf = await File(path).open(mode: FileMode.writeOnlyAppend);
    _writeLock = Lock();
    _writeReady = true;
  }

  Future<void> _closeRead() async {
    if (!_readReady) {
      return;
    }

    await _readLock!.dispose();
    await _readRaf!.flush();
    await _readRaf!.close();

    _readLock = null;
    _readReady = false;
    _readRaf = null;
  }

  Future<void> _closeWrite() async {
    if (!_writeReady) {
      return;
    }

    await _writeLock!.dispose();
    await _writeRaf!.flush();
    await _writeRaf!.close();

    _writeLock = null;
    _writeReady = false;
    _writeRaf = null;
  }
}
