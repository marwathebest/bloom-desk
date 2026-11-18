import 'dart:io';

import 'package:path/path.dart' as p;

// النسخ الأولى من Bloom Desk كانت تحفظ بياناتها في مجلد اسمه com.example
// هذي الدالة تنقل مشاريعك ووردك للمكان الجديد مرة وحدة بس
Future<void> migrateOldData({
  required String appData,
  required String newSupportDir,
}) async {
  const fileName = 'shared_preferences.json';
  final oldFile = File(p.join(appData, 'com.example', 'bloom_desk', fileName));
  final newFile = File(p.join(newSupportDir, fileName));

  if (!oldFile.existsSync() || newFile.existsSync()) return;
  await newFile.parent.create(recursive: true);
  await oldFile.copy(newFile.path);
}
