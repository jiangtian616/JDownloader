import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:j_downloader/j_downloader.dart';
import 'package:j_downloader/src/exception/j_download_exception.dart';
import 'package:j_downloader/src/extension/file_extension.dart';
import 'package:j_downloader/src/file/file_manager.dart';
import 'package:j_downloader/src/function/function.dart';
import 'package:j_downloader/src/isolate/main_isolate_manager.dart';
import 'package:j_downloader/src/model/download_chunk.dart';
import 'package:j_downloader/src/model/download_progress.dart';
import 'package:retry/retry.dart';

class DownloadManager {
  final String url;
  final String downloadPath;
  final String savePath;

  late int _isolateCount;

  final Dio _dio = Dio();

  late final int totalBytes;

  bool _fileReady = false;
  late FileManager _fileManager;

  bool _chunksReady = false;
  List<DownloadTrunk> _chunks = [];
  List<bool> _chunksBusy = [];

  int get currentBytes => _chunks.fold(0, (previousValue, element) => previousValue + element.downloadedBytes);

  bool _isolatesReady = false;
  List<MainIsolateManager> _isolates = [];

  Future? _configUpdatingFuture;

  DownloadProgressCallback? _onProgress;
  VoidCallback? _onDone;
  ValueCallback<String?>? _onError;

  static const int _preservedMetadataHeaderSize = 1024 * 16;

  static const String _copySuffix = '.jdcopy';

  DownloadManager({
    required this.url,
    required this.downloadPath,
    required this.savePath,
    required int isolateCount,
  }) : _isolateCount = isolateCount;

  void tryRecoverFromMetadata(bool deleteWhenUrlMismatch) {
    File downloadFile = File(downloadPath);
    if (!downloadFile.existsSync()) {
      return;
    }

    RandomAccessFile? raf;
    Uint8List metadataHeader;
    try {
      raf = downloadFile.openSync(mode: FileMode.read);
      metadataHeader = raf.readSync(_preservedMetadataHeaderSize);
      raf.closeSync();
    } on Exception catch (e) {
      raf?.closeSync();
      downloadFile.deleteSyncIgnoreError();
      return;
    }

    DownloadProgress progress = DownloadProgress.fromBuffer(metadataHeader);
    if (progress.url != url && deleteWhenUrlMismatch) {
      downloadFile.deleteSyncIgnoreError();
      return;
    }

    totalBytes = progress.totalBytes;
    _chunks = progress.chunks;
    _chunksBusy = List.generate(_chunks.length, (_) => false);
    _chunksReady = true;
  }

  Future<void> start() async {
    await _configUpdatingFuture;

    await _initTrunks();

    await _preCreateDownloadFile();

    await _startIsolates();

    await _tryHandleTrunks();
  }

  Future<void> pause() async {
    return _killIsolates();
  }

  Future<void> dispose() async {
    await pause();

    if (_fileReady) {
      await _fileManager.close();
      _fileReady = false;
    }

    File downloadFile = File(downloadPath);
    if (await downloadFile.exists()) {
      await downloadFile.delete();
    }

    _chunks.clear();
    _chunksBusy.clear();
    _chunksReady = false;
  }

  Future<void> changeIsolateCount(int count) async {
    if (_isolateCount == count) {
      return;
    }

    Completer completer = Completer();
    _configUpdatingFuture = completer.future;

    bool wasRunning = _isolatesReady;
    await pause();

    _isolateCount = count;

    /// add chunk if uncompleted chunk is less than isolate count
    if (_chunksReady && _chunks.where((c) => !c.completed).length < _isolateCount && !_chunks.every((chunk) => chunk.completed)) {
      List<DownloadTrunk> newChunks = [];

      for (int i = 0; i < _chunks.length; i++) {
        if (_chunks[i].downloadedBytes != 0) {
          newChunks.add(
            DownloadTrunk(size: _chunks[i].downloadedBytes, downloadedBytes: _chunks[i].downloadedBytes),
          );
        }
        if (_chunks[i].downloadedBytes != _chunks[i].size) {
          newChunks.add(
            DownloadTrunk(size: _chunks[i].size - _chunks[i].downloadedBytes),
          );
        }
      }

      while (newChunks.where((c) => !c.completed).length < _isolateCount) {
        int largestUnCompletedChunkIndex = -1;
        int largestUnCompletedChunkSize = 0;
        for (int i = 0; i < newChunks.length; i++) {
          if (newChunks[i].completed) {
            continue;
          }
          if (newChunks[i].size > largestUnCompletedChunkSize) {
            largestUnCompletedChunkIndex = i;
            largestUnCompletedChunkSize = newChunks[i].size;
          }
        }

        if (largestUnCompletedChunkIndex == -1 || largestUnCompletedChunkSize <= 1) {
          break;
        }

        newChunks[largestUnCompletedChunkIndex] = DownloadTrunk(size: largestUnCompletedChunkSize ~/ 2);
        newChunks.insert(largestUnCompletedChunkIndex + 1, DownloadTrunk(size: largestUnCompletedChunkSize - largestUnCompletedChunkSize ~/ 2));
      }

      _chunks = newChunks;
      _chunksBusy = List.generate(_chunks.length, (_) => false);

      if (_fileReady) {
        await _storeCurrentDownloadProgress();
      }
    }

    completer.complete();
    _configUpdatingFuture = null;

    if (wasRunning) {
      return start();
    }
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
      throw JDownloadException(JDownloadExceptionType.fetchContentLengthFailed, error: e);
    }

    int? contentLength = int.tryParse(response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
    if (contentLength == null) {
      throw JDownloadException(JDownloadExceptionType.noContentLengthHeaderFound);
    }

    totalBytes = contentLength;

    _chunks = List.generate(
      _isolateCount,
      (index) => DownloadTrunk(
        size: index != _isolateCount - 1 ? contentLength ~/ _isolateCount : contentLength - (_isolateCount - 1) * (contentLength ~/ _isolateCount),
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
      List<Completer<void>> readyCompleters = List.generate(_isolateCount, (_) => Completer<void>());
      for (int i = 0; i < _isolateCount; i++) {
        MainIsolateManager isolateManager = MainIsolateManager()
          ..registerOnReady(readyCompleters[i].complete)
          ..initIsolate();
        _isolates.add(isolateManager);
      }

      await Future.wait(readyCompleters.map((e) => e.future));
    } on Exception catch (e) {
      await _killIsolates();
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

  Future<void> _preCreateDownloadFile() async {
    if (_fileReady) {
      return;
    }

    try {
      File downloadFile = File(downloadPath);
      if (!await downloadFile.exists()) {
        await downloadFile.create(recursive: true);
      }

      _fileManager = FileManager(downloadPath);

      await _storeCurrentDownloadProgress();

      await _fileManager.truncate(_preservedMetadataHeaderSize + totalBytes);

      _fileReady = true;
    } on Exception catch (e) {
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

  Future<void> _killIsolates() async {
    List<Future> killFutures = _isolates.map((e) => e.killIsolate()).toList();

    for (MainIsolateManager isolate in _isolates) {
      isolate.unRegisterOnProgress();
      isolate.unRegisterOnDone();
      isolate.unRegisterOnError();
    }

    _chunksBusy = List.generate(_chunks.length, (_) => false);
    _isolatesReady = false;

    await Future.wait(killFutures);
  }

  void _handleChunkDownloadProgress(MainIsolateManager isolate, int chunkIndex, int newDownloadedBytes) {
    _chunks[chunkIndex].downloadedBytes += newDownloadedBytes;

    print('chunk $chunkIndex: ${_chunks[chunkIndex].downloadedBytes}/${_chunks[chunkIndex].size}');

    _onProgress?.call(currentBytes, totalBytes);

    _storeCurrentDownloadProgress();
  }

  void _handleChunkDownloadComplete(MainIsolateManager isolate, int chunkIndex) {
    assert(_chunks[chunkIndex].completed);

    _chunksBusy[chunkIndex] = false;

    _tryHandleTrunks();
  }

  Future<void> _handleChunkDownloadError(MainIsolateManager isolate, int chunkIndex, String? error) async {
    print('chunk $chunkIndex: $error');

    await _killIsolates();

    _onError?.call(error);
  }

  Future<void> _completeDownloadFile() async {
    assert(_chunks.every((chunk) => chunk.completed));

    File downloadFile = File(downloadPath);
    File saveFile = File(savePath + _copySuffix);
    IOSink? saveFileOutput;
    try {
      await _fileManager.close();

      await saveFile.create(recursive: true);

      Stream<List<int>> inputStream = downloadFile.openRead(_preservedMetadataHeaderSize);
      saveFileOutput = saveFile.openWrite();

      await inputStream.forEach(saveFileOutput.add);
      await saveFileOutput.flush();
      await saveFileOutput.close();

      await saveFile.rename(savePath);
      await downloadFile.delete();
    } on Exception catch (e) {
      await saveFileOutput?.close();
      _onError?.call(e.toString());
      return;
    } finally {
      await _killIsolates();
    }

    _onDone?.call();
  }

  Future<void> _storeCurrentDownloadProgress() async {
    DownloadProgress progress = DownloadProgress(
      url: url,
      savePath: savePath,
      totalBytes: totalBytes,
      chunks: _chunks,
    );

    try {
      await _fileManager.writeFrom(progress.toBuffer, position: 0);
    } on Exception catch (e) {
      /// ignore error after download complete
    }
  }
}
