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
  cancel(40),
  error(50),
  done(60),
  ;

  final int code;

  const SubIsolateMessageType(this.code);
}
