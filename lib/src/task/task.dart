import 'dart:io';

import 'package:j_downloader/j_downloader.dart';
import 'package:j_downloader/src/download/download_manager.dart';
import 'package:j_downloader/src/function/function.dart';

typedef DownloadProgressCallback = void Function(int current, int total);

class JDownloadTask {
  final String url;

  final String savePath;

  TaskStatus _status;

  TaskStatus get status => _status;

  late final DownloadManager _downloadManager;

  int get currentBytes => _downloadManager.currentBytes;

  String get downloadPath => '$savePath.jdtemp';

  JDownloadTask.newTask({
    required this.url,
    required this.savePath,
    required int isolateCount,
    bool deleteWhenUrlMismatch = true,
    DownloadProgressCallback? onProgress,
    VoidCallback? onDone,
    ValueCallback<JDownloadException>? onError,
    JDownloadLogCallback? onLog,
  }) : _status = TaskStatus.none {
    assert(Uri.tryParse(url) != null, 'Invalid url');
    assert(savePath.isNotEmpty, 'Invalid save path');
    assert(isolateCount > 0, 'Invalid isolate.dart count');

    _downloadManager = DownloadManager(
      url: url,
      downloadPath: downloadPath,
      savePath: savePath,
      isolateCount: isolateCount,
    )
      ..registerOnProgress((current, total) {
        onProgress?.call(current, total);
      })
      ..registerOnDone(() {
        _status = TaskStatus.completed;
        onDone?.call();
      })
      ..registerOnError((value) {
        _status = TaskStatus.failed;
        onError?.call(value);
      })
      ..registerOnLog((log) {
        onLog?.call(log);
      });

    _downloadManager.tryRecoverFromMetadata(deleteWhenUrlMismatch);

    if (File(savePath).existsSync()) {
      _status = TaskStatus.completed;
      onDone?.call();
    }
  }

  Future<void> start() async {
    if (_status == TaskStatus.downloading || _status == TaskStatus.completed || _status == TaskStatus.disposed) {
      return;
    }

    await _downloadManager.start();
    _status = TaskStatus.downloading;
  }

  Future<void> pause() async {
    if (_status == TaskStatus.paused || _status == TaskStatus.completed || _status == TaskStatus.disposed) {
      return;
    }

    await _downloadManager.pause();
    _status = TaskStatus.paused;
  }

  Future<void> dispose() async {
    await _downloadManager.dispose();
    _status = TaskStatus.disposed;
  }

  Future<void> changeIsolateCount(int count) async {
    if (_status == TaskStatus.completed) {
      return;
    }

    await _downloadManager.changeIsolateCount(count);
  }

  @override
  String toString() {
    return 'JDownloadTask{url: $url, savePath: $savePath, _status: $_status, _downloadManager: $_downloadManager}';
  }
}

enum TaskStatus {
  none(0),
  downloading(10),
  paused(20),
  failed(30),
  completed(40),
  disposed(50),
  ;

  final int code;

  const TaskStatus(this.code);
}
