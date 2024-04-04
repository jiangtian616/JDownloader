class JDownloadException implements Exception {
  final JDownloadExceptionType type;

  final dynamic error;

  JDownloadException(this.type, {this.error});

  @override
  String toString() {
    return 'JDownloadException{type: $type, error: $error}';
  }
}

enum JDownloadExceptionType {
  fetchContentLengthFailed(10, 'Failed to get content-length from url response.'),
  noContentLengthHeaderFound(20, 'No content-length header found in url response.'),
  startIsolateFailed(30, 'Failed to start isolate.'),
  preCreateDownloadFileFailed(40, 'Failed to pre-create download file.'),
  downloadFailed(50, 'Download failed.'),
  serverNotSupport(60, 'Server does not support range requests.'),
  writeDownloadFileFailed(70, 'Write download file failed.'),
  completeDownloadFileFailed(80, 'Failed to complete download file.'),
  ;

  final int code;

  final String desc;

  const JDownloadExceptionType(this.code, this.desc);
}
