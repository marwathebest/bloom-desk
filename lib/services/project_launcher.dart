import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/project.dart';
import 'text_file.dart';

// الخطة: وش بنسوي لما تضغط "اعرض"
class LaunchPlan {
  const LaunchPlan.command(String this.command, {this.localUrl})
    : openPath = null,
      url = null,
      error = null;
  const LaunchPlan.open(String this.openPath)
    : command = null,
      url = null,
      localUrl = null,
      error = null;
  const LaunchPlan.url(String this.url)
    : command = null,
      openPath = null,
      localUrl = null,
      error = null;
  const LaunchPlan.error(String this.error)
    : command = null,
      openPath = null,
      url = null,
      localUrl = null;

  final String? command; // أمر يشتغل في نافذة تيرمنال
  final String? openPath; // ملف أو مجلد ينفتح بالبرنامج الافتراضي
  final String? url; // رابط الموقع المنشور
  final String? localUrl; // نفتحه في المتصفح أول ما السيرفر يجهز
  final String? error; // سبب ما نقدر نشغّل
}

// يحاول يعرف رقم البورت اللي يشتغل عليه سيرفر Node / React
int? detectPort(String path) {
  final packageFile = File(p.join(path, 'package.json'));
  Map? package;
  try {
    final json = jsonDecode(readTextSafely(packageFile));
    if (json is Map) package = json;
  } on Object {
    package = null;
  }

  // ١. من أمر التشغيل نفسه:  --port 3001  أو  PORT=3001
  final scripts = package?['scripts'];
  if (scripts is Map) {
    for (final name in ['dev', 'start']) {
      final script = scripts[name];
      if (script is! String) continue;
      final match = RegExp(r'(?:--port[= ]|PORT=)(\d{2,5})').firstMatch(script);
      if (match != null) return int.parse(match.group(1)!);
    }
  }

  // ٢. من ملفات السيرفر:  PORT || 4173  أو  listen(3000  أو  port: 5174
  final candidates = [
    'server.js',
    'index.js',
    'app.js',
    'main.js',
    'server.mjs',
    'vite.config.js',
    'vite.config.ts',
    'vite.config.mjs',
  ];
  for (final name in candidates) {
    final file = File(p.join(path, name));
    if (!file.existsSync()) continue;
    final match = RegExp(
      r'(?:PORT\)?\s*\|\|\s*|\.listen\(\s*|\bport\s*:\s*)(\d{2,5})',
    ).firstMatch(readTextSafely(file));
    if (match != null) return int.parse(match.group(1)!);
  }

  // ٣. البورت الافتراضي للأدوات المشهورة
  final deps = {
    ...?(package?['dependencies'] as Map?),
    ...?(package?['devDependencies'] as Map?),
  };
  if (deps.containsKey('vite')) return 5173;
  if (deps.containsKey('next') || deps.containsKey('react-scripts')) {
    return 3000;
  }
  return null;
}

// يكمّل الرابط لو ناقصه https://
String normalizeUrl(String url) {
  final trimmed = url.trim();
  return trimmed.contains('://') ? trimmed : 'https://$trimmed';
}

// يقرر كيف يشتغل المشروع حسب نوعه والملفات اللي فيه
// local = true يعني شغّله من جهازك حتى لو عنده موقع منشور
LaunchPlan planLaunch(Project project, {bool local = false}) {
  // المشروع منشور؟ نفتح موقعه الحقيقي، وما نحتاج المجلد أصلاً
  if (!local && project.liveUrl.trim().isNotEmpty) {
    return LaunchPlan.url(normalizeUrl(project.liveUrl));
  }

  final folderError = _checkFolder(project);
  if (folderError != null) return LaunchPlan.error(folderError);
  final path = project.path.trim();

  // سيرفر Node / React: نعرف البورت عشان نفتح المتصفح لحاله
  String? localUrl;
  if (project.type == ProjectType.react) {
    final port = detectPort(path);
    if (port != null) localUrl = 'http://localhost:$port';
  }

  // أمر خاص كتبته بنفسك يتقدّم على كل شيء
  final custom = project.runCommand.trim();
  if (custom.isNotEmpty) return LaunchPlan.command(custom, localUrl: localUrl);

  switch (project.type) {
    case ProjectType.flutter:
      // نفضّل Chrome لأنه الأسرع، وإذا ما فيه ويب نشغّل ويندوز
      final String device;
      if (Directory(p.join(path, 'web')).existsSync()) {
        device = ' -d chrome';
      } else if (Directory(p.join(path, 'windows')).existsSync()) {
        device = ' -d windows';
      } else {
        device = '';
      }
      return LaunchPlan.command('flutter run$device');

    case ProjectType.react:
      final script = _npmScript(path);
      if (script == null) {
        return const LaunchPlan.error(
          'ما لقيت أمر dev أو start في package.json. اكتب أمر تشغيل خاص من "تعديل"',
        );
      }
      // لو المكتبات مو محمّلة، نحمّلها أول عشان ما يطلع خطأ قدام الناس
      final hasModules = Directory(p.join(path, 'node_modules')).existsSync();
      final install = hasModules ? '' : 'npm install && ';
      return LaunchPlan.command(
        '${install}npm run $script',
        localUrl: localUrl,
      );

    case ProjectType.website:
      final index = File(p.join(path, 'index.html'));
      return LaunchPlan.open(index.existsSync() ? index.path : path);

    case ProjectType.other:
      return LaunchPlan.open(path);
  }
}

String? _checkFolder(Project project) {
  final path = project.path.trim();
  if (path.isEmpty) return 'حدد مجلد المشروع أول (من "تعديل")';
  if (!Directory(path).existsSync()) return 'ما لقيت المجلد: $path';
  return null;
}

// يدوّر في package.json على أمر dev أو start
String? _npmScript(String path) {
  final file = File(p.join(path, 'package.json'));
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(readTextSafely(file));
    final scripts = json is Map ? json['scripts'] : null;
    if (scripts is! Map) return null;
    if (scripts.containsKey('dev')) return 'dev';
    if (scripts.containsKey('start')) return 'start';
  } on FormatException {
    return null;
  }
  return null;
}

// ▶️ اعرض: يرجّع رسالة خطأ، أو null لو اشتغل
Future<String?> runProject(Project project, {bool local = false}) async {
  final plan = planLaunch(project, local: local);
  if (plan.error != null) return plan.error;
  try {
    if (plan.url != null) {
      final opened = await launchUrl(
        Uri.parse(plan.url!),
        mode: LaunchMode.externalApplication,
      );
      return opened ? null : 'ما قدرت أفتح الرابط: ${plan.url}';
    }
    if (plan.openPath != null) {
      await Process.start('explorer', [plan.openPath!]);
    } else {
      // نافذة تيرمنال جديدة تشغّل الأمر وتبقى مفتوحة عشان تشوف وش يصير
      await Process.start('cmd', [
        '/c',
        'start',
        'Bloom Desk',
        'cmd',
        '/k',
        plan.command!,
      ], workingDirectory: project.path.trim());
      // ننتظر السيرفر في الخلفية، وأول ما يجهز نفتح المتصفح
      if (plan.localUrl != null) openWhenReady(plan.localUrl!);
    }
    return null;
  } on ProcessException catch (e) {
    return 'ما قدرت أشغّله: ${e.message}';
  }
}

// يسأل السيرفر كل ثانية "جاهز؟" لمدة دقيقتين، وأول ما يرد يفتح المتصفح
Future<bool> openWhenReady(
  String url, {
  Duration timeout = const Duration(minutes: 2),
  Future<bool> Function(Uri uri)? open,
}) async {
  final uri = Uri.parse(url);
  final deadline = DateTime.now().add(timeout);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        return await (open ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
      } on Object {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return false;
  } finally {
    client.close(force: true);
  }
}

// يشغّل أمر في نافذة تيرمنال جديدة داخل مجلد المشروع (مثلاً للتصليح)
Future<String?> runInTerminal(Project project, String command) async {
  final folderError = _checkFolder(project);
  if (folderError != null) return folderError;
  try {
    await Process.start('cmd', [
      '/c',
      'start',
      'Bloom Desk',
      'cmd',
      '/k',
      command,
    ], workingDirectory: project.path.trim());
    return null;
  } on ProcessException catch (e) {
    return 'ما قدرت أشغّل الأمر: ${e.message}';
  }
}

// 💻 افتح في VS Code
Future<String?> openInVsCode(Project project) async {
  final folderError = _checkFolder(project);
  if (folderError != null) return folderError;
  try {
    final process = await Process.start('cmd', [
      '/c',
      'code',
      project.path.trim(),
    ]);
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      return 'ما لقيت VS Code. تأكد أنه مثبت وأن أمر code شغّال';
    }
    return null;
  } on ProcessException catch (e) {
    return 'ما قدرت أفتح VS Code: ${e.message}';
  }
}

// 📁 افتح المجلد في File Explorer
Future<String?> openFolder(Project project) async {
  final folderError = _checkFolder(project);
  if (folderError != null) return folderError;
  try {
    await Process.start('explorer', [project.path.trim()]);
    return null;
  } on ProcessException catch (e) {
    return 'ما قدرت أفتح المجلد: ${e.message}';
  }
}
