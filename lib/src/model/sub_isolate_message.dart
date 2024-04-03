class SubIsolateMessage<T> {
  final SubIsolateMessageType type;
  final T data;

  SubIsolateMessage(this.type, this.data);

  @override
  String toString() {
    return 'SubIsolateMessage{type: $type, data: $data}';
  }
}

enum SubIsolateMessageType {
  log(00),
  init(10),
  begin(20),
  progress(30),
  error(40),
  done(80),
  closeReady(90),
  closed(100),
  ;

  final int code;

  const SubIsolateMessageType(this.code);
}
