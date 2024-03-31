import 'dart:async';

import 'package:j_downloader/j_downloader.dart';

Future<void> main() async {
  Completer completer = Completer();

  JDownloadTask task = JDownloadTask.newTask(
    url: 'https://jnnnmcribetlkexrhqsk.hath.network/archive/2874499/1ca3dd8d5a54f645e34df55206c0503e5fce84c5/qxg8xv1a6x0/3?start=1',
    savePath: 'C:\\Users\\JTMonster\\IdeaProjects\\J_Downloader\\example\\test.zip',
    isolateCount: 8,
    onProgress: (int current, int total) {
      print('Download progress: $current/$total');
    },
    onDone: () {
      print('Download done');
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (error) {
      print('Download error: $error');
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );

  try {
    await task.start();
  } on Exception catch (e) {
    print('Download error: $e');
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  await completer.future;
}
