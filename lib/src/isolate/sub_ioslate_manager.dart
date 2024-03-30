import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:j_downloader/src/model/main_isolate_message.dart';
import 'package:j_downloader/src/model/sub_isolate_message.dart';

class SubIsolateManager {
  final SendPort mainSendPort;

  CancelToken? _cancelToken;

  SubIsolateManager({
    required this.mainSendPort,
  }) {
    ReceivePort subReceivePort = ReceivePort();

    subReceivePort.listen((message) {
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
        case MainIsolateMessageType.pause:
          _cancelToken?.cancel();
          break;
        default:
          break;
      }
    });

    mainSendPort.send(SubIsolateMessage(SubIsolateMessageType.init, subReceivePort.sendPort));
  }

  Future<void> download(String url, String downloadPath, ({int start, int end}) downloadRange, int fileWriteOffset) async {
    mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.begin, null));

    _cancelToken = CancelToken();
    Response<ResponseBody> response;

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
      mainSendPort.send(SubIsolateMessage<String?>(SubIsolateMessageType.error, e.message ?? e.error?.toString()));
      return;
    }

    if (response.statusCode != HttpStatus.partialContent) {
      mainSendPort.send(SubIsolateMessage<String?>(SubIsolateMessageType.error, 'Server does not support range requests'));
      return;
    }

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
      }
    }

    Stream<Uint8List> stream = response.data!.stream;
    late StreamSubscription subscription;
    subscription = stream.listen(
      (data) {
        subscription.pause();
        asyncWrite = raf.writeFrom(data).then((result) {
          mainSendPort.send(SubIsolateMessage<int>(SubIsolateMessageType.progress, data.length));
          raf = result;
          if (!_cancelToken!.isCancelled) {
            subscription.resume();
          }
        }).catchError((e) async {
          await subscription.cancel().catchError((_) {});
          closed = true;
          await raf.close().catchError((_) => raf);
          mainSendPort.send(SubIsolateMessage<String?>(SubIsolateMessageType.error, e.toString()));
        });
      },
      onDone: () async {
        await asyncWrite;
        closed = true;
        await raf.close().catchError((_) => raf);
        mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.done, null));
      },
      onError: (e) async {
        await close();
        mainSendPort.send(SubIsolateMessage<String?>(SubIsolateMessageType.error, e.toString()));
      },
      cancelOnError: true,
    );

    _cancelToken?.whenCancel.then((_) async {
      await subscription.cancel();
      await close();
      mainSendPort.send(SubIsolateMessage<Null>(SubIsolateMessageType.cancel, null));
    });
  }
}

void subIsolateEntryPoint(SendPort mainSendPort) {
  SubIsolateManager(mainSendPort: mainSendPort);
}
