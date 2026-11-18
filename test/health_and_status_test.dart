import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bloom_desk/main.dart';
import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/services/health_check.dart';

Directory makeFolder(
  Map<String, String> files, {
  List<String> dirs = const [],
}) {
  final dir = Directory.systemTemp.createTempSync('bloom_health_');
  files.forEach((name, content) {
    final file = File(p.join(dir.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  for (final d in dirs) {
    Directory(p.join(dir.path, d)).createSync(recursive: true);
  }
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Project make({
  String path = '',
  ProjectType type = ProjectType.other,
  String liveUrl = '',
}) => Project(
  id: '1',
  name: 'x',
  path: path,
  type: type,
  color: Colors.pink,
  liveUrl: liveUrl,
);

void main() {
  group('checkProject: live sites', () {
    test('fast 200 is ready', () async {
      final r = await checkProject(
        make(liveUrl: 'a.com'),
        fetchStatus: (_, _) async => 200,
      );
      expect(r.level, HealthLevel.ok);
      expect(r.message, 'الموقع جاهز');
    });

    test('slow answer means it was asleep and is now awake', () async {
      final r = await checkProject(
        make(liveUrl: 'https://a.onrender.com'),
        slowAfter: Duration.zero,
        fetchStatus: (_, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 200;
        },
      );
      expect(r.level, HealthLevel.ok);
      expect(r.message, contains('صحّيناه'));
    });

    test('no answer or error status is a problem', () async {
      final none = await checkProject(
        make(liveUrl: 'a.com'),
        fetchStatus: (_, _) async => null,
      );
      expect(none.level, HealthLevel.error);
      final bad = await checkProject(
        make(liveUrl: 'a.com'),
        fetchStatus: (_, _) async => 503,
      );
      expect(bad.level, HealthLevel.error);
      expect(bad.message, contains('503'));
    });

    test('uses https when the link has no scheme', () async {
      Uri? asked;
      await checkProject(
        make(liveUrl: 'a.com'),
        fetchStatus: (uri, _) async {
          asked = uri;
          return 200;
        },
      );
      expect(asked.toString(), 'https://a.com');
    });
  });

  group('checkProject: local projects', () {
    test('missing folder or no folder at all', () async {
      expect((await checkProject(make())).level, HealthLevel.error);
      final r = await checkProject(make(path: r'C:\nope\nowhere\123'));
      expect(r.level, HealthLevel.error);
      expect(r.message, contains('مفقود'));
    });

    test('Flutter without .dart_tool needs pub get', () async {
      final dir = makeFolder({'pubspec.yaml': 'name: a'});
      final r = await checkProject(
        make(path: dir.path, type: ProjectType.flutter),
      );
      expect(r.level, HealthLevel.warn);
      expect(r.fixCommand, 'flutter pub get');

      Directory(p.join(dir.path, '.dart_tool')).createSync();
      final ready = await checkProject(
        make(path: dir.path, type: ProjectType.flutter),
      );
      expect(ready.level, HealthLevel.ok);
    });

    test('Node without node_modules needs npm install', () async {
      final dir = makeFolder({
        'package.json': jsonEncode({
          'scripts': {'start': 'node server.js'},
        }),
      });
      final r = await checkProject(
        make(path: dir.path, type: ProjectType.react),
      );
      expect(r.level, HealthLevel.warn);
      expect(r.fixCommand, 'npm install');
    });

    test('Node with no start script is a problem', () async {
      final dir = makeFolder({'package.json': '{}'}, dirs: ['node_modules']);
      final r = await checkProject(
        make(path: dir.path, type: ProjectType.react),
      );
      expect(r.level, HealthLevel.error);
    });

    test('website needs index.html', () async {
      final empty = makeFolder({'a.txt': ''});
      expect(
        (await checkProject(make(path: empty.path, type: ProjectType.website)))
            .level,
        HealthLevel.warn,
      );
      final site = makeFolder({'index.html': ''});
      expect(
        (await checkProject(make(path: site.path, type: ProjectType.website)))
            .level,
        HealthLevel.ok,
      );
    });
  });

  test('status survives save and load, old data defaults to in progress', () {
    final done = make()..status = ProjectStatus.done;
    expect(Project.fromJson(done.toJson()).status, ProjectStatus.done);
    expect(
      Project.fromJson({'id': '1', 'name': 'a', 'color': 0}).status,
      ProjectStatus.inProgress,
    );
  });

  testWidgets('change status on a card and filter by it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'projects': jsonEncode([
        {'id': '1', 'name': 'Alpha', 'color': 0xFFE0607E, 'status': 'done'},
        {'id': '2', 'name': 'Beta', 'color': 0xFF4E9A6B},
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BloomDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('✅ مكتمل (1)'), findsOneWidget);
    expect(find.text('🛠️ قيد العمل (1)'), findsOneWidget);

    // Filter: done only
    await tester.tap(find.text('✅ مكتمل (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    // Back to all, mark Beta as done from its card
    await tester.tap(find.text('الكل (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🛠️ قيد العمل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('✅  مكتمل'));
    await tester.pumpAndSettle();

    expect(find.text('✅ مكتمل (2)'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('projects')!) as List;
    expect(saved.map((p) => p['status']), everyElement('done'));
  });
}
