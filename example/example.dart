import 'dart:async';

import 'package:j_downloader/j_downloader.dart';
import 'package:logging/logging.dart';

Future<void> main() async {
  Completer completer = Completer();

  JDownloadTask task = JDownloadTask.newTask(
    url: 'https://rrxuxxkmbmskpyrurcgo.hath.network/archive/2873416/93495e2d7223e60aa324e0865ff10bcce9b230d0/m4mgpgwa6we/3?start=1',
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
