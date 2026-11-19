import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/focus_session.dart';
import '../widgets/focus_rose_painter.dart';

// 🌷 حديقة اليوم: وردة لكل جلسة، ووين راح وقتك، وأفكارك الطارئة
class GardenPage extends StatefulWidget {
  const GardenPage({super.key, required this.sessions, this.clock});

  final List<FocusSession> sessions;
  final DateTime Function()? clock; // للاختبارات

  @override
  State<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends State<GardenPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(minutes: 10),
  )..repeat();

  late DateTime _day = _now();

  DateTime _now() => (widget.clock ?? DateTime.now)();
  bool get _isToday => isSameDay(_day, _now());

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  void _moveDay(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = sessionsOn(widget.sessions, _day);
    final summary = summarizeDay(sessions, _day);
    final ideas = [
      for (final s in sessions)
        for (final idea in s.ideas) (idea: idea, session: s),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('🌷 حديقتي'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              // التنقل بين الأيام
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'اليوم اللي قبل',
                    onPressed: () => _moveDay(-1),
                    icon: const Icon(Icons.arrow_back_ios_new),
                  ),
                  SizedBox(
                    width: 180,
                    child: Text(
                      dayLabel(_day, _now()),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'اليوم اللي بعد',
                    onPressed: _isToday ? null : () => _moveDay(1),
                    icon: const Icon(Icons.arrow_forward_ios),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (sessions.isEmpty)
                _empty(theme)
              else ...[
                Text(
                  '🌹 ${summary.bloomed}   🌱 ${summary.wilted}   ·   '
                  '${formatMinutes(summary.focusedMinutes)} تركيز',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _gardenBed(sessions),
                const SizedBox(height: 28),
                _timeBreakdown(theme, sessions),
                if (ideas.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _ideasSection(theme, ideas),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('ما فيه جلسات هذا اليوم', style: theme.textTheme.titleMedium),
          if (_isToday)
            Text(
              'ابدأ جلسة تركيز وتنبت أول وردة',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  // أحواض الورد: وردة لكل جلسة، وطولها حسب مدة التركيز
  Widget _gardenBed(List<FocusSession> sessions) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF4F7), Color(0xFFE6F4E1)],
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 4,
        runSpacing: 12,
        children: [for (final s in sessions) _roseTile(s)],
      ),
    );
  }

  Widget _roseTile(FocusSession s) {
    final minutes = s.focusedSeconds / 60;
    final height = 110 + min(minutes, 60) * 1.2; // جلسة أطول = وردة أطول
    final growth = s.completed
        ? 1.0
        : (s.focusedSeconds / (s.plannedMinutes * 60)).clamp(0.3, 1.0);
    final title = s.task.isEmpty ? 'جلسة تركيز' : s.task;

    return Tooltip(
      message: '$title · ${formatMinutes(minutes.round())}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(s),
        child: SizedBox(
          width: 100,
          child: Column(
            children: [
              SizedBox(
                width: 100,
                height: height,
                child: AnimatedBuilder(
                  animation: _sway,
                  builder: (context, _) => CustomPaint(
                    painter: FocusRosePainter(
                      growth: growth,
                      color: Color(s.colorValue),
                      // كل وردة لها توقيت خاص فما يتمايلون مع بعض
                      time:
                          _sway.value * 600 +
                          s.startedAt.minute * 1.7 +
                          s.startedAt.hour,
                    ),
                  ),
                ),
              ),
              Text(
                formatClock(s.startedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(FocusSession s) {
    final end = s.startedAt.add(Duration(seconds: s.focusedSeconds));
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(
            '${s.completed ? '🌹' : '🌱'} '
            '${s.task.isEmpty ? 'جلسة تركيز' : s.task}',
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(
                  Icons.circle,
                  s.projectName.isEmpty ? 'بدون مشروع' : s.projectName,
                  color: Color(s.colorValue),
                ),
                _detailRow(
                  Icons.schedule,
                  '${formatClock(s.startedAt)} ← ${formatClock(end)}',
                ),
                _detailRow(
                  Icons.timer_outlined,
                  'ركّزت ${formatMinutes(s.focusedSeconds ~/ 60)} '
                  'من ${formatMinutes(s.plannedMinutes)}',
                ),
                if (s.ideas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('💡 الأفكار', style: theme.textTheme.titleSmall),
                  for (final idea in s.ideas)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $idea'),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تمام'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // 📊 وين راح وقتك: شريط ملوّن + قائمة
  Widget _timeBreakdown(ThemeData theme, List<FocusSession> sessions) {
    final projects = timePerProject(sessions);
    final total = projects.fold(0, (sum, p) => sum + p.seconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('📊 وين راح وقتك', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  for (final p in projects)
                    if (p.seconds > 0)
                      Expanded(
                        flex: p.seconds,
                        child: Container(color: Color(p.colorValue)),
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (final p in projects)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: Color(p.colorValue)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.name)),
                Text(
                  '${formatMinutes(p.minutes)}  ·  ${p.sessions} '
                  '${p.sessions == 1 ? 'جلسة' : 'جلسات'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 💡 كل الأفكار الطارئة في مكان واحد
  Widget _ideasSection(
    ThemeData theme,
    List<({String idea, FocusSession session})> ideas,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '💡 أفكارك الطارئة (${ideas.length})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: ideas.map((i) => '• ${i.idea}').join('\n'),
                  ),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('انسخت الأفكار ✓')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('انسخها'),
            ),
          ],
        ),
        for (final item in ideas)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              leading: Icon(
                Icons.lightbulb_outline,
                color: Color(item.session.colorValue),
              ),
              title: Text(item.idea),
              subtitle: Text(
                '${item.session.projectName.isEmpty ? 'بدون مشروع' : item.session.projectName}'
                '  ·  ${formatClock(item.session.startedAt)}',
              ),
            ),
          ),
      ],
    );
  }
}
