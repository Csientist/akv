import 'package:logger/logger.dart';

/// A global, easy-to-use logger.
/// Simply call: Log.i('Hello'); or Log.e('Error!');
class Log {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, // Number of method calls to be displayed
      errorMethodCount: 5, // Number of method calls if stacktrace is provided
      lineLength: 80, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      // dateTimeFormat: DateTimeFormat.dateAndTime, // Optional: add timestamps
    ),
  );

  /// 💡 Info: General application flow
  static void i(dynamic message) {
    _logger.i(message);
  }

  /// 🐛 Debug: Useful for tracking state or variables
  static void d(dynamic message) {
    _logger.d(message);
  }

  /// ⚠️ Warning: Something unexpected happened, but it's not fatal
  static void w(dynamic message) {
    _logger.w(message);
  }

  /// 🛑 Error: Something broke! (Pass the exception object here if you have one)
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
}