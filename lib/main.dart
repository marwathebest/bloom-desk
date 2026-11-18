import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'pages/projects_page.dart';
import 'services/migrate_old_data.dart';

// نقطة البداية
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ننقل بيانات النسخ القديمة (لو موجودة) قبل ما يفتح البرنامج
  if (!kIsWeb && Platform.isWindows) {
    try {
      await migrateOldData(
        appData: Platform.environment['APPDATA'] ?? '',
        newSupportDir: (await getApplicationSupportDirectory()).path,
      );
    } on Object {
      // لو صار خطأ، نكمل عادي بدون ما نوقف البرنامج
    }
  }

  runApp(const BloomDeskApp());
}

// الإطار الخارجي: الاسم، والألوان، والاتجاه، وأول صفحة
class BloomDeskApp extends StatelessWidget {
  const BloomDeskApp({super.key, this.pickFolder});

  // للاختبارات فقط: طريقة بديلة لاختيار المجلد
  final Future<String?> Function()? pickFolder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bloom Desk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE0607E)),
        scaffoldBackgroundColor: const Color(0xFFFFF8F9),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: ProjectsPage(pickFolder: pickFolder),
    );
  }
}
