import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bloom_desk/services/save_queue.dart';

// Runs around every test file: each test starts with an empty save queue,
// so a save left pending when one test ends can't block the next test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(SaveQueue.shared.reset);
  await testMain();
}
