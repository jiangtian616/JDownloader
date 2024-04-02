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
  init(10),
  begin(20),
  progress(30),
  error(40),
  done(50),
  closeReady(60),
  closed(70),
  ;

  final int code;

  const SubIsolateMessageType(this.code);
}
