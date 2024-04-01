class MainIsolateMessage<T> {
  final MainIsolateMessageType type;
  final T data;

  MainIsolateMessage(this.type, this.data);

  @override
  String toString() {
    return 'MainIsolateMessage{type: $type, data: $data}';
  }
}

enum MainIsolateMessageType {
  download(10),
  close(20),
  ;

  final int code;

  const MainIsolateMessageType(this.code);
}
