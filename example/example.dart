import 'dart:async';

import 'package:j_downloader/j_downloader.dart';
import 'package:j_downloader/src/util/log_util.dart';
import 'package:logging/logging.dart';

Future<void> main() async {
  hierarchicalLoggingEnabled = true;
  Log.level = Level.FINEST;

  Completer completer = Completer();

  JDownloadTask task = JDownloadTask.newTask(
    url: 'https://rrxuxxkmbmskpyrurcgo.hath.network/archive/2873416/93495e2d7223e60aa324e0865ff10bcce9b230d0/m4mgpgwa6we/3?start=1',
    savePath: 'C:\\Users\\JTMonster\\IdeaProjects\\J_Downloader\\example\\test.zip',
    isolateCount: 4,
    onProgress: (int current, int total) {
      Log.finest('Download progress: $current/$total');
    },
    onDone: () {
      Log.info('Download done');
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (error) {
      Log.severe('Download error: $error');
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );

  try {
    await task.start();
  } on Exception catch (e) {
    Log.severe('Download error: $e');
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  await completer.future;
}
