import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/project.dart';
import '../services/focus_prefs.dart';

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
  final _customMinutes = TextEditingController(text: '35');
  final _prefs = FocusPrefs();
  int _minutes = 25;
  bool _custom = false;
  int _goal = FocusPrefs.defaultGoal;

  // المدة المخصصة لازم تكون رقم معقول
  int? get _chosenMinutes {
    if (!_custom) return _minutes;
    final value = int.tryParse(_customMinutes.text.trim());
    if (value == null || value < 1 || value > 180) return null;
    return value;
  }

  @override
  void initState() {
    super.initState();
    _prefs.dailyGoal().then((goal) {
      if (mounted) setState(() => _goal = goal);
    });
  }

  @override
  void dispose() {
    _task.dispose();
    _customMinutes.dispose();
    super.dispose();
  }

  void _changeGoal(int by) {
    setState(() => _goal += by);
    _prefs.setDailyGoal(_goal);
  }

  void _start() {
    final minutes = _chosenMinutes;
    if (minutes == null) return;
    Navigator.pop(
      context,
      FocusSetup(project: _project, task: _task.text.trim(), minutes: minutes),
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
                      selected: !_custom && _minutes == m,
                      onSelected: (_) => setState(() {
                        _custom = false;
                        _minutes = m;
                      }),
                    ),
                  ChoiceChip(
                    label: const Text('مخصص'),
                    selected: _custom,
                    onSelected: (_) => setState(() => _custom = true),
                  ),
                ],
              ),
              // ⏱️ مدة تختارها بنفسك
              if (_custom) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _customMinutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'كم دقيقة؟',
                      suffixText: 'دقيقة',
                      helperText: 'من ١ إلى ١٨٠',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // 🎯 هدف اليوم
              Row(
                children: [
                  Text('🎯 هدف اليوم', style: labelStyle),
                  const Spacer(),
                  IconButton.outlined(
                    tooltip: 'أقل',
                    onPressed: _goal > 1 ? () => _changeGoal(-1) : null,
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text('$_goal جلسات', textAlign: TextAlign.center),
                  ),
                  IconButton.outlined(
                    tooltip: 'أكثر',
                    onPressed: _goal < 20 ? () => _changeGoal(1) : null,
                    icon: const Icon(Icons.add, size: 18),
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
          onPressed: _chosenMinutes == null ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ابدأ'),
        ),
      ],
    );
  }
}
