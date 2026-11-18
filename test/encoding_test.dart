import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/services/project_detector.dart';
import 'package:bloom_desk/services/text_file.dart';

List<int> utf16le(String s) => [
  0xFF, 0xFE, // BOM
  for (final unit in s.codeUnits) ...[unit & 0xFF, unit >> 8],
];

Directory folder(String name, Map<String, List<int>> files) {
  final root = Directory.systemTemp.createTempSync('bloom_enc_');
  addTearDown(() => root.deleteSync(recursive: true));
  final dir = Directory(p.join(root.path, name))..createSync();
  files.forEach((file, bytes) {
    File(p.join(dir.path, file)).writeAsBytesSync(bytes);
  });
  return dir;
}

void main() {
  test(
    'decodeTextSafely handles UTF-8, UTF-8 BOM, UTF-16 and broken bytes',
    () {
      expect(decodeTextSafely(utf8.encode('مرحبا')), 'مرحبا');
      expect(decodeTextSafely([0xEF, 0xBB, 0xBF, ...utf8.encode('hi')]), 'hi');
      expect(decodeTextSafely(utf16le('مرحبا bank')), 'مرحبا bank');
      // Windows-1256 Arabic bytes are not valid UTF-8: no crash
      expect(() => decodeTextSafely([0xE3, 0xD1, 0xC8, 0xC7]), returnsNormally);
    },
  );

  test('a README in UTF-16 no longer breaks adding', () {
    final dir = folder('old-site', {
      'index.html': utf8.encode('<html></html>'),
      'README.md': utf16le('Live: https://old-site.onrender.com'),
    });
    final d = detectProject(dir.path);
    expect(d.name, 'old-site');
    expect(d.type, ProjectType.website);
    expect(d.liveUrl, 'https://old-site.onrender.com');
  });

  test('a README with broken bytes is read without crashing', () {
    final dir = folder('old-site', {
      'index.html': utf8.encode('<html></html>'),
      'README.md': [0xE3, 0xD1, 0xC8, 0xC7, 0x0A, 0xFF, 0xFE, 0x00],
    });
    expect(() => detectProject(dir.path), returnsNormally);
    expect(detectProject(dir.path).name, 'old-site');
  });

  test('package.json saved as UTF-16 is still understood', () {
    final dir = folder('app', {
      'package.json': utf16le(
        jsonEncode({
          'name': 'my-app',
          'scripts': {'dev': 'vite'},
        }),
      ),
    });
    final d = detectProject(dir.path);
    expect(d.type, ProjectType.react);
    expect(d.name, 'my-app');
  });
}
