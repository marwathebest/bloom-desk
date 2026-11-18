import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import 'save_queue.dart';

// المخزن: يحفظ المشاريع في الجهاز، فتلقاها لما تقفل التطبيق وترجع
//
// تقدر تفتح أكثر من نافذة Bloom Desk (مثلاً وحدة لجلسة التركيز)،
// فكل تعديل يقرأ آخر نسخة من الملف أول، ويغيّر بس اللي تغيّر،
// عشان نافذة ما تمسح اللي أضافته النافذة الثانية
class ProjectStore {
  static const _key = 'projects';

  // يقرأ آخر نسخة من الملف (مو من ذاكرة هالنافذة)
  Future<List<Project>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _decode(prefs.getString(_key));
  }

  // يضيف مشروع أو يحدّثه (نفس الـ id)، ويرجّع القائمة كاملة بعد التعديل
  Future<List<Project>> upsert(Project project) => upsertAll([project]);

  Future<List<Project>> upsertAll(List<Project> projects) => _update((list) {
    for (final project in projects) {
      final index = list.indexWhere((p) => p.id == project.id);
      if (index == -1) {
        list.add(project);
      } else {
        list[index] = project;
      }
    }
  });

  Future<List<Project>> remove(String id) =>
      _update((list) => list.removeWhere((p) => p.id == id));

  // طابور واحد للبرنامج كله، عشان أي حفظين ما يتداخلون
  Future<List<Project>> _update(void Function(List<Project> list) change) =>
      SaveQueue.shared.run(() => _updateNow(change));

  Future<List<Project>> _updateNow(
    void Function(List<Project> list) change,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = _decode(prefs.getString(_key));
    change(list);
    await prefs.setString(
      _key,
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
    return list;
  }

  List<Project> _decode(String? raw) {
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((item) => Project.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
