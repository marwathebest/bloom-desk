import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import 'project_launcher.dart';

// نتيجة الفحص: 🟢 جاهز، 🟡 يحتاج شيء بسيط، 🔴 فيه مشكلة
enum HealthLevel { ok, warn, error }

class HealthResult {
  const HealthResult(this.level, this.message, {this.fixCommand});

  const HealthResult.ok(String message) : this(HealthLevel.ok, message);
  const HealthResult.warn(String message, {String? fix})
    : this(HealthLevel.warn, message, fixCommand: fix);
  const HealthResult.error(String message) : this(HealthLevel.error, message);

  final HealthLevel level;
  final String message;
  final String? fixCommand; // أمر يصلّح المشكلة (لو فيه)
}

// يسأل الرابط ويرجّع رقم الرد (200 = تمام)، أو null لو ما رد
typedef StatusFetcher = Future<int?> Function(Uri uri, Duration timeout);

// يفحص مشروع واحد قبل العرض
Future<HealthResult> checkProject(
  Project project, {
  StatusFetcher? fetchStatus,
  Duration timeout = const Duration(seconds: 75),
  Duration slowAfter = const Duration(seconds: 8),
}) async {
  // ١. مشروع منشور: نفتح موقعه ونتأكد أنه يرد
  // (وهذا يصحّي مواقع Render النايمة قبل العرض)
  if (project.liveUrl.trim().isNotEmpty) {
    final uri = Uri.parse(normalizeUrl(project.liveUrl));
    final stopwatch = Stopwatch()..start();
    final status = await (fetchStatus ?? _fetchStatus)(uri, timeout);
    stopwatch.stop();

    if (status == null) return const HealthResult.error('الموقع ما يرد');
    if (status >= 400) return HealthResult.error('الموقع يرد بخطأ $status');
    if (stopwatch.elapsed > slowAfter) {
      return const HealthResult.ok('جاهز (كان نايم وصحّيناه ☕)');
    }
    return const HealthResult.ok('الموقع جاهز');
  }

  // ٢. مشروع محلي: نتأكد من المجلد والملفات
  final path = project.path.trim();
  if (path.isEmpty) {
    return const HealthResult.error('ما فيه مجلد ولا رابط موقع');
  }
  if (!Directory(path).existsSync()) {
    return const HealthResult.error('المجلد مفقود أو تغيّر مكانه');
  }

  bool has(String name) =>
      FileSystemEntity.typeSync(p.join(path, name)) !=
      FileSystemEntityType.notFound;

  switch (project.type) {
    case ProjectType.flutter:
      if (!has('pubspec.yaml')) {
        return const HealthResult.error('ما لقيت pubspec.yaml');
      }
      if (!has('.dart_tool')) {
        return const HealthResult.warn(
          'المكتبات مو محمّلة',
          fix: 'flutter pub get',
        );
      }
      return const HealthResult.ok('جاهز للتشغيل');

    case ProjectType.react:
      final plan = planLaunch(project, local: true);
      if (plan.error != null) return HealthResult.error(plan.error!);
      if (!has('node_modules')) {
        return const HealthResult.warn(
          'المكتبات مو محمّلة',
          fix: 'npm install',
        );
      }
      return const HealthResult.ok('جاهز للتشغيل');

    case ProjectType.website:
      return has('index.html')
          ? const HealthResult.ok('جاهز للعرض')
          : const HealthResult.warn('ما لقيت index.html');

    case ProjectType.other:
      return const HealthResult.ok('المجلد موجود');
  }
}

Future<int?> _fetchStatus(Uri uri, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return response.statusCode;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}
