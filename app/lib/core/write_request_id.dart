import 'dart:math';

/// A stable identifier for one user-initiated create action.
///
/// Keep the same value while a form retries so a lost HTTP response cannot
/// turn a successful write into a duplicate record.
String newWriteRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String childWriteRequestId(String parent, int index) => '$parent:$index';
