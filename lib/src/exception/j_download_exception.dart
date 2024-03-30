class JDownloadException implements Exception {
  final JDownloadExceptionType type;

  final Object? error;

  JDownloadException(this.type, {this.error});

  @override
  String toString() {
    return 'JDownloadException, type: ${type.desc}${error != null ? ' Error: $error' : ''}';
  }
}

enum JDownloadExceptionType {
  fetchContentLengthFailed(10, 'Failed to get content-length from url response.'),
  noContentLengthHeaderFound(20, 'No content-length header found in url response.'),
  startIsolateFailed(30, 'Failed to start isolate.'),
  preCreateDownloadFileFailed(40, 'Failed to pre-create download file.'),
  completeDownloadFileFailed(50, 'Failed to complete download file.'),
  ;

  final int code;

  final String desc;

  const JDownloadExceptionType(this.code, this.desc);
}
