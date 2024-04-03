import 'package:logger/logger.dart';

import '../function/function.dart';

class JDownloadLogOutput extends LogOutput {
  ValueCallback<OutputEvent>? _callback;

  @override
  void output(OutputEvent event) {
    _callback?.call(event);
  }

  void registerCallBack(ValueCallback<OutputEvent> callback) {
    _callback = callback;
  }

  void unregisterCallBack() {
    _callback = null;
  }
}
