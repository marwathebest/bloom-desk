import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/services/project_launcher.dart';

Directory makeFolder(
  Map<String, String> files, {
  List<String> dirs = const [],
}) {
  final dir = Directory.systemTemp.createTempSync('bloom_launch_');
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

Project project(String path, ProjectType type, {String runCommand = ''}) =>
    Project(
      id: '1',
      name: 'x',
      path: path,
      type: type,
      color: Colors.pink,
      runCommand: runCommand,
    );

void main() {
  test('missing or wrong folder gives a clear error', () {
    expect(planLaunch(project('', ProjectType.flutter)).error, isNotNull);
    expect(
      planLaunch(project(r'C:\does\not\exist\here', ProjectType.flutter)).error,
      contains('ما لقيت المجلد'),
    );
  });

  test('Flutter prefers Chrome, then Windows, then default device', () {
    final web = makeFolder(
      {'pubspec.yaml': 'name: a'},
      dirs: ['web', 'windows'],
    );
    expect(
      planLaunch(project(web.path, ProjectType.flutter)).command,
      'flutter run -d chrome',
    );

    final win = makeFolder({'pubspec.yaml': 'name: a'}, dirs: ['windows']);
    expect(
      planLaunch(project(win.path, ProjectType.flutter)).command,
      'flutter run -d windows',
    );

    final none = makeFolder({'pubspec.yaml': 'name: a'});
    expect(
      planLaunch(project(none.path, ProjectType.flutter)).command,
      'flutter run',
    );
  });

  test('React installs packages first when node_modules is missing', () {
    final dir = makeFolder({
      'package.json': jsonEncode({
        'scripts': {'start': 'x', 'dev': 'y'},
      }),
    });
    expect(
      planLaunch(project(dir.path, ProjectType.react)).command,
      'npm install && npm run dev',
    );

    Directory(p.join(dir.path, 'node_modules')).createSync();
    expect(
      planLaunch(project(dir.path, ProjectType.react)).command,
      'npm run dev',
    );
  });

  test('React falls back to start, and errors with no scripts', () {
    final start = makeFolder(
      {
        'package.json': jsonEncode({
          'scripts': {'start': 'x'},
        }),
      },
      dirs: ['node_modules'],
    );
    expect(
      planLaunch(project(start.path, ProjectType.react)).command,
      'npm run start',
    );

    final none = makeFolder({'package.json': '{}'});
    expect(planLaunch(project(none.path, ProjectType.react)).error, isNotNull);
  });

  test('website opens index.html, other opens the folder', () {
    final site = makeFolder({'index.html': '<html></html>'});
    expect(
      planLaunch(project(site.path, ProjectType.website)).openPath,
      p.join(site.path, 'index.html'),
    );

    final other = makeFolder({'a.txt': 'a'});
    expect(
      planLaunch(project(other.path, ProjectType.other)).openPath,
      other.path,
    );
  });

  test('custom run command wins over detection', () {
    final dir = makeFolder({'pubspec.yaml': 'name: a'}, dirs: ['web']);
    final plan = planLaunch(
      project(
        dir.path,
        ProjectType.flutter,
        runCommand: 'flutter run -d windows --release',
      ),
    );
    expect(plan.command, 'flutter run -d windows --release');
  });

  test('live site opens its URL, even with no local folder', () {
    final live = Project(
      id: '1',
      name: 'site',
      color: Colors.pink,
      type: ProjectType.react,
      liveUrl: 'my-site.com',
    );
    final plan = planLaunch(live);
    expect(plan.url, 'https://my-site.com');
    expect(plan.error, isNull);

    // "Run from my device" ignores the live URL and needs the folder
    expect(planLaunch(live, local: true).error, isNotNull);
  });

  test('run locally uses the folder when a live URL exists', () {
    final dir = makeFolder({'pubspec.yaml': 'name: a'}, dirs: ['web']);
    final live = Project(
      id: '1',
      name: 'a',
      path: dir.path,
      color: Colors.pink,
      type: ProjectType.flutter,
      liveUrl: 'https://a.web.app',
    );
    expect(planLaunch(live).url, 'https://a.web.app');
    expect(planLaunch(live, local: true).command, 'flutter run -d chrome');
  });

  test('normalizeUrl keeps full URLs and adds https otherwise', () {
    expect(normalizeUrl(' http://x.com '), 'http://x.com');
    expect(normalizeUrl('x.com'), 'https://x.com');
  });

  test('liveUrl survives save and load', () {
    final original = Project(
      id: '1',
      name: 'a',
      color: Colors.pink,
      liveUrl: 'https://a.com',
    );
    expect(Project.fromJson(original.toJson()).liveUrl, 'https://a.com');
  });

  group('detectPort', () {
    test('server.js with PORT || 4173 (like the SPL game)', () {
      final dir = makeFolder({
        'package.json': jsonEncode({
          'scripts': {'start': 'node server.js'},
        }),
        'server.js':
            'const PORT = Number(process.env.PORT) || 4173;\n'
            'server.listen(PORT, HOST);',
      });
      expect(detectPort(dir.path), 4173);
      expect(
        planLaunch(project(dir.path, ProjectType.react)).localUrl,
        'http://localhost:4173',
      );
    });

    test('port in the script wins', () {
      final dir = makeFolder({
        'package.json': jsonEncode({
          'scripts': {'dev': 'vite --port 3005'},
          'devDependencies': {'vite': '^5'},
        }),
      });
      expect(detectPort(dir.path), 3005);
    });

    test('app.listen(8080)', () {
      final dir = makeFolder({
        'package.json': '{}',
        'index.js': 'app.listen(8080, () => {});',
      });
      expect(detectPort(dir.path), 8080);
    });

    test('tool defaults: vite 5173, next 3000', () {
      final vite = makeFolder({
        'package.json': jsonEncode({
          'devDependencies': {'vite': '^5'},
        }),
      });
      expect(detectPort(vite.path), 5173);
      final next = makeFolder({
        'package.json': jsonEncode({
          'dependencies': {'next': '14'},
        }),
      });
      expect(detectPort(next.path), 3000);
    });

    test('unknown port gives null and no auto-open', () {
      final dir = makeFolder({
        'package.json': jsonEncode({
          'scripts': {'start': 'node x.js'},
        }),
      });
      expect(detectPort(dir.path), isNull);
      expect(planLaunch(project(dir.path, ProjectType.react)).localUrl, isNull);
    });

    test('Flutter projects never get a localUrl', () {
      final dir = makeFolder({'pubspec.yaml': 'name: a'}, dirs: ['web']);
      expect(
        planLaunch(project(dir.path, ProjectType.flutter)).localUrl,
        isNull,
      );
    });
  });

  test('openWhenReady waits for the server, then opens it', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://localhost:${server.port}';
    server.listen(
      (req) => req.response
        ..write('ok')
        ..close(),
    );
    Uri? opened;
    final ok = await openWhenReady(
      url,
      open: (u) async {
        opened = u;
        return true;
      },
    );
    expect(ok, isTrue);
    expect(opened.toString(), url);
    await server.close(force: true);
  });

  test('openWhenReady gives up when nothing answers', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close(); // port now closed
    var opened = false;
    final ok = await openWhenReady(
      'http://localhost:$port',
      timeout: const Duration(seconds: 2),
      open: (_) async => opened = true,
    );
    expect(ok, isFalse);
    expect(opened, isFalse);
  });

  test('runCommand survives save and load', () {
    final original = project(r'C:\a', ProjectType.flutter, runCommand: 'go');
    final restored = Project.fromJson(original.toJson());
    expect(restored.runCommand, 'go');
    expect(
      Project.fromJson({'id': '1', 'name': 'old', 'color': 0xFF000000})
          .runCommand,
      '',
    );
  });
}
