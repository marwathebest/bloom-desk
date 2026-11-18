import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:bloom_desk/services/migrate_old_data.dart';

void main() {
  late Directory appData;
  late String newDir;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('bloom_migrate_');
    newDir = p.join(appData.path, 'Bloom Desk', 'Bloom Desk');
  });
  tearDown(() => appData.deleteSync(recursive: true));

  File oldFile() => File(
    p.join(
      appData.path,
      'com.example',
      'bloom_desk',
      'shared_preferences.json',
    ),
  );
  File newFile() => File(p.join(newDir, 'shared_preferences.json'));

  test('copies old data to the new folder once', () async {
    oldFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('{"old":true}');
    await migrateOldData(appData: appData.path, newSupportDir: newDir);
    expect(newFile().readAsStringSync(), '{"old":true}');
    expect(oldFile().existsSync(), isTrue); // old copy kept as a backup
  });

  test('never overwrites data already in the new folder', () async {
    oldFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('{"old":true}');
    newFile()
      ..createSync(recursive: true)
      ..writeAsStringSync('{"new":true}');
    await migrateOldData(appData: appData.path, newSupportDir: newDir);
    expect(newFile().readAsStringSync(), '{"new":true}');
  });

  test('does nothing for new users', () async {
    await migrateOldData(appData: appData.path, newSupportDir: newDir);
    expect(newFile().existsSync(), isFalse);
  });
}
