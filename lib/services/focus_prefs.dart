import 'package:shared_preferences/shared_preferences.dart';

import 'save_queue.dart';

// إعدادات التركيز: هدف اليوم، وبدء الجلسة الجاية لحالها، والصوت
class FocusPrefs {
  static const defaultGoal = 6;

  Future<int> dailyGoal() async =>
      (await _prefs()).getInt('dailyGoal') ?? defaultGoal;
  Future<void> setDailyGoal(int goal) =>
      _set((p) => p.setInt('dailyGoal', goal));

  Future<bool> autoNext() async =>
      (await _prefs()).getBool('autoNext') ?? false;
  Future<void> setAutoNext(bool on) => _set((p) => p.setBool('autoNext', on));

  Future<String> sound() async => (await _prefs()).getString('sound') ?? 'off';
  Future<void> setSound(String id) => _set((p) => p.setString('sound', id));

  Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  Future<void> _set(Future<bool> Function(SharedPreferences p) write) =>
      SaveQueue.shared.run(() async => write(await _prefs()));
}
