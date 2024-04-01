import 'dart:async';

import 'package:j_downloader/j_downloader.dart';

Future<void> main() async {
  Completer completer = Completer();

  JDownloadTask task = JDownloadTask.newTask(
    url: 'https://jnnnmcribetlkexrhqsk.hath.network/archive/2874723/641419b4e631fd98c536b8bfe4fa904c2233ff0f/8dnrequa6x4/2?start=1',
    savePath: 'C:\\Users\\JTMonster\\IdeaProjects\\J_Downloader\\example\\test.zip',
    isolateCount: 4,
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
