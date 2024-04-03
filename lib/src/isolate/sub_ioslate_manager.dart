import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:j_downloader/src/exception/j_download_exception.dart';
import 'package:j_downloader/src/model/main_isolate_message.dart';
import 'package:j_downloader/src/model/sub_isolate_message.dart';
import 'package:logger/web.dart';

class SubIsolateManager {
  final ReceivePort _subReceivePort;
  final SendPort _mainSendPort;

  CancelToken? _cancelToken;

  SubIsolateManager({
    required SendPort mainSendPort,
  })  : _mainSendPort = mainSendPort,
        _subReceivePort = ReceivePort() {
    _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.init, _subReceivePort.sendPort));

    _subReceivePort.listen((message) {
      _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.log, LogEvent(Level.debug, 'received main message: $message')));
      
      switch (message.type) {
        case MainIsolateMessageType.download:
          message = message as MainIsolateMessage<({String url, String downloadPath, ({int start, int end}) downloadRange, int fileWriteOffset})>;
          download(
            message.data.url,
            message.data.downloadPath,
            message.data.downloadRange,
            message.data.fileWriteOffset,
          );
          break;
        case MainIsolateMessageType.close:
          if (_cancelToken == null || _cancelToken!.isCancelled) {
            _mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.closeReady, null));
          } else {
            _cancelToken!.cancel();
          }
          break;
        default:
          break;
      }
    });
  }

  Future<void> download(String url, String downloadPath, ({int start, int end}) downloadRange, int fileWriteOffset) async {
    _cancelToken ??= CancelToken();
    Response<ResponseBody> response;

    _mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.begin, null));
    try {
      response = await Dio().get(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          preserveHeaderCase: true,
          headers: {'Range': '${downloadRange.start}-${downloadRange.end - 1}'},
          responseType: ResponseType.stream,
        ),
        cancelToken: _cancelToken,
      );
    } on DioException catch (e) {
      _cancelToken = null;
      
      if (e.type == DioExceptionType.cancel) {
        _mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.closeReady, null));
      } else {
        _mainSendPort.send(
          SubIsolateMessage<JDownloadException>(
            SubIsolateMessageType.error,
            JDownloadException(
              JDownloadExceptionType.downloadFailed,
              error: e.message ?? e.toString(),
              data: e.response
                ?..data = null
                ..requestOptions.cancelToken = null,
            ),
          ),
        );
      }

      return;
    }

    if (response.statusCode != HttpStatus.partialContent) {
      _cancelToken!.cancel();
      _cancelToken = null;

      return _mainSendPort.send(
        SubIsolateMessage<JDownloadException>(
          SubIsolateMessageType.error,
          JDownloadException(JDownloadExceptionType.serverNotSupport, data: response),
        ),
      );
    }

    _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.log, LogEvent(Level.debug, 'open download file')));
    
    File downloadFile = File(downloadPath);
    RandomAccessFile raf = await downloadFile.open(mode: FileMode.writeOnlyAppend);
    await raf.setPosition(fileWriteOffset);

    Future<void>? asyncWrite;
    bool closed = false;
    Future<void> close() async {
      if (!closed) {
        closed = true;
        await asyncWrite;
        await raf.close().catchError((_) => raf);
        _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.log, LogEvent(Level.debug, 'close download file')));
      }
    }

    Stream<Uint8List> stream = response.data!.stream;
    late StreamSubscription subscription;
    subscription = stream.listen(
      (data) {
        subscription.pause();
        asyncWrite = raf.writeFrom(data).then((result) {
          _mainSendPort.send(SubIsolateMessage<int>(SubIsolateMessageType.progress, data.length));
          raf = result;
          if (_cancelToken != null && !_cancelToken!.isCancelled) {
            subscription.resume();
          }
        }).catchError((e) async {
          await subscription.cancel().catchError((_) {});
          closed = true;
          await raf.close().catchError((_) => raf);
          _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.log, LogEvent(Level.debug, 'close download file')));
          _mainSendPort.send(
            SubIsolateMessage<JDownloadException>(
              SubIsolateMessageType.error,
              JDownloadException(JDownloadExceptionType.writeDownloadFileFailed, error: e),
            ),
          );
        });
      },
      onDone: () async {
        await asyncWrite;
        closed = true;
        await raf.close().catchError((_) => raf);
        _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.log, LogEvent(Level.debug, 'close download file')));
        _cancelToken = null;
        _mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.done, null));
      },
      onError: (e) async {
        await close();
        _cancelToken = null;
        _mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.error, e.toString()));
      },
      cancelOnError: true,
    );

    _cancelToken?.whenCancel.then((_) async {
      await subscription.cancel();
      await close();
      _mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.closeReady, null));
    });
  }
}

void subIsolateEntryPoint(SendPort mainSendPort) {
  SubIsolateManager(mainSendPort: mainSendPort);
}
