class DownloadTrunk {
  final int size;

  int downloadedBytes;

  bool get completed => downloadedBytes == size;

  DownloadTrunk({
    required this.size,
    this.downloadedBytes = 0,
  });

  factory DownloadTrunk.fromJson(Map<String, dynamic> json) {
    return DownloadTrunk(
      size: json["size"],
      downloadedBytes: json["downloadedBytes"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "size": this.size,
      "downloadedBytes": this.downloadedBytes,
    };
  }

  @override
  String toString() {
    return 'DownloadTrunk{size: $size, downloadedBytes: $downloadedBytes}';
  }
}
