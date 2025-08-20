import 'dart:developer' as developer;

class Logger {
  void warning(String message) {
    developer.log(message, name: 'WARNING');
  }
}

final logger = Logger();
