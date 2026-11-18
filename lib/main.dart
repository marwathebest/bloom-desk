import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'demo/demo_data.dart';
import 'models/focus_session.dart';
import 'pages/focus_page.dart';
import 'pages/garden_page.dart';
import 'pages/projects_page.dart';
import 'services/migrate_old_data.dart';

// نقطة البداية
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // وضع العرض التجريبي (لصور الموقع): بيانات وهمية في الذاكرة بس
  if (isDemoBuild) {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData(demoPrefs(DateTime.now()));
    runApp(BloomDeskApp(demoScreen: args.isEmpty ? 'projects' : args.first));
    return;
  }

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
  const BloomDeskApp({super.key, this.pickFolder, this.demoScreen});

  // للاختبارات فقط: طريقة بديلة لاختيار المجلد
  final Future<String?> Function()? pickFolder;

  // وضع العرض: أي شاشة تفتح أول (projects أو focus أو garden)
  final String? demoScreen;

  Widget _home() {
    switch (demoScreen) {
      case 'focus':
        return FocusPage(
          task: 'ألوان جديدة للورد',
          minutes: 25,
          project: demoProjects.first,
          clock: demoFocusClock(),
        );
      case 'garden':
        final List<FocusSession> sessions = demoSessions(DateTime.now());
        return GardenPage(sessions: sessions);
      default:
        return ProjectsPage(pickFolder: pickFolder);
    }
  }

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
      home: _home(),
    );
  }
}
