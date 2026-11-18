import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/session_store.dart';
import '../widgets/focus_rose_painter.dart';

// مراحل الجلسة
enum FocusPhase { focusing, bloomed, wilted, onBreak, breakDone }

// صفحة جلسة التركيز: وردة تكبر مع الوقت
class FocusPage extends StatefulWidget {
  const FocusPage({
    super.key,
    required this.task,
    required this.minutes,
    this.project,
    this.store,
    this.clock,
  });

  final String task;
  final int minutes;
  final Project? project;
  final SessionStore? store;
  final DateTime Function()? clock; // للاختبارات: ساعة نتحكم فيها

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  late final SessionStore _store = widget.store ?? SessionStore();
  final _ideaController = TextEditingController();
  final List<String> _ideas = [];

  Timer? _timer;
  FocusPhase _phase = FocusPhase.focusing;
  late final DateTime _startedAt;
  Duration _accumulated = Duration.zero; // الوقت قبل آخر إيقاف مؤقت
  DateTime? _resumedAt; // null = موقوف مؤقتاً
  DateTime? _breakEndsAt;

  DateTime _now() => (widget.clock ?? DateTime.now)();
  Duration get _planned => Duration(minutes: widget.minutes);
  bool get _paused => _resumedAt == null;
  Color get _color => widget.project?.color ?? const Color(0xFFE0607E);
  int get _breakMinutes => widget.minutes >= 45 ? 10 : 5;

  // الوقت اللي ركّزته فعلاً (بدون أوقات الإيقاف)
  Duration get _focused {
    final running = _paused ? Duration.zero : _now().difference(_resumedAt!);
    final total = _accumulated + running;
    return total > _planned ? _planned : total;
  }

  double get _growth => _focused.inMilliseconds / _planned.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _startedAt = _now();
    _resumedAt = _startedAt;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sway.dispose();
    _ideaController.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    if (_phase == FocusPhase.focusing && _focused >= _planned) {
      _complete();
      return;
    }
    if (_phase == FocusPhase.onBreak && !_now().isBefore(_breakEndsAt!)) {
      SystemSound.play(SystemSoundType.alert);
      setState(() => _phase = FocusPhase.breakDone);
      return;
    }
    // حفظ تلقائي كل ٣٠ ثانية تركيز: لو انقفل البرنامج فجأة، وقتك ما يضيع
    if (_phase == FocusPhase.focusing &&
        _focused.inSeconds >= 60 &&
        _focused - _lastAutoSave >= const Duration(seconds: 30)) {
      _lastAutoSave = _focused;
      _save(completed: false);
    }
    setState(() {}); // نحدّث العداد والوردة
  }

  Duration _lastAutoSave = Duration.zero;

  void _togglePause() {
    setState(() {
      if (_paused) {
        _resumedAt = _now();
      } else {
        _accumulated += _now().difference(_resumedAt!);
        _resumedAt = null;
      }
    });
  }

  // 🌹 خلص الوقت
  Future<void> _complete() async {
    setState(() {
      _accumulated = _planned;
      _resumedAt = null;
      _phase = FocusPhase.bloomed;
    });
    SystemSound.play(SystemSoundType.alert);
    await _save(completed: true);
  }

  // 🥀 أنهيت بدري
  Future<void> _endEarly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تنهي الجلسة بدري؟'),
        content: const Text('وردتك بتذبل 🥀 بس الوقت اللي ركّزته ينحسب لك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('كمّل'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('أنهِ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _phase != FocusPhase.focusing) return;

    final focused = _focused;
    setState(() {
      _accumulated = focused;
      _resumedAt = null;
      _phase = FocusPhase.wilted;
    });
    if (focused.inSeconds >= 60) await _save(completed: false);
  }

  Future<void> _save({required bool completed}) {
    return _store.add(
      FocusSession(
        id: _startedAt.microsecondsSinceEpoch.toString(),
        projectId: widget.project?.id,
        projectName: widget.project?.name ?? '',
        colorValue: _color.toARGB32(),
        task: widget.task,
        plannedMinutes: widget.minutes,
        focusedSeconds: _focused.inSeconds,
        completed: completed,
        startedAt: _startedAt,
        ideas: List.of(_ideas),
      ),
    );
  }

  void _startBreak() {
    setState(() {
      _phase = FocusPhase.onBreak;
      _breakEndsAt = _now().add(Duration(minutes: _breakMinutes));
    });
  }

  void _addIdea() {
    final text = _ideaController.text.trim();
    if (text.isEmpty) return;
    setState(() => _ideas.add(text));
    _ideaController.clear();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusing = _phase == FocusPhase.focusing;

    return PopScope(
      canPop: !focusing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endEarly(); // زر الرجوع وسط الجلسة = تأكيد الإنهاء
      },
      child: Scaffold(
        backgroundColor: Color.lerp(Colors.white, _color, 0.06),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.project?.name ?? 'جلسة تركيز'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    widget.task.isEmpty ? 'ركّز 🌱' : widget.task,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: AnimatedBuilder(
                      animation: _sway,
                      builder: (context, _) => CustomPaint(
                        painter: FocusRosePainter(
                          growth: focusing || _phase == FocusPhase.wilted
                              ? _growth
                              : 1,
                          color: _color,
                          sway: sin(_sway.value * 2 * pi) * 0.03,
                          wilted: _phase == FocusPhase.wilted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._phaseContent(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phaseContent(ThemeData theme) {
    final big = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w300,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final focusedMinutes = _focused.inMinutes;

    switch (_phase) {
      case FocusPhase.focusing:
        return [
          Text(_format(_planned - _focused), style: big),
          if (_paused)
            Text('⏸️ موقوف مؤقتاً', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: _togglePause,
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                label: Text(_paused ? 'كمّل' : 'إيقاف مؤقت'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _endEarly,
                child: const Text('أنهِ الجلسة'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _ideasBox(theme),
        ];

      case FocusPhase.bloomed:
        return [
          Text('🌹 تفتحت وردتك!', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'ركّزت ${widget.minutes} دقيقة',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _startBreak,
            icon: const Icon(Icons.local_cafe_outlined),
            label: Text('ابدأ الراحة ($_breakMinutes د)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
          if (_ideas.isNotEmpty) ...[const SizedBox(height: 16), _ideasList()],
        ];

      case FocusPhase.wilted:
        return [
          Text('🥀 ذبلت هالمرة', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            focusedMinutes > 0
                ? 'بس ركّزت $focusedMinutes دقيقة، وهذي تنحسب لك 💪'
                : 'ولا يهمك، المرة الجاية 💪',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
          if (_ideas.isNotEmpty) ...[const SizedBox(height: 16), _ideasList()],
        ];

      case FocusPhase.onBreak:
        final left = _breakEndsAt!.difference(_now());
        return [
          Text('☕ وقت الراحة', style: theme.textTheme.headlineMedium),
          Text(_format(left.isNegative ? Duration.zero : left), style: big),
          const SizedBox(height: 16),
          for (final tip in const [
            '💧 اشرب ماء',
            '🧘 قم تمدد دقيقتين',
            '👀 طالع شي بعيد لمدة ٢٠ ثانية',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(tip, style: theme.textTheme.titleMedium),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _phase = FocusPhase.breakDone),
            child: const Text('تخطّى الراحة'),
          ),
        ];

      case FocusPhase.breakDone:
        return [
          Text('💪 خلصت الراحة', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'again'),
            icon: const Icon(Icons.replay),
            label: const Text('جلسة جديدة'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
        ];
    }
  }

  // 💡 صندوق الأفكار الطارئة
  Widget _ideasBox(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ideaController,
          onSubmitted: (_) => _addIdea(),
          decoration: InputDecoration(
            hintText: '💡 جتك فكرة؟ اكتبها هنا وكمّل شغلك',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              tooltip: 'احفظ الفكرة',
              icon: const Icon(Icons.add),
              onPressed: _addIdea,
            ),
          ),
        ),
        if (_ideas.isNotEmpty) ...[const SizedBox(height: 12), _ideasList()],
      ],
    );
  }

  Widget _ideasList() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [for (final idea in _ideas) Chip(label: Text('💡 $idea'))],
    );
  }
}
