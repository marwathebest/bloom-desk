import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/focus_session.dart';
import '../models/project.dart';

// وضع العرض التجريبي: بيانات وهمية لصور الموقع
// يشتغل بس لما يُبنى البرنامج بـ --dart-define=BLOOM_DEMO=true
// وكل شيء في الذاكرة، فما يلمس بيانات أي أحد
const bool isDemoBuild = bool.fromEnvironment('BLOOM_DEMO');

final List<Project> demoProjects = [
  Project(
    id: 'd1',
    name: 'Rose Garden',
    description: 'حديقة ورود تفاعلية تنبت بالضغط وتتمايل مع الهواء',
    path: r'C:\Projects\rose_garden',
    type: ProjectType.flutter,
    color: projectColors[0],
    links: ['https://github.com/you/rose_garden'],
    status: ProjectStatus.done,
  ),
  Project(
    id: 'd2',
    name: 'متجر القهوة',
    description: 'متجر إلكتروني لمحمصة قهوة محلية مع سلة ودفع',
    path: r'C:\Projects\coffee-shop',
    type: ProjectType.react,
    color: projectColors[1],
    links: ['https://github.com/you/coffee-shop'],
    liveUrl: 'https://coffee-shop.example.com',
    status: ProjectStatus.done,
  ),
  Project(
    id: 'd3',
    name: 'لعبة الحروف',
    description: 'لعبة جماعية لتعلّم الحروف العربية بالكاميرا',
    path: r'C:\Projects\letters-game',
    type: ProjectType.website,
    color: projectColors[3],
    links: ['https://github.com/you/letters-game'],
    status: ProjectStatus.inProgress,
  ),
  Project(
    id: 'd4',
    name: 'Weather Mood',
    description: 'تطبيق طقس يغيّر ألوانه حسب الجو',
    path: r'C:\Projects\weather-mood',
    type: ProjectType.flutter,
    color: projectColors[5],
    status: ProjectStatus.inProgress,
  ),
  Project(
    id: 'd5',
    name: 'Portfolio',
    description: 'موقعي الشخصي ومعرض أعمالي',
    path: r'C:\Projects\portfolio',
    type: ProjectType.website,
    color: projectColors[6],
    liveUrl: 'https://portfolio.example.com',
    status: ProjectStatus.done,
  ),
  Project(
    id: 'd6',
    name: 'مساعد المذاكرة',
    description: 'بوت يلخّص الدروس ويسوي أسئلة مراجعة',
    path: r'C:\Projects\study-bot',
    type: ProjectType.react,
    color: projectColors[4],
    status: ProjectStatus.idea,
  ),
];

List<FocusSession> demoSessions(DateTime now) {
  DateTime at(int hour, int minute) =>
      DateTime(now.year, now.month, now.day, hour, minute);
  FocusSession s(
    String id,
    Project p,
    DateTime start,
    int minutes, {
    int? focused,
    String task = '',
    List<String> ideas = const [],
  }) => FocusSession(
    id: id,
    projectId: p.id,
    projectName: p.name,
    colorValue: p.color.toARGB32(),
    task: task,
    plannedMinutes: minutes,
    focusedSeconds: (focused ?? minutes) * 60,
    completed: focused == null,
    startedAt: start,
    ideas: ideas,
  );

  final rose = demoProjects[0];
  final coffee = demoProjects[1];
  final letters = demoProjects[2];
  final weather = demoProjects[3];
  return [
    s(
      's1',
      letters,
      at(9, 0),
      45,
      task: 'كاميرا تتعرف على الحروف',
      ideas: ['وضع لعب ثنائي'],
    ),
    s('s2', rose, at(10, 5), 25, task: 'ألوان جديدة للورد'),
    s('s3', coffee, at(11, 0), 25, focused: 9, task: 'صفحة الدفع'),
    s(
      's4',
      letters,
      at(13, 30),
      60,
      task: 'شاشة النتائج',
      ideas: ['أصوات تشجيع', 'لوحة الأبطال'],
    ),
    s('s5', weather, at(15, 10), 25, task: 'أيقونات الطقس'),
    s('s6', rose, at(16, 0), 15, task: 'زر المشاركة'),
  ];
}

// نفس شكل ملف الحفظ، عشان نعطيه للبرنامج كأنه محفوظ
Map<String, Object> demoPrefs(DateTime now) => {
  'flutter.projects': jsonEncode(demoProjects.map((p) => p.toJson()).toList()),
  'flutter.sessions': jsonEncode(
    demoSessions(now).map((s) => s.toJson()).toList(),
  ),
};

// لصورة جلسة التركيز: ساعة توقف عند ١٤ دقيقة من ٢٥
DateTime Function() demoFocusClock() {
  final start = DateTime.now();
  var first = true;
  return () {
    if (first) {
      first = false;
      return start;
    }
    return start.add(const Duration(minutes: 14, seconds: 12));
  };
}

const demoAccent = Color(0xFFE0607E);
