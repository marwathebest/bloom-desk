import 'package:flutter/material.dart';

import '../models/project.dart';

// اللي تختاره قبل ما تبدأ الجلسة
class FocusSetup {
  const FocusSetup({this.project, required this.task, required this.minutes});

  final Project? project;
  final String task;
  final int minutes;
}

// نافذة "جلسة تركيز": المشروع، ووش بتسوي، والمدة
class FocusSetupDialog extends StatefulWidget {
  const FocusSetupDialog({
    super.key,
    required this.projects,
    this.initialProject,
  });

  final List<Project> projects;
  final Project? initialProject;

  @override
  State<FocusSetupDialog> createState() => _FocusSetupDialogState();
}

class _FocusSetupDialogState extends State<FocusSetupDialog> {
  static const _durations = [15, 25, 45, 60];

  late Project? _project = widget.initialProject;
  final _task = TextEditingController();
  int _minutes = 25;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.pop(
      context,
      FocusSetup(project: _project, task: _task.text.trim(), minutes: _minutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;

    return AlertDialog(
      title: const Text('جلسة تركيز 🌱'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _project?.id,
                decoration: const InputDecoration(
                  labelText: 'المشروع',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('بدون مشروع'),
                  ),
                  for (final p in widget.projects)
                    DropdownMenuItem(
                      value: p.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 12, color: p.color),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _project = widget.projects
                      .where((p) => p.id == id)
                      .firstOrNull;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _task,
                autofocus: true,
                onSubmitted: (_) => _start(),
                decoration: const InputDecoration(
                  labelText: 'وش بتسوي؟',
                  hintText: 'مثلاً: أصلّح صفحة الدخول',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('المدة', style: labelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in _durations)
                    ChoiceChip(
                      label: Text('$m د'),
                      selected: _minutes == m,
                      onSelected: (_) => setState(() => _minutes = m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ابدأ'),
        ),
      ],
    );
  }
}
