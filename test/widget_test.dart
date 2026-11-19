import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bloom_desk/main.dart';
import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/services/project_detector.dart';

Directory makeFolder(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('bloom_test_');
  files.forEach((name, content) {
    final file = File(p.join(dir.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  group('detectProject', () {
    test('Flutter project: name, description and GitHub link', () {
      final dir = makeFolder({
        'pubspec.yaml':
            'name: rose_garden\r\ndescription: "Roses that grow"\r\n',
        '.git/config':
            '[remote "origin"]\n\turl = git@github.com:me/rose_garden.git\n',
      });
      final d = detectProject(dir.path);
      expect(d.type, ProjectType.flutter);
      expect(d.name, 'rose_garden');
      expect(d.description, 'Roses that grow');
      expect(d.links, ['https://github.com/me/rose_garden']);
    });

    test('default Flutter description is dropped', () {
      final dir = makeFolder({
        'pubspec.yaml': "name: app\ndescription: \"A new Flutter project.\"\n",
      });
      expect(detectProject(dir.path).description, '');
    });

    test('package.json project', () {
      final dir = makeFolder({
        'package.json': jsonEncode({
          'name': 'smart-scan',
          'description': 'Scanner',
        }),
      });
      final d = detectProject(dir.path);
      expect(d.type, ProjectType.react);
      expect(d.name, 'smart-scan');
      expect(d.description, 'Scanner');
    });

    test('broken package.json falls back to folder name', () {
      final dir = makeFolder({'package.json': '{oops'});
      final d = detectProject(dir.path);
      expect(d.type, ProjectType.react);
      expect(d.name, p.basename(dir.path));
    });

    test('website and plain folder', () {
      final site = makeFolder({'index.html': '<html></html>'});
      expect(detectProject(site.path).type, ProjectType.website);
      final plain = makeFolder({'notes.txt': 'hi'});
      final d = detectProject(plain.path);
      expect(d.type, ProjectType.other);
      expect(d.name, p.basename(plain.path));
      expect(d.links, isEmpty);
    });

    test('live URL from package.json homepage', () {
      final dir = makeFolder({
        'package.json': jsonEncode({
          'name': 'site',
          'homepage': 'https://me.github.io/site',
        }),
      });
      expect(detectProject(dir.path).liveUrl, 'https://me.github.io/site');
    });

    test('live URL from a CNAME file', () {
      final dir = makeFolder({
        'index.html': '<html></html>',
        'CNAME': 'www.my-site.com\n',
      });
      expect(detectProject(dir.path).liveUrl, 'https://www.my-site.com');
    });

    test('live URL from README prefers instant hosts over Render', () {
      final dir = makeFolder({
        'index.html': '<html></html>',
        'README.md':
            'Live: https://my-app.onrender.com/ and '
            '(https://me.github.io/my-app/). Docs: https://other.github.io/x',
      });
      // Folder name must appear in the link, so rename via a subfolder
      final project = Directory(p.join(dir.path, 'my-app'))..createSync();
      File(p.join(dir.path, 'README.md'))
          .copySync(p.join(project.path, 'README.md'));
      File(p.join(project.path, 'index.html')).writeAsStringSync('<html>');
      expect(
        detectProject(project.path).liveUrl,
        'https://me.github.io/my-app/',
      );
    });

    test('live URL from render.yaml service name', () {
      final dir = makeFolder({
        'index.html': '<html></html>',
        'render.yaml': 'services:\n  - type: web\n    name: my-site\n    runtime: static\n',
      });
      expect(detectProject(dir.path).liveUrl, 'https://my-site.onrender.com');
    });

    test('README links without the project name are ignored', () {
      final dir = makeFolder({
        'index.html': '<html></html>',
        'README.md': 'See https://someone.github.io/tutorial',
      });
      expect(detectProject(dir.path).liveUrl, '');
    });

    test('no live URL when nothing points to one', () {
      final dir = makeFolder({'index.html': '<html></html>'});
      expect(detectProject(dir.path).liveUrl, '');
    });

    test('https git url keeps host and drops .git', () {
      expect(
        gitUrlToWeb('https://github.com/me/app.git'),
        'https://github.com/me/app',
      );
    });
  });

  testWidgets('picking a folder adds the project with detected details', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'view': 'grid'});
    final dir = makeFolder({
      'pubspec.yaml': 'name: rose_garden\n',
      '.git/config': '\turl = https://github.com/me/rose_garden.git\n',
    });

    await tester.pumpWidget(BloomDeskApp(pickFolder: () async => dir.path));
    await tester.pumpAndSettle();
    expect(find.text('اسحب مجلد مشروعك هنا'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('rose_garden'), findsOneWidget);
    expect(find.textContaining('Flutter'), findsOneWidget);
    expect(
      find.text('🛠️ قيد العمل'),
      findsOneWidget,
    ); // new projects start in progress
    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('مشاريعي (1)'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('projects')!) as List;
    expect(saved.single['path'], dir.path);

    // Adding the same folder again is skipped
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('مشاريعي (1)'), findsOneWidget);
  });

  testWidgets('saved projects load, edit rejects empty name, delete works', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'view': 'grid',
      'projects': jsonEncode([
        {
          'id': '1',
          'name': 'Rose Garden',
          'description': 'حديقة ورود',
          'path': r'C:\rose_garden',
          'type': 'flutter',
          'color': 0xFFE0607E,
          'links': ['github.com/me/rose'],
        },
      ]),
    });
    await tester.pumpWidget(const BloomDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('Rose Garden'), findsOneWidget);
    expect(find.text('github.com'), findsOneWidget);

    // Edit: clearing the name is rejected
    await tester.tap(find.byTooltip('خيارات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('اكتب اسم المشروع'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    // Delete
    await tester.tap(find.byTooltip('خيارات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(find.text('Rose Garden'), findsNothing);
    expect(find.text('اسحب مجلد مشروعك هنا'), findsOneWidget);
  });
}
