import 'dart:convert';
import 'dart:io';

// يقرأ ملف نصي مهما كان ترميزه، وما يطيح أبداً
//
// بعض الملفات (مثل README قديم) تكون محفوظة UTF-16 أو بترميز ويندوز القديم
// بدل UTF-8. readAsStringSync العادية تطيح معها، فنستخدم هذي بدالها.
String readTextSafely(File file) {
  final List<int> bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    return '';
  }
  return decodeTextSafely(bytes);
}

String decodeTextSafely(List<int> bytes) {
  // UTF-16 مع علامة BOM في البداية
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes.sublist(2), little: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes.sublist(2), little: false);
    }
  }
  // UTF-8 مع BOM
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  // أي حرف غلط يتحول لـ � بدل ما يطيح
  return utf8.decode(bytes.sublist(start), allowMalformed: true);
}

String _utf16(List<int> bytes, {required bool little}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}
