// جلسة تركيز وحدة: على وش اشتغلت، وكم دقيقة، وهل تفتحت الوردة
class FocusSession {
  const FocusSession({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.colorValue,
    required this.task,
    required this.plannedMinutes,
    required this.focusedSeconds,
    required this.completed,
    required this.startedAt,
    this.ideas = const [],
    this.active = false,
    this.updatedAt,
  });

  // الجلسة لسا شغّالة (تنحفظ كل ٣٠ ثانية). لو انقفل البرنامج وهي active،
  // نعرض عليك تكمّلها
  final bool active;
  final DateTime? updatedAt; // آخر حفظ

  FocusSession copyWith({
    int? plannedMinutes,
    int? focusedSeconds,
    bool? completed,
    List<String>? ideas,
    bool? active,
    DateTime? updatedAt,
  }) => FocusSession(
    id: id,
    projectId: projectId,
    projectName: projectName,
    colorValue: colorValue,
    task: task,
    plannedMinutes: plannedMinutes ?? this.plannedMinutes,
    focusedSeconds: focusedSeconds ?? this.focusedSeconds,
    completed: completed ?? this.completed,
    startedAt: startedAt,
    ideas: ideas ?? this.ideas,
    active: active ?? this.active,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  final String id;
  final String? projectId; // null = جلسة بدون مشروع
  final String projectName;
  final int colorValue; // لون الوردة (لون المشروع)
  final String task; // وش كنت تسوي
  final int plannedMinutes;
  final int focusedSeconds; // الوقت الفعلي اللي ركّزته
  final bool completed; // true = 🌹 تفتحت، false = 🥀 ذبلت
  final DateTime startedAt;
  final List<String> ideas; // الأفكار الطارئة اللي كتبتها وسط الجلسة

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'projectName': projectName,
    'color': colorValue,
    'task': task,
    'plannedMinutes': plannedMinutes,
    'focusedSeconds': focusedSeconds,
    'completed': completed,
    'startedAt': startedAt.toIso8601String(),
    'ideas': ideas,
    'active': active,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
    id: json['id'] as String,
    projectId: json['projectId'] as String?,
    projectName: json['projectName'] as String? ?? '',
    colorValue: json['color'] as int? ?? 0xFFE0607E,
    task: json['task'] as String? ?? '',
    plannedMinutes: json['plannedMinutes'] as int? ?? 25,
    focusedSeconds: json['focusedSeconds'] as int? ?? 0,
    completed: json['completed'] as bool? ?? false,
    startedAt: DateTime.parse(json['startedAt'] as String),
    ideas: (json['ideas'] as List?)?.cast<String>() ?? const [],
    active: json['active'] as bool? ?? false,
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
  );

  // جلسة انقطعت: كانت شغّالة، وما انحفظت من فترة (يعني البرنامج انقفل)
  // نتأكد إنها مو شغّالة الحين في نافذة ثانية: آخر حفظ قبل أكثر من ٩٠ ثانية
  bool isUnfinished(DateTime now) =>
      active &&
      !completed &&
      now.difference(updatedAt ?? startedAt) > const Duration(seconds: 90) &&
      now.difference(startedAt) < const Duration(hours: 12);
}

// ملخص يوم واحد
class DaySummary {
  const DaySummary({
    required this.bloomed,
    required this.wilted,
    required this.focusedMinutes,
  });

  final int bloomed; // 🌹
  final int wilted; // 🥀
  final int focusedMinutes;

  bool get isEmpty => bloomed == 0 && wilted == 0;
}

DaySummary summarizeDay(List<FocusSession> sessions, DateTime day) {
  final today = sessions.where(
    (s) =>
        s.startedAt.year == day.year &&
        s.startedAt.month == day.month &&
        s.startedAt.day == day.day,
  );
  return DaySummary(
    bloomed: today.where((s) => s.completed).length,
    wilted: today.where((s) => !s.completed).length,
    focusedMinutes: today.fold(0, (sum, s) => sum + s.focusedSeconds) ~/ 60,
  );
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// جلسات يوم معيّن، بالترتيب من الأقدم للأحدث
List<FocusSession> sessionsOn(List<FocusSession> sessions, DateTime day) =>
    sessions.where((s) => isSameDay(s.startedAt, day)).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

// كم وقت راح لكل مشروع
class ProjectTime {
  const ProjectTime({
    required this.name,
    required this.colorValue,
    required this.seconds,
    required this.sessions,
  });

  final String name;
  final int colorValue;
  final int seconds;
  final int sessions;

  int get minutes => seconds ~/ 60;
}

List<ProjectTime> timePerProject(List<FocusSession> sessions) {
  final byKey = <String, List<FocusSession>>{};
  for (final s in sessions) {
    // الجلسات بدون مشروع تتجمع مع بعض
    final key = s.projectId ?? '';
    byKey.putIfAbsent(key, () => []).add(s);
  }
  return byKey.values.map((list) {
    final latest = list.last;
    return ProjectTime(
      name: latest.projectName.isEmpty ? 'بدون مشروع' : latest.projectName,
      colorValue: latest.colorValue,
      seconds: list.fold(0, (sum, s) => sum + s.focusedSeconds),
      sessions: list.length,
    );
  }).toList()..sort((a, b) => b.seconds.compareTo(a.seconds));
}

// 14:05 → "2:05 م"
String formatClock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'ص' : 'م'}';
}

const _weekdays = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

// "اليوم"، "أمس"، أو "الأحد 16/11"
String dayLabel(DateTime day, DateTime now) {
  if (isSameDay(day, now)) return 'اليوم';
  if (isSameDay(day, now.subtract(const Duration(days: 1)))) return 'أمس';
  return '${_weekdays[day.weekday - 1]} ${day.day}/${day.month}';
}

// ٧٥ → "1 س 15 د"
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes د';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours س' : '$hours س $rest د';
}
