import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:j_downloader/j_downloader.dart';
import 'package:j_downloader/src/exception/j_download_exception.dart';
import 'package:j_downloader/src/function/function.dart';
import 'package:j_downloader/src/isolate/main_isolate_manager.dart';
import 'package:j_downloader/src/model/download_chunk.dart';
import 'package:j_downloader/src/model/download_progress.dart';
import 'package:retry/retry.dart';

class DownloadManager {
  final String url;
  final String downloadPath;
  final String savePath;
  final int isolateCount;

  final Dio _dio = Dio();

  late final int totalBytes;

  bool _refReady = false;
  late RandomAccessFile _raf;

  bool _storeStreamReady = false;
  late final StreamController<DownloadProgress> _storeProgressSC;
  late final StreamSubscription<DownloadProgress> _storeProgressSS;

  bool _chunksReady = false;
  List<DownloadTrunk> _chunks = [];
  List<bool> _chunksBusy = [];

  int get currentBytes => _chunks.fold(0, (previousValue, element) => previousValue + element.downloadedBytes);

  bool _isolatesReady = false;
  List<MainIsolateManager> _isolates = [];

  DownloadProgressCallback? _onProgress;
  VoidCallback? _onDone;
  ValueCallback<String?>? _onError;

  static const int _preservedMetadataHeaderSize = 1024 * 16;

  static const String _copySuffix = '.jdcopy';

  DownloadManager({
    required this.url,
    required this.downloadPath,
    required this.savePath,
    required this.isolateCount,
  });

  void tryRecoverFromMetadata() {
    File downloadFile = File(downloadPath);
    if (!downloadFile.existsSync()) {
      return;
    }

    RandomAccessFile? raf;
    DownloadProgress progress;
    try {
      raf = downloadFile.openSync(mode: FileMode.read);
      Uint8List metadataHeader = raf.readSync(_preservedMetadataHeaderSize);
      progress = DownloadProgress.fromBuffer(metadataHeader);

      raf.closeSync();
    } on Exception catch (e) {
      print('Failed to read metadata from download file, will start from scratch.');
      raf?.closeSync();
      downloadFile.deleteSync();
      return;
    }

    if (progress.url != url) {
      print('Download url mismatch, expected: $url, actual: ${progress.url}, will start from scratch.');
      downloadFile.deleteSync();
      return;
    }

    try {
      _raf = downloadFile.openSync(mode: FileMode.writeOnlyAppend);
    } on Exception catch (e) {
      print('Failed to open download file for write, will start from scratch.');
      downloadFile.deleteSync();
      return;
    }

    _refReady = true;
    totalBytes = progress.totalBytes;
    _chunks = progress.chunks;
    _chunksBusy = List.generate(_chunks.length, (_) => false);
    _chunksReady = true;
  }

  Future<void> start() async {
    await _initStoreProgressStream();

    await _initTrunks();

    await _preCreateDownloadFile();

    await _startIsolates();

    await _tryHandleTrunks();
  }

  Future<void> pause() async {
    _killIsolates();
  }

  void registerOnProgress(DownloadProgressCallback callback) {
    _onProgress = callback;
  }

  void unRegisterOnProgress() {
    _onProgress = null;
  }

  void registerOnDone(VoidCallback callback) {
    _onDone = callback;
  }

  void unRegisterOnDone() {
    _onDone = null;
  }

  void registerOnError(ValueCallback<String?> callback) {
    _onError = callback;
  }

  void unRegisterOnError() {
    _onError = null;
  }

  Future<void> _initStoreProgressStream() async {
    if (_storeStreamReady) {
      return;
    }

    _storeProgressSC = StreamController<DownloadProgress>();
    _storeProgressSS = _storeProgressSC.stream.listen((progress) async {
      _storeProgressSS.pause();

      await _storeDownloadProgress(progress);

      _storeProgressSS.resume();
    });

    _storeStreamReady = true;
  }

  Future<void> _initTrunks() async {
    if (_chunksReady) {
      return;
    }

    Response response;

    try {
      response = await retry(
        () => _dio.head(
          url,
          options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
        ),
        maxAttempts: 3,
        retryIf: (e) => e is DioException,
      );
    } on DioException catch (e) {
      print('Failed to get content-length from url response.');
      throw JDownloadException(JDownloadExceptionType.fetchContentLengthFailed, error: e);
    }

    int? contentLength = int.tryParse(response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
    if (contentLength == null) {
      throw JDownloadException(JDownloadExceptionType.noContentLengthHeaderFound);
    }

    totalBytes = contentLength;

    _chunks = List.generate(
      isolateCount,
      (index) => DownloadTrunk(
        size: index != isolateCount - 1 ? contentLength ~/ isolateCount : contentLength - (isolateCount - 1) * (contentLength ~/ isolateCount),
      ),
    );
    _chunksBusy = List.generate(_chunks.length, (_) => false);

    _chunksReady = true;
  }

  Future<void> _startIsolates() async {
    if (_isolatesReady) {
      return;
    }

    _isolates.clear();

    try {
      List<Completer<void>> readyCompleters = List.generate(isolateCount, (_) => Completer<void>());
      for (int i = 0; i < isolateCount; i++) {
        MainIsolateManager isolateManager = MainIsolateManager()
          ..registerOnReady(readyCompleters[i].complete)
          ..initIsolate();
        _isolates.add(isolateManager);
      }

      await Future.wait(readyCompleters.map((e) => e.future));
    } on Exception catch (e) {
      print('startIsolates error, shutdown all isolates');
      _killIsolates();
      _isolates.clear();
      throw JDownloadException(JDownloadExceptionType.startIsolateFailed, error: e);
    }

    for (MainIsolateManager isolate in _isolates) {
      isolate.unRegisterOnReady();
    }

    _isolatesReady = true;
  }

  Future<void> _tryHandleTrunks() async {
    if (_chunks.every((chunk) => chunk.completed)) {
      _completeDownloadFile();
      return;
    }

    if (_isolates.length > _chunks.length) {
      // todo: re-chunk
    }

    for (int i = 0; i < _chunks.length; i++) {
      if (_chunks[i].completed) {
        continue;
      }
      if (_chunksBusy[i]) {
        continue;
      }

      for (MainIsolateManager isolate in _isolates) {
        if (!isolate.free) {
          continue;
        }

        isolate
          ..registerOnProgress((value) {
            _handleChunkDownloadProgress(isolate, i, value);
          })
          ..registerOnDone(() {
            _handleChunkDownloadComplete(isolate, i);
          })
          ..registerOnError((String? error) {
            _handleChunkDownloadError(isolate, i, error);
          });

        _chunksBusy[i] = true;

        isolate.beginDownload(
          url,
          downloadPath,
          _computeChunkDownloadRange(_chunks, i),
          _computeFileWriteOffset(_chunks, i),
        );
        break;
      }
    }
  }

  void _killIsolates() {
    for (MainIsolateManager isolate in _isolates) {
      isolate.killIsolate();
      isolate.unRegisterOnProgress();
      isolate.unRegisterOnDone();
      isolate.unRegisterOnError();
    }

    _chunksBusy = List.generate(_chunks.length, (_) => false);
    _isolatesReady = false;
  }

  Future<void> _preCreateDownloadFile() async {
    if (_refReady) {
      return;
    }

    try {
      File downloadFile = File(downloadPath);
      if (!await downloadFile.exists()) {
        await downloadFile.create(recursive: true);
      }

      _raf = await downloadFile.open(mode: FileMode.writeOnlyAppend);

      DownloadProgress progress = DownloadProgress(
        url: url,
        savePath: savePath,
        totalBytes: totalBytes,
        chunks: _chunks,
      );
      await _storeDownloadProgress(progress);

      _raf = await _raf.truncate(_preservedMetadataHeaderSize + totalBytes);

      _refReady = true;
    } on Exception catch (e) {
      print('Failed to pre-create download file.');
      throw JDownloadException(JDownloadExceptionType.preCreateDownloadFileFailed, error: e);
    }
  }

  int _computeFileWriteOffset(List<DownloadTrunk> chunks, int i) {
    int offset = 0;
    for (int j = 0; j < i; j++) {
      offset += chunks[j].size;
    }

    return _preservedMetadataHeaderSize + offset + chunks[i].downloadedBytes;
  }

  ({int start, int end}) _computeChunkDownloadRange(List<DownloadTrunk> chunks, int i) {
    int start = 0;
    for (int j = 0; j < i; j++) {
      start += chunks[j].size;
    }

    int end = start + chunks[i].size;
    start = start + chunks[i].downloadedBytes;

    return (start: start, end: end);
  }

  void _handleChunkDownloadProgress(MainIsolateManager isolate, int chunkIndex, int newDownloadedBytes) {
    _chunks[chunkIndex].downloadedBytes += newDownloadedBytes;

    _onProgress?.call(currentBytes, totalBytes);

    _tryStoreDownloadProgress();
  }

  void _handleChunkDownloadComplete(MainIsolateManager isolate, int chunkIndex) {
    assert(_chunks[chunkIndex].completed);

    _chunksBusy[chunkIndex] = false;

    _tryHandleTrunks();
  }

  void _handleChunkDownloadError(MainIsolateManager isolate, int chunkIndex, String? error) {
    print('Chunk $chunkIndex download error');

    _killIsolates();

    _onError?.call(error);
  }

  Future<void> _completeDownloadFile() async {
    assert(_chunks.every((chunk) => chunk.completed));

    File downloadFile = File(downloadPath);
    File saveFile = File(savePath + _copySuffix);
    IOSink? saveFileOutput;
    try {
      await saveFile.create(recursive: true);

      Stream<List<int>> inputStream = downloadFile.openRead(_preservedMetadataHeaderSize);
      saveFileOutput = saveFile.openWrite();

      await inputStream.forEach(saveFileOutput.add);

      await saveFileOutput.flush();
      await saveFileOutput.close();

      await saveFile.rename(savePath);

      await _raf.close();
      await downloadFile.delete();
    } on Exception catch (e) {
      print('Failed to complete download file.');

      await saveFileOutput?.flush();
      await saveFileOutput?.close();
      throw JDownloadException(JDownloadExceptionType.completeDownloadFileFailed, error: e);
    }

    _onDone?.call();

    _killIsolates();
  }

  void _tryStoreDownloadProgress() {
    DownloadProgress progress = DownloadProgress(
      url: url,
      savePath: savePath,
      totalBytes: totalBytes,
      chunks: _chunks,
    );
    _storeProgressSC.add(progress);
  }

  Future<void> _storeDownloadProgress(DownloadProgress progress) async {
    try {
      _raf = await _raf.setPosition(0);
      _raf = await _raf.writeFrom(progress.toBuffer);
    } on Exception catch (e) {
      print('Failed to store download progress');
    }
  }
}
