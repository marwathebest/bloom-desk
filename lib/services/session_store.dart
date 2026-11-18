import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/focus_session.dart';
import 'save_queue.dart';

// يحفظ جلسات التركيز، عشان نعرف وين راح يومك
class SessionStore {
  static const _key = 'sessions';

  // يقرأ آخر نسخة من الملف، عشان ما نمسح جلسات نافذة ثانية
  Future<List<FocusSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((item) => FocusSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(FocusSession session) => upsert(session);

  // يحفظ الجلسة، ولو موجودة (نفس الـ id) يحدّثها بدل ما يكررها
  // نستخدمه كل ٣٠ ثانية وسط الجلسة، عشان لو انقفل البرنامج ما يضيع وقتك
  Future<void> upsert(FocusSession session) => SaveQueue.shared.run(() async {
    final sessions = await load();
    final index = sessions.indexWhere((s) => s.id == session.id);
    if (index == -1) {
      sessions.add(session);
    } else {
      sessions[index] = session;
    }
    await _write(sessions);
  });

  Future<void> remove(String id) => SaveQueue.shared.run(() async {
    final sessions = await load();
    sessions.removeWhere((s) => s.id == id);
    await _write(sessions);
  });

  Future<void> _write(List<FocusSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }
}
