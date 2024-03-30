import 'dart:isolate';

import 'package:j_downloader/src/isolate/sub_ioslate_manager.dart';
import 'package:j_downloader/src/model/main_isolate_message.dart';
import 'package:j_downloader/src/model/sub_isolate_message.dart';
import 'package:j_downloader/src/function/function.dart';

class MainIsolateManager {
  Isolate? _isolate;
  ReceivePort? _mainReceivePort;
  SendPort? _subSendPort;

  bool _ready = false;
  bool _free = false;

  VoidCallback? _onReady;
  ValueCallback? _onProgress;
  VoidCallback? _onDone;
  ValueCallback<String?>? onError;

  bool get free => _free;

  Future<void> initIsolate() async {
    if (_ready) {
      return;
    }

    _mainReceivePort = ReceivePort();
    _mainReceivePort!.listen((message) {
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
        case SubIsolateMessageType.cancel:
          message = message as SubIsolateMessage<Null>;
          break;
        case SubIsolateMessageType.error:
          message = message as SubIsolateMessage<String?>;
          _free = true;
          onError?.call(message.data);
          break;
        case SubIsolateMessageType.done:
          _free = true;
          _onDone?.call();
        default:
          break;
      }
    });

    try {
      _isolate = await Isolate.spawn(subIsolateEntryPoint, _mainReceivePort!.sendPort);
    } catch (e) {
      _mainReceivePort!.close();
      rethrow;
    }
  }

  void beginDownload(String url, String downloadPath, ({int start, int end}) downloadRange, int fileWriteOffset) {
    assert(_isolate != null && _mainReceivePort != null && _subSendPort != null && _ready);

    if (!_free) {
      print('isolate is not free');
      return;
    }
    _free = false;

    _sendDownloadMessage(url, downloadPath, downloadRange, fileWriteOffset);
  }

  void pauseIsolate() {
    if (_isolate == null || _mainReceivePort == null || !_ready) {
      return;
    }

    _sendPauseMessage();
    _free = true;
  }

  void killIsolate() {
    if (_isolate == null || _mainReceivePort == null || !_ready) {
      return;
    }

    _sendPauseMessage();
    _mainReceivePort!.close();
    _isolate!.kill();
    _isolate = null;
    _subSendPort = null;
    _ready = false;
    _free = false;
  }

  void _sendDownloadMessage(String url, String downloadPath, ({int start, int end}) downloadRange, int fileWriteOffset) {
    _subSendPort!.send(
      MainIsolateMessage(
        MainIsolateMessageType.download,
        (url: url, downloadPath: downloadPath, downloadRange: downloadRange, fileWriteOffset: fileWriteOffset),
      ),
    );
  }

  void _sendPauseMessage() {
    assert(_isolate != null && _subSendPort != null && _ready);

    _subSendPort!.send(MainIsolateMessage(MainIsolateMessageType.pause, null));
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

  void registerOnError(ValueCallback<String?> onError) {
    this.onError = onError;
  }

  void unRegisterOnError() {
    onError = null;
  }
}
