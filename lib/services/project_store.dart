import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';

// المخزن: يحفظ المشاريع في الجهاز، فتلقاها لما تقفل التطبيق وترجع
class ProjectStore {
  static const _key = 'projects';

  Future<List<Project>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];

    final list = jsonDecode(raw) as List;
    return list
        .map((item) => Project.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(projects.map((p) => p.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
