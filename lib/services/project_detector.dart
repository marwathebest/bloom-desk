import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';

// اللي يطلع من فحص المجلد
class DetectedProject {
  const DetectedProject({
    required this.name,
    required this.description,
    required this.type,
    required this.links,
    this.liveUrl = '',
  });

  final String name;
  final String description;
  final ProjectType type;
  final List<String> links;
  final String liveUrl; // رابط الموقع المنشور لو قدرنا نعرفه
}

// يفحص مجلد المشروع ويعرف بنفسه: الاسم، والوصف، والنوع، ورابط GitHub
DetectedProject detectProject(String folderPath) {
  var name = p.basename(folderPath);
  var description = '';
  var type = ProjectType.other;
  var liveUrl = '';

  final pubspec = File(p.join(folderPath, 'pubspec.yaml'));
  final packageJson = File(p.join(folderPath, 'package.json'));
  final indexHtml = File(p.join(folderPath, 'index.html'));

  if (pubspec.existsSync()) {
    // مشروع Flutter
    type = ProjectType.flutter;
    final text = pubspec.readAsStringSync();
    name = _yamlValue(text, 'name') ?? name;
    description = _yamlValue(text, 'description') ?? '';
    if (description == 'A new Flutter project.') description = '';
  } else if (packageJson.existsSync()) {
    // مشروع React أو Node
    type = ProjectType.react;
    try {
      final json = jsonDecode(packageJson.readAsStringSync());
      if (json is Map) {
        final jsonName = json['name'];
        if (jsonName is String && jsonName.trim().isNotEmpty) name = jsonName;
        final jsonDescription = json['description'];
        if (jsonDescription is String) description = jsonDescription;
        // "homepage" غالباً هو رابط الموقع المنشور
        final homepage = json['homepage'];
        if (homepage is String && homepage.startsWith('http')) {
          liveUrl = homepage.trim();
        }
      }
    } on FormatException {
      // ملف package.json فيه خطأ، نكمل بالاسم من المجلد
    }
  } else if (indexHtml.existsSync()) {
    // موقع
    type = ProjectType.website;
  }

  // ملف CNAME = دومين خاص للموقع (GitHub Pages)
  if (liveUrl.isEmpty) {
    for (final folder in ['', 'public', 'web']) {
      final cname = File(p.join(folderPath, folder, 'CNAME'));
      if (cname.existsSync()) {
        final domain = cname.readAsStringSync().trim().split('\n').first.trim();
        if (domain.isNotEmpty) liveUrl = 'https://$domain';
        break;
      }
    }
  }

  // رابط من ملف README أو من إعدادات Render
  if (liveUrl.isEmpty) {
    liveUrl =
        _readmeLiveUrl(folderPath, [p.basename(folderPath), name]) ??
        _renderUrl(folderPath) ??
        '';
  }

  final remote = _gitRemote(folderPath);
  return DetectedProject(
    name: name,
    description: description.trim(),
    type: type,
    links: remote == null ? const [] : [remote],
    liveUrl: liveUrl,
  );
}

// مواقع الاستضافة بالترتيب: السريعة أول، وRender آخر لأن نسخته المجانية تنام
// وأول فتح ياخذ وقت (يحرج وقت العرض)
const _hostingDomains = [
  'github.io',
  'netlify.app',
  'vercel.app',
  'pages.dev',
  'web.app',
  'firebaseapp.com',
  'onrender.com',
];

// يدوّر في README على رابط استضافة فيه اسم المشروع
String? _readmeLiveUrl(String folderPath, List<String> names) {
  final readme = ['README.md', 'readme.md', 'Readme.md']
      .map((f) => File(p.join(folderPath, f)))
      .where((f) => f.existsSync())
      .firstOrNull;
  if (readme == null) return null;

  final keys = names.map((n) => n.toLowerCase()).where((n) => n.isNotEmpty);
  final urls = RegExp(r'''https?://[^\s)\]>"'`]+''')
      .allMatches(readme.readAsStringSync())
      .map((m) => m.group(0)!.replaceAll(RegExp(r'[.,;:!]+$'), ''))
      .where((url) => keys.any((k) => url.toLowerCase().contains(k)))
      .toList();

  for (final domain in _hostingDomains) {
    for (final url in urls) {
      final host = Uri.tryParse(url)?.host ?? '';
      if (host == domain || host.endsWith('.$domain')) return url;
    }
  }
  return null;
}

// مشروع عنده render.yaml = منشور على Render باسم الخدمة
String? _renderUrl(String folderPath) {
  final file = File(p.join(folderPath, 'render.yaml'));
  if (!file.existsSync()) return null;
  final service = _yamlValue(file.readAsStringSync(), r'\s*-?\s*name');
  return service == null ? null : 'https://$service.onrender.com';
}

// يقرأ سطر مثل  name: my_app  من ملف pubspec.yaml
String? _yamlValue(String text, String key) {
  final match = RegExp('^$key:[ \\t]*(.+)\$', multiLine: true).firstMatch(text);
  if (match == null) return null;
  var value = match.group(1)!.trim();
  final quoted =
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")));
  if (quoted) value = value.substring(1, value.length - 1);
  return value.isEmpty ? null : value;
}

// يقرأ رابط GitHub من إعدادات git في المجلد
String? _gitRemote(String folderPath) {
  final config = File(p.join(folderPath, '.git', 'config'));
  if (!config.existsSync()) return null;
  final match = RegExp(
    r'^\s*url\s*=\s*(.+)$',
    multiLine: true,
  ).firstMatch(config.readAsStringSync());
  if (match == null) return null;
  return gitUrlToWeb(match.group(1)!.trim());
}

// يحوّل  git@github.com:me/app.git  إلى  https://github.com/me/app
String gitUrlToWeb(String url) {
  var result = url;
  final ssh = RegExp(r'^git@([^:]+):(.+)$').firstMatch(result);
  if (ssh != null) result = 'https://${ssh.group(1)}/${ssh.group(2)}';
  if (result.endsWith('.git')) result = result.substring(0, result.length - 4);
  return result;
}
