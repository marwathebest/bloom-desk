import 'package:flutter/material.dart';

// أنواع المشاريع: كل نوع له اسم وأيقونة
// (في نسخة ويندوز بنستخدم النوع عشان نعرف أمر التشغيل)
enum ProjectType {
  flutter('Flutter', Icons.flutter_dash),
  react('React / Node', Icons.javascript),
  website('موقع', Icons.language),
  other('أخرى', Icons.folder_outlined);

  const ProjectType(this.label, this.icon);

  final String label;
  final IconData icon;
}

// حالة المشروع: وين وصلت فيه
enum ProjectStatus {
  idea('فكرة', '💡'),
  inProgress('قيد العمل', '🛠️'),
  done('مكتمل', '✅');

  const ProjectStatus(this.label, this.emoji);

  final String label;
  final String emoji;
}

// ألوان المشاريع اللي تختار منها
const List<Color> projectColors = [
  Color(0xFFE0607E), // وردي
  Color(0xFFE5704A), // مرجاني
  Color(0xFFC98A1A), // عسلي
  Color(0xFF4E9A6B), // أخضر
  Color(0xFF2A8C8C), // تركوازي
  Color(0xFF4A7FD0), // أزرق
  Color(0xFF8A63C9), // بنفسجي
  Color(0xFF5F6B7A), // رمادي
];

// شكل "المشروع الواحد"
class Project {
  final String id;
  String name;
  String description;
  String path; // مسار المجلد في جهازك
  ProjectType type;
  Color color;
  List<String> links;

  Project({
    required this.id,
    required this.name,
    this.description = '',
    this.path = '',
    this.type = ProjectType.other,
    required this.color,
    List<String>? links,
    this.runCommand = '',
    this.liveUrl = '',
    this.status = ProjectStatus.inProgress,
    this.notes = '',
  }) : links = links ?? [];

  // ملاحظات حرة (للأفكار خصوصاً: وش الفكرة، وش تحتاج، خطوات أولى...)
  String notes;

  // فكرة بس، لسا ما لها مجلد ولا موقع
  bool get isNoteOnly => path.trim().isEmpty && liveUrl.trim().isEmpty;

  // الحالة: فكرة، أو قيد العمل، أو مكتمل
  ProjectStatus status;

  // رابط الموقع المنشور (اختياري). لو موجود، "اعرض" يفتحه بدل التشغيل المحلي
  String liveUrl;

  // أمر تشغيل خاص (اختياري). لو فاضي، البرنامج يختار حسب النوع
  String runCommand;

  // نحوّل المشروع لنص (JSON) عشان نقدر نحفظه
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'path': path,
    'type': type.name,
    'color': color.toARGB32(),
    'links': links,
    'runCommand': runCommand,
    'liveUrl': liveUrl,
    'status': status.name,
    'notes': notes,
  };

  // ونرجّعه من النص لمشروع لما نفتح التطبيق
  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    path: json['path'] as String? ?? '',
    type: ProjectType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => ProjectType.other,
    ),
    color: Color(json['color'] as int),
    links: (json['links'] as List?)?.cast<String>() ?? [],
    runCommand: json['runCommand'] as String? ?? '',
    liveUrl: json['liveUrl'] as String? ?? '',
    status: ProjectStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => ProjectStatus.inProgress,
    ),
    notes: json['notes'] as String? ?? '',
  );
}
