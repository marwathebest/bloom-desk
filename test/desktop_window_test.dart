import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bloom_desk/services/desktop_window.dart';

// Loads the real Windows functions (user32.dll). The test process has no
// Bloom Desk window, so every call must quietly do nothing instead of crashing.
void main() {
  test(
    'Windows calls load and do nothing when there is no app window',
    () async {
      final window = Win32Window();
      expect(await window.bounds(), isNull);
      await window.setBounds(const Rect.fromLTWH(0, 0, 300, 300));
      await window.setAlwaysOnTop(true);
      await window.setAlwaysOnTop(false);
      await window.flash();
      await window.bringToFront();
    },
    skip: !Platform.isWindows,
  );
}
