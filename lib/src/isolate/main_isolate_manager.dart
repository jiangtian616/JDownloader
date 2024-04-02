import 'dart:async';
import 'dart:isolate';

import 'package:j_downloader/src/exception/j_download_exception.dart';
import 'package:j_downloader/src/isolate/sub_ioslate_manager.dart';
import 'package:j_downloader/src/model/main_isolate_message.dart';
import 'package:j_downloader/src/model/sub_isolate_message.dart';
import 'package:j_downloader/src/function/function.dart';

class MainIsolateManager {
  bool _ready = false;
  Isolate? _isolate;
  ReceivePort? _mainReceivePort;
  SendPort? _subSendPort;

  bool _free = true;

  VoidCallback? _onReady;
  ValueCallback? _onProgress;
  VoidCallback? _onDone;
  ValueCallback<JDownloadException>? _onError;

  bool get free => _free;

  Completer<void>? _closeCompleter;

  Future<void> initIsolate() async {
    if (_ready) {
      return;
    }

    _mainReceivePort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(subIsolateEntryPoint, _mainReceivePort!.sendPort);
    } catch (e) {
      _mainReceivePort!.close();
      rethrow;
    }

    _isolate!.addOnExitListener(_mainReceivePort!.sendPort);

    _mainReceivePort!.listen((message) {
      message ??= SubIsolateMessage<Null>(SubIsolateMessageType.closed, null);

      print('received sub message: $message');

      switch (message.type) {
        case SubIsolateMessageType.init:
          message = message as SubIsolateMessage<SendPort>;
          _subSendPort = message.data;
          _ready = true;
          _free = true;
          _onReady?.call();
          break;
        case SubIsolateMessageType.progress:
          message = message as SubIsolateMessage<int>;
          _onProgress?.call(message.data);
          break;
        case SubIsolateMessageType.error:
          message = message as SubIsolateMessage;
          _free = true;
          _onError?.call(message.data);
          break;
        case SubIsolateMessageType.done:
          _free = true;
          _onDone?.call();
        case SubIsolateMessageType.closeReady:
        case SubIsolateMessageType.closed:
          message = message as SubIsolateMessage<Null>;
          _mainReceivePort?.close();
          _isolate?.kill();
          _isolate = null;
          _subSendPort = null;
          _ready = false;
          _free = true;
          _closeCompleter?.complete();
          _closeCompleter = null;
          break;
        default:
          break;
      }
    });
  }

  void beginDownload(String url, String downloadPath, ({int start, int end}) downloadRange, int fileWriteOffset) {
    assert(_isolate != null && _mainReceivePort != null && _subSendPort != null && _ready);

    if (!_free) {
      return;
    }
    _free = false;

    _subSendPort!.send(
      MainIsolateMessage(
        MainIsolateMessageType.download,
        (url: url, downloadPath: downloadPath, downloadRange: downloadRange, fileWriteOffset: fileWriteOffset),
      ),
    );
  }

  Future<void> killIsolate() async {
    if (_isolate == null || _mainReceivePort == null || !_ready || free) {
      return;
    }

    _closeCompleter ??= Completer();
    _subSendPort!.send(MainIsolateMessage(MainIsolateMessageType.close, null));
    return _closeCompleter!.future;
  }

  void registerOnReady(VoidCallback onReady) {
    _onReady = onReady;
  }

  void unRegisterOnReady() {
    _onReady = null;
  }

  void registerOnProgress(ValueCallback onProgress) {
    _onProgress = onProgress;
  }

  void unRegisterOnProgress() {
    _onProgress = null;
  }

  void registerOnDone(VoidCallback onDone) {
    _onDone = onDone;
  }

  void unRegisterOnDone() {
    _onDone = null;
  }

  void registerOnError(ValueCallback<JDownloadException> onError) {
    _onError = onError;
  }

  void unRegisterOnError() {
    _onError = null;
  }
}
