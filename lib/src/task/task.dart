import 'dart:io';

import 'package:j_downloader/src/download/download_manager.dart';
import 'package:j_downloader/src/function/function.dart';

typedef DownloadProgressCallback = void Function(int current, int total);

class JDownloadTask {
  final String url;

  final String savePath;

  final int isolateCount;

  TaskStatus _status;

  TaskStatus get status => _status;

  late final DownloadManager _downloadManager;

  int get currentBytes => _downloadManager.currentBytes;

  String get downloadPath => '$savePath.jdtemp';

  JDownloadTask.newTask({
    required this.url,
    required this.savePath,
    required this.isolateCount,
    bool deleteWhenUrlMismatch = true,
    DownloadProgressCallback? onProgress,
    VoidCallback? onDone,
    ValueCallback<String?>? onError,
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
      });

    _downloadManager.tryRecoverFromMetadata(deleteWhenUrlMismatch);
    
    _status = TaskStatus.paused;

    if (File(savePath).existsSync()) {
      _status = TaskStatus.completed;
      onDone?.call();
    }
  }

  Future<void> start() async {
    if (_status == TaskStatus.downloading || _status == TaskStatus.completed) {
      return;
    }

    await _downloadManager.start();
    _status = TaskStatus.downloading;
  }

  Future<void> pause() async {
    if (_status == TaskStatus.paused || _status == TaskStatus.completed) {
      return;
    }

    await _downloadManager.pause();
    _status = TaskStatus.paused;
  }

  @override
  String toString() {
    return 'JDownloadTask{url: $url, savePath: $savePath, isolateCount: $isolateCount}';
  }
}

enum TaskStatus {
  none(0),
  downloading(10),
  paused(20),
  failed(30),
  completed(40);

  final int code;

  const TaskStatus(this.code);
}
