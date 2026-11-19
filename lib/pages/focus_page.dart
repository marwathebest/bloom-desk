import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/focus_environment.dart';
import '../services/focus_prefs.dart';
import '../services/project_store.dart';
import '../services/session_store.dart';
import '../widgets/focus_rose_painter.dart';

// مراحل الجلسة
// budded = أنهيت بدري: الوردة توقف على حجمها (برعم) بدل ما تذبل
enum FocusPhase { focusing, bloomed, budded, onBreak, breakDone }

// صفحة جلسة التركيز: وردة تكبر مع الوقت
class FocusPage extends StatefulWidget {
  const FocusPage({
    super.key,
    required this.task,
    required this.minutes,
    this.project,
    this.store,
    this.projectStore,
    this.clock,
    this.resume,
    this.environment,
  });

  final String task;
  final int minutes;
  final Project? project;
  final SessionStore? store;
  final ProjectStore? projectStore;
  final DateTime Function()? clock; // للاختبارات: ساعة نتحكم فيها
  final FocusSession? resume; // جلسة انقطعت ونكمّلها
  final FocusEnvironment? environment; // النافذة والتنبيهات والأصوات

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage>
    with SingleTickerProviderStateMixin {
  // ساعة الحركة: منها تتمايل الوردة وتتنفس وتطلع اللمعات
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(minutes: 10),
  )..repeat();
  late final SessionStore _store = widget.store ?? SessionStore();
  late final ProjectStore _projectStore = widget.projectStore ?? ProjectStore();
  late final FocusEnvironment _env =
      widget.environment ?? FocusEnvironment.current;
  final _prefs = FocusPrefs();
  final _ideaController = TextEditingController();
  late final List<String> _ideas = List.of(widget.resume?.ideas ?? const []);

  Timer? _timer;
  FocusPhase _phase = FocusPhase.focusing;
  late final String _id;
  late final DateTime _startedAt;
  late int _plannedMinutes; // يزيد لو ضغطت "+٥ دقائق"
  Duration _accumulated = Duration.zero; // الوقت قبل آخر إيقاف مؤقت
  DateTime? _resumedAt; // null = موقوف مؤقتاً
  DateTime? _breakEndsAt;
  int _breakMinutes = 5;
  DateTime? _lastSaveAt;

  // اليوم
  int _doneBefore = 0; // جلسات اليوم المكتملة قبل هذي
  bool _completedThis = false;
  int _goal = FocusPrefs.defaultGoal;
  bool _autoNext = false;
  String _sound = 'off';

  // النافذة الصغيرة
  bool _mini = false;
  Rect? _fullBounds;

  String? _ideasMessage; // بعد ما ترسل الأفكار للملاحظات أو اللوحة

  DateTime _now() => (widget.clock ?? DateTime.now)();
  Duration get _planned => Duration(minutes: _plannedMinutes);
  bool get _paused => _resumedAt == null;
  Color get _color => widget.project?.color ?? const Color(0xFFE0607E);
  int get _doneToday => _doneBefore + (_completedThis ? 1 : 0);
  bool get _longBreak => _breakMinutes == 15;
  String get _title => widget.task.isEmpty ? 'ركّز 🌱' : widget.task;

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
    final resume = widget.resume;
    _startedAt = resume?.startedAt ?? _now();
    _id = resume?.id ?? _startedAt.microsecondsSinceEpoch.toString();
    _plannedMinutes = resume?.plannedMinutes ?? widget.minutes;
    _accumulated = Duration(seconds: resume?.focusedSeconds ?? 0);
    _resumedAt = _now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadToday();
  }

  Future<void> _loadToday() async {
    final sessions = await _store.load();
    final goal = await _prefs.dailyGoal();
    final autoNext = await _prefs.autoNext();
    final sound = await _prefs.sound();
    if (!mounted) return;
    final today = _now();
    setState(() {
      _doneBefore = sessions
          .where(
            (s) => s.completed && s.id != _id && isSameDay(s.startedAt, today),
          )
          .length;
      _goal = goal;
      _autoNext = autoNext;
      _sound = sound;
    });
    _applySound();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    _ideaController.dispose();
    _env.stopSound();
    if (_mini) {
      _env.window.setAlwaysOnTop(false);
      if (_fullBounds != null) _env.window.setBounds(_fullBounds!);
    }
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    if (_phase == FocusPhase.focusing && _focused >= _planned) {
      _complete();
      return;
    }
    if (_phase == FocusPhase.onBreak && !_now().isBefore(_breakEndsAt!)) {
      _breakOver();
      return;
    }
    // حفظ تلقائي كل ٣٠ ثانية (حتى وأنت موقف مؤقتاً): لو انقفل البرنامج
    // فجأة، وقتك ما يضيع، والبرنامج يعرض عليك تكمّل الجلسة
    if (_phase == FocusPhase.focusing &&
        _focused.inSeconds >= 60 &&
        (_lastSaveAt == null ||
            _now().difference(_lastSaveAt!) >= const Duration(seconds: 30))) {
      _save(completed: false, active: true);
    }
    setState(() {}); // نحدّث العداد
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        _resumedAt = _now();
      } else {
        _accumulated += _now().difference(_resumedAt!);
        _resumedAt = null;
      }
    });
    _applySound();
  }

  void _addFiveMinutes() => setState(() => _plannedMinutes += 5);

  // 🌹 خلص الوقت
  Future<void> _complete() async {
    setState(() {
      _accumulated = _planned;
      _resumedAt = null;
      _phase = FocusPhase.bloomed;
      _completedThis = true;
      // كل ٤ جلسات اليوم: راحة طويلة
      _breakMinutes = _doneToday % 4 == 0
          ? 15
          : _plannedMinutes >= 45
          ? 10
          : 5;
    });
    _env.stopSound();
    _alert(
      '🌹 تفتحت وردتك!',
      'ركّزت $_plannedMinutes دقيقة على «$_title». وقت الراحة ☕',
    );
    await _save(completed: true, active: false);
  }

  // 🌱 أنهيت بدري: الوردة توقف على حجمها، والوقت ينحسب
  Future<void> _finishEarly() async {
    if (_phase != FocusPhase.focusing) return;
    final focused = _focused;
    setState(() {
      _accumulated = focused;
      _resumedAt = null;
      _phase = FocusPhase.budded;
    });
    _env.stopSound();
    if (focused.inSeconds >= 60 || _lastSaveAt != null) {
      await _save(completed: false, active: false);
    }
  }

  Future<void> _confirmEnd() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تنهي الجلسة؟'),
        content: const Text(
          'وردتك بتوقف على حجمها الحين 🌱 وكل دقيقة ركّزتها تنحسب لك.',
        ),
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
    if (confirmed == true && mounted) await _finishEarly();
  }

  // زر الرجوع وسط الجلسة: ثلاث خيارات بدل الإنهاء مباشرة
  Future<void> _onBack() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('جلستك لسا شغّالة 🌱'),
        content: const Text('وش تبي تسوي؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('كمّل الجلسة'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'pause'),
            child: const Text('إيقاف مؤقت'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'end'),
            child: const Text('أنهِ الجلسة'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'pause' && !_paused) _togglePause();
    if (choice == 'end') await _finishEarly();
  }

  Future<void> _save({required bool completed, required bool active}) {
    final now = _now();
    _lastSaveAt = now;
    return _store.upsert(
      FocusSession(
        id: _id,
        projectId: widget.project?.id,
        projectName: widget.project?.name ?? '',
        colorValue: _color.toARGB32(),
        task: widget.task,
        plannedMinutes: _plannedMinutes,
        focusedSeconds: _focused.inSeconds,
        completed: completed,
        startedAt: _startedAt,
        ideas: List.of(_ideas),
        active: active,
        updatedAt: now,
      ),
    );
  }

  // 🔔 تنبيه: صوت + إشعار ويندوز + وميض في شريط المهام
  void _alert(String title, String body) {
    SystemSound.play(SystemSoundType.alert);
    _env.notify(title, body);
    _env.window.flash();
  }

  void _startBreak() {
    setState(() {
      _phase = FocusPhase.onBreak;
      _breakEndsAt = _now().add(Duration(minutes: _breakMinutes));
    });
  }

  void _breakOver({bool skipped = false}) {
    setState(() => _phase = FocusPhase.breakDone);
    if (!skipped) _alert('💪 خلصت الراحة', 'جاهز للجلسة الجاية؟');
    if (_autoNext) Navigator.pop(context, 'again-auto');
  }

  Future<void> _setAutoNext(bool on) async {
    setState(() => _autoNext = on);
    await _prefs.setAutoNext(on);
  }

  Future<void> _setSound(String id) async {
    setState(() => _sound = id);
    _applySound();
    await _prefs.setSound(id);
  }

  // الصوت يشتغل بس وأنت مركّز، ويوقف مع الإيقاف المؤقت
  void _applySound() {
    final file = focusSounds
        .firstWhere((s) => s.id == _sound, orElse: () => focusSounds.first)
        .file;
    if (_phase == FocusPhase.focusing && !_paused && file != null) {
      _env.playSound(file);
    } else {
      _env.stopSound();
    }
  }

  // 🪟 نافذة صغيرة فوق كل البرامج
  Future<void> _enterMini() async {
    final bounds = await _env.window.bounds();
    if (!mounted) return;
    setState(() => _mini = true);
    if (bounds == null) return;
    _fullBounds = bounds;
    final dpr = View.of(context).devicePixelRatio;
    final w = 320 * dpr, h = 470 * dpr;
    await _env.window.setBounds(
      Rect.fromLTWH(bounds.right - w, bounds.top, w, h),
    );
    await _env.window.setAlwaysOnTop(true);
  }

  Future<void> _exitMini() async {
    await _env.window.setAlwaysOnTop(false);
    if (_fullBounds != null) await _env.window.setBounds(_fullBounds!);
    if (mounted) setState(() => _mini = false);
  }

  void _addIdea() {
    final text = _ideaController.text.trim();
    if (text.isEmpty) return;
    setState(() => _ideas.add(text));
    _ideaController.clear();
  }

  // 💡 الأفكار → ملاحظات المشروع
  Future<void> _sendIdeasToNotes() async {
    final project = widget.project;
    if (project == null) return;
    final all = await _projectStore.load();
    final fresh = all.where((p) => p.id == project.id).firstOrNull;
    if (fresh == null) {
      setState(() => _ideasMessage = 'ما لقيت المشروع، يمكن انحذف');
      return;
    }
    fresh.notes = [
      if (fresh.notes.trim().isNotEmpty) fresh.notes.trim(),
      for (final idea in _ideas) '• $idea',
    ].join('\n');
    await _projectStore.upsert(fresh);
    if (!mounted) return;
    setState(() => _ideasMessage = '✓ انضافت لملاحظات «${project.name}»');
  }

  // 💡 الأفكار → بطاقات في عمود الأفكار
  Future<void> _sendIdeasToBoard() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final from = widget.project?.name ?? '';
    await _projectStore.upsertAll([
      for (var i = 0; i < _ideas.length; i++)
        Project(
          id: '${stamp}_$i',
          name: _ideas[i],
          notes: from.isEmpty
              ? 'من جلسة «$_title»'
              : 'من جلسة «$_title» على $from',
          type: ProjectType.other,
          status: ProjectStatus.idea,
          color: _color,
        ),
    ]);
    if (!mounted) return;
    setState(
      () => _ideasMessage = '✓ صارت ${_ideas.length} أفكار في عمود 💡 فكرة',
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _rose(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) => CustomPaint(
          painter: FocusRosePainter(
            growth: _phase == FocusPhase.focusing || _phase == FocusPhase.budded
                ? _growth
                : 1,
            color: _color,
            time: _motion.value * 600,
            sparkles: _phase == FocusPhase.focusing && !_paused,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusing = _phase == FocusPhase.focusing;
    return PopScope(
      canPop: !focusing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Color.lerp(Colors.white, _color, 0.06),
        appBar: _mini
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                title: Text(widget.project?.name ?? 'جلسة تركيز'),
                actions: [
                  if (focusing || _phase == FocusPhase.onBreak)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: IconButton(
                        tooltip: 'نافذة صغيرة فوق البرامج',
                        onPressed: _enterMini,
                        icon: const Icon(Icons.picture_in_picture_alt_outlined),
                      ),
                    ),
                ],
              ),
        body: _mini ? _miniBody(context) : _fullBody(context),
      ),
    );
  }

  Widget _fullBody(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              _goalLine(theme),
              const SizedBox(height: 12),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              _rose(300),
              const SizedBox(height: 8),
              ..._phaseContent(theme),
            ],
          ),
        ),
      ),
    );
  }

  // 🎯 هدف اليوم: نقطة لكل جلسة
  Widget _goalLine(ThemeData theme) {
    final done = _doneToday;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'هدف اليوم',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        for (var i = 0; i < _goal; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              i < done ? Icons.circle : Icons.circle_outlined,
              size: 12,
              color: _color,
            ),
          ),
        const SizedBox(width: 10),
        Text(
          '$done من $_goal',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (done >= _goal) const Text('  🎉'),
      ],
    );
  }

  List<Widget> _phaseContent(ThemeData theme) {
    final big = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w300,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    switch (_phase) {
      case FocusPhase.focusing:
        return [
          Text(_format(_planned - _focused), style: big),
          if (_paused)
            Text('⏸️ موقوف مؤقتاً', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _togglePause,
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                label: Text(_paused ? 'كمّل' : 'إيقاف مؤقت'),
              ),
              OutlinedButton.icon(
                onPressed: _addFiveMinutes,
                icon: const Icon(Icons.more_time, size: 18),
                label: const Text('زِد ٥ دقائق'),
              ),
              TextButton(
                onPressed: _confirmEnd,
                child: const Text('أنهِ الجلسة'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 🎵 أصوات هادئة
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in focusSounds)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _sound == s.id,
                  onSelected: (_) => _setSound(s.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _ideasBox(),
        ];

      case FocusPhase.bloomed:
        return [
          Text('🌹 تفتحت وردتك!', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'ركّزت $_plannedMinutes دقيقة',
            style: theme.textTheme.bodyLarge,
          ),
          if (_longBreak)
            Text(
              '🎉 $_doneToday جلسات اليوم! تستاهل راحة طويلة',
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
          _ideasAfter(theme),
        ];

      case FocusPhase.budded:
        final minutes = _focused.inMinutes;
        return [
          Text('🌱 وردتك صارت برعم', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            minutes > 0
                ? 'ركّزت $minutes دقيقة، وهذي تنحسب لك 💪'
                : 'ولا يهمك، المرة الجاية 💪',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
          _ideasAfter(theme),
        ];

      case FocusPhase.onBreak:
        final left = _breakEndsAt!.difference(_now());
        return [
          Text(
            _longBreak ? '☕ راحة طويلة' : '☕ وقت الراحة',
            style: theme.textTheme.headlineMedium,
          ),
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
          const SizedBox(height: 12),
          _autoNextSwitch(theme),
          TextButton(
            onPressed: () => _breakOver(skipped: true),
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

  Widget _autoNextSwitch(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: _autoNext, onChanged: _setAutoNext),
        const SizedBox(width: 8),
        Text('ابدأ الجلسة الجاية لحالها', style: theme.textTheme.bodyMedium),
      ],
    );
  }

  // 💡 صندوق الأفكار الطارئة
  Widget _ideasBox() {
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

  // بعد الجلسة: وين تروح الأفكار؟
  Widget _ideasAfter(ThemeData theme) {
    if (_ideas.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            '💡 أفكارك الطارئة (${_ideas.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _ideasList(),
          const SizedBox(height: 12),
          if (_ideasMessage != null)
            Text(
              _ideasMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF3A9A5B),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.project != null)
                  FilledButton.tonalIcon(
                    onPressed: _sendIdeasToNotes,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: Text('أضفها لملاحظات «${widget.project!.name}»'),
                  ),
                OutlinedButton.icon(
                  onPressed: _sendIdeasToBoard,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('حوّلها لأفكار في اللوحة'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // 🪟 النافذة الصغيرة: الوردة والوقت وأهم زر
  Widget _miniBody(BuildContext context) {
    final theme = Theme.of(context);
    final time = switch (_phase) {
      FocusPhase.focusing => _format(_planned - _focused),
      FocusPhase.onBreak => _format(
        _breakEndsAt!.difference(_now()).isNegative
            ? Duration.zero
            : _breakEndsAt!.difference(_now()),
      ),
      FocusPhase.bloomed => '🌹',
      FocusPhase.budded => '🌱',
      FocusPhase.breakDone => '💪',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _phase == FocusPhase.onBreak ? '☕ راحة' : _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'رجّع النافذة كبيرة',
                  onPressed: _exitMini,
                  icon: const Icon(Icons.open_in_full),
                ),
              ],
            ),
            Expanded(child: Center(child: _rose(220))),
            Text(
              time,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            if (_phase == FocusPhase.focusing)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: _paused ? 'كمّل' : 'إيقاف مؤقت',
                    onPressed: _togglePause,
                    icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'زِد ٥ دقائق',
                    onPressed: _addFiveMinutes,
                    icon: const Icon(Icons.more_time),
                  ),
                ],
              )
            else if (_phase == FocusPhase.bloomed)
              FilledButton(
                onPressed: _startBreak,
                child: Text('ابدأ الراحة ($_breakMinutes د)'),
              )
            else
              FilledButton(
                onPressed: _exitMini,
                child: const Text('افتح النافذة'),
              ),
          ],
        ),
      ),
    );
  }
}
