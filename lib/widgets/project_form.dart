import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/project_detector.dart';

// نافذة إضافة أو تعديل مشروع
class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key, this.project});

  // لو فيه مشروع = تعديل. لو null = مشروع جديد
  final Project? project;

  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _path;
  late final TextEditingController _links;
  late final TextEditingController _runCommand;
  late final TextEditingController _liveUrl;
  String? _liveUrlHint; // رسالة لو ما لقينا رابط
  late ProjectType _type;
  late Color _color;
  late ProjectStatus _status;

  bool get _isEdit => widget.project != null;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _path = TextEditingController(text: p?.path ?? '');
    _links = TextEditingController(text: p?.links.join('\n') ?? '');
    _runCommand = TextEditingController(text: p?.runCommand ?? '');
    _liveUrl = TextEditingController(text: p?.liveUrl ?? '');
    _type = p?.type ?? ProjectType.flutter;
    _color = p?.color ?? projectColors.first;
    _status = p?.status ?? ProjectStatus.inProgress;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _path.dispose();
    _links.dispose();
    _runCommand.dispose();
    _liveUrl.dispose();
    super.dispose();
  }

  // تختار المجلد، ويتعبّى الفاضي من الخانات تلقائياً
  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'اختر المجلد');
    if (path == null) return;
    final detected = detectProject(path);
    setState(() {
      _path.text = path;
      _type = detected.type;
      if (_name.text.trim().isEmpty) _name.text = detected.name;
      if (_description.text.trim().isEmpty) {
        _description.text = detected.description;
      }
      if (_links.text.trim().isEmpty) _links.text = detected.links.join('\n');
      if (_liveUrl.text.trim().isEmpty) _liveUrl.text = detected.liveUrl;
    });
  }

  // يدوّر على رابط الموقع المنشور في مجلد المشروع
  void _detectLiveUrl() {
    final path = _path.text.trim();
    final found = path.isEmpty || !Directory(path).existsSync()
        ? ''
        : detectProject(path).liveUrl;
    if (found.isNotEmpty) {
      setState(() => _liveUrl.text = found);
    } else {
      setState(() => _liveUrlHint = 'ما لقيت رابط في المجلد، اكتبه بنفسك');
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final links = _links.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    Navigator.pop(
      context,
      Project(
        id:
            widget.project?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        description: _description.text.trim(),
        path: _path.text.trim(),
        type: _type,
        color: _color,
        status: _status,
        links: links,
        runCommand: _runCommand.text.trim(),
        liveUrl: _liveUrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;

    return AlertDialog(
      title: Text(_isEdit ? 'تعديل المشروع' : 'مشروع جديد 🌱'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم المشروع',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'اكتب اسم المشروع'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'وصف قصير',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _path,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'مسار المجلد',
                    hintText: r'C:\Users\...\my_project',
                    hintTextDirection: TextDirection.ltr,
                    border: const OutlineInputBorder(),
                    suffixIcon: kIsWeb
                        ? null
                        : IconButton(
                            tooltip: 'اختر مجلد',
                            icon: const Icon(Icons.folder_open),
                            onPressed: _pickFolder,
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // الحالة
                Text('الحالة', style: labelStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in ProjectStatus.values)
                      ChoiceChip(
                        label: Text('${s.emoji} ${s.label}'),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // نوع المشروع
                Text('نوع المشروع', style: labelStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ProjectType.values.map((type) {
                    return ChoiceChip(
                      avatar: Icon(type.icon, size: 18),
                      label: Text(type.label),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // اللون
                Text('اللون', style: labelStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: projectColors.map((color) {
                    final selected = _color == color;
                    return InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: Colors.black87, width: 3)
                              : null,
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _links,
                  maxLines: 3,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'روابط (رابط في كل سطر)',
                    hintText: 'https://github.com/...',
                    hintTextDirection: TextDirection.ltr,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _liveUrl,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'رابط الموقع المنشور (اختياري)',
                    hintText: 'https://my-site.com',
                    hintTextDirection: TextDirection.ltr,
                    helperText:
                        _liveUrlHint ??
                        'لو موجود، زر "اعرض" يفتح الموقع الحقيقي',
                    prefixIcon: const Icon(Icons.public),
                    border: const OutlineInputBorder(),
                    suffixIcon: kIsWeb
                        ? null
                        : IconButton(
                            tooltip: 'اكتشف الرابط من المجلد',
                            icon: const Icon(Icons.auto_awesome),
                            onPressed: _detectLiveUrl,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _runCommand,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'أمر تشغيل خاص (اختياري)',
                    hintText: 'flutter run -d windows',
                    hintTextDirection: TextDirection.ltr,
                    helperText: 'اتركه فاضي ويختار البرنامج حسب نوع المشروع',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}
