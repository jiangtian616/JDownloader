import 'dart:convert';
import 'dart:typed_data';

import 'package:j_downloader/src/model/download_chunk.dart';

class DownloadProgress {
  final String url;

  final String savePath;

  final int totalBytes;

  final List<DownloadTrunk> chunks;

  const DownloadProgress({
    required this.url,
    required this.savePath,
    required this.totalBytes,
    required this.chunks,
  });

  Uint8List get toBuffer {
    Uint8List buffer = utf8.encode(jsonEncode(this));
    return Uint8List.fromList([buffer.length & 0xFF, buffer.length >> 8] + buffer);
  }

  factory DownloadProgress.fromBuffer(Uint8List buffer) {
    int length = buffer[0] + (buffer[1] << 8);
    return DownloadProgress.fromJson(jsonDecode(utf8.decode(buffer.sublist(2, 2 + length))));
  }

  factory DownloadProgress.fromJson(Map<String, dynamic> json) {
    return DownloadProgress(
      url: json["url"],
      savePath: json["savePath"],
      totalBytes: json["totalBytes"],
      chunks: (jsonDecode(json["chunks"]) as List).map((e) => DownloadTrunk.fromJson(e)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "url": this.url,
      "savePath": this.savePath,
      "totalBytes": this.totalBytes,
      "chunks": jsonEncode(this.chunks),
    };
  }

  @override
  String toString() {
    return 'DownloadProgress{url: $url, savePath: $savePath, totalBytes: $totalBytes, chunks: $chunks}';
  }
}
