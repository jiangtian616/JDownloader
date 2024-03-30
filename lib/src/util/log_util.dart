import 'package:logging/logging.dart';
import 'package:sprintf/sprintf.dart';

class Log {
  static final Logger _logger = Logger('jdownloader')..onRecord.listen(output);

  static set level(Level level) {
    _logger.level = level;
  }

  static final Map<Level, AnsiColor> levelColors = {
    Level.FINEST: AnsiColor.fg(AnsiColor.grey(0.5)),
    Level.FINE: AnsiColor.none(),
    Level.INFO: AnsiColor.fg(12),
    Level.WARNING: AnsiColor.fg(208),
    Level.SEVERE: AnsiColor.fg(196),
  };

  static void finest(Object? message, {Object? error, StackTrace? stackTrace}) => _logger.log(Level.FINEST, message, error, stackTrace);

  static void fine(Object? message, {Object? error, StackTrace? stackTrace}) => _logger.log(Level.FINE, message, error, stackTrace);

  static void info(Object? message, {Object? error, StackTrace? stackTrace}) => _logger.log(Level.INFO, message, error, stackTrace);

  static void warning(Object? message, {Object? error, StackTrace? stackTrace}) => _logger.log(Level.WARNING, message, error, stackTrace);

  static void severe(Object? message, {Object? error, StackTrace? stackTrace}) => _logger.log(Level.SEVERE, message, error, stackTrace);

  static void output(LogRecord record) {
    final AnsiColor color = levelColors[record.level]!;

    print(color(sprintf('[%s]%9s %s: %s', [
      record.time.toString().substring(11, 23),
      '[${record.level.name}]',
      record.loggerName,
      record.message,
    ])));

    if (record.error != null) {
      print(color(sprintf('%s', [record.error])));
    }
    if (record.stackTrace != null) {
      print(color(sprintf('%s', [record.stackTrace])));
    }
  }
}

/// This class handles colorizing of terminal output.
class AnsiColor {
  /// ANSI Control Sequence Introducer, signals the terminal for new settings.
  static const ansiEsc = '\x1B[';

  /// Reset all colors and options for current SGRs to terminal defaults.
  static const ansiDefault = '${ansiEsc}0m';

  final int? fg;
  final int? bg;
  final bool color;

  AnsiColor.none()
      : fg = null,
        bg = null,
        color = false;

  AnsiColor.fg(this.fg)
      : bg = null,
        color = true;

  AnsiColor.bg(this.bg)
      : fg = null,
        color = true;

  @override
  String toString() {
    if (fg != null) {
      return '${ansiEsc}38;5;${fg}m';
    } else if (bg != null) {
      return '${ansiEsc}48;5;${bg}m';
    } else {
      return '';
    }
  }

  String call(String msg) {
    if (color) {
      return '${toString()}$msg$ansiDefault';
    } else {
      return msg;
    }
  }

  AnsiColor toFg() => AnsiColor.fg(bg);

  AnsiColor toBg() => AnsiColor.bg(fg);

  /// Defaults the terminal's foreground color without altering the background.
  String get resetForeground => color ? '${ansiEsc}39m' : '';

  /// Defaults the terminal's background color without altering the foreground.
  String get resetBackground => color ? '${ansiEsc}49m' : '';

  static int grey(double level) => 232 + (level.clamp(0.0, 1.0) * 23).round();
}
