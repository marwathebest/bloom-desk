import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/focus_session.dart';
import '../models/project.dart';
import 'focus_environment.dart';
import 'focus_prefs.dart';
import 'project_store.dart';
import 'session_store.dart';

// مراحل الجلسة
// budded = أنهيت بدري: الوردة توقف على حجمها (برعم) بدل ما تذبل
enum FocusPhase { focusing, bloomed, budded, onBreak, breakDone }

// الجلسة الشغّالة الحين (لو فيه). صفحة المشاريع تسمع لها وتعرض شريط الجلسة
final ValueNotifier<FocusController?> activeFocus = ValueNotifier(null);

// محرّك جلسة التركيز: الوقت، والحفظ، والتنبيهات، والصوت، والنافذة الصغيرة
//
// منفصل عن الصفحة، عشان الجلسة تكمل وأنت ترجع لمشاريعك وملفاتك.
// الصفحة وشريط الجلسة بس "يعرضون" هذا المحرّك.
class FocusController extends ChangeNotifier {
  FocusController({
    required this.task,
    required int minutes,
    this.project,
    SessionStore? store,
    ProjectStore? projectStore,
    DateTime Function()? clock,
    FocusSession? resume,
    FocusEnvironment? environment,
  }) : _store = store ?? SessionStore(),
       _projectStore = projectStore ?? ProjectStore(),
       _clock = clock ?? DateTime.now,
       env = environment ?? FocusEnvironment.current,
       ideas = List.of(resume?.ideas ?? const []) {
    _startedAt = resume?.startedAt ?? _clock();
    _id = resume?.id ?? _startedAt.microsecondsSinceEpoch.toString();
    plannedMinutes = resume?.plannedMinutes ?? minutes;
    _accumulated = Duration(seconds: resume?.focusedSeconds ?? 0);
    _resumedAt = _clock();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadToday();
  }

  final String task;
  final Project? project;
  final FocusEnvironment env;
  final SessionStore _store;
  final ProjectStore _projectStore;
  final DateTime Function() _clock;
  final _prefs = FocusPrefs();
  final List<String> ideas;

  // لما تخلص الراحة أو تبي جلسة جديدة: 'again' أو 'again-auto'
  void Function(String kind)? onNext;
  // الصفحة مفتوحة الحين؟ (عشان نعرف نرجع لها أو نكمل بالخلفية)
  bool pageOpen = false;

  Timer? _timer;
  bool _closed = false;
  FocusPhase phase = FocusPhase.focusing;
  late final String _id;
  late final DateTime _startedAt;
  late int plannedMinutes; // يزيد لو ضغطت "زِد ٥ دقائق"
  Duration _accumulated = Duration.zero; // الوقت قبل آخر إيقاف مؤقت
  DateTime? _resumedAt; // null = موقوف مؤقتاً
  DateTime? _breakEndsAt;
  int breakMinutes = 5;
  DateTime? _lastSaveAt;

  int _doneBefore = 0; // جلسات اليوم المكتملة قبل هذي
  bool _completedThis = false;
  int goal = FocusPrefs.defaultGoal;
  bool autoNext = false;
  String sound = 'off';

  bool mini = false;
  Rect? _fullBounds;

  String? ideasMessage; // بعد ما ترسل الأفكار للملاحظات أو اللوحة

  bool get isClosed => _closed;
  DateTime now() => _clock();
  Duration get planned => Duration(minutes: plannedMinutes);
  bool get paused => _resumedAt == null;
  Color get color => project?.color ?? const Color(0xFFE0607E);
  int get doneToday => _doneBefore + (_completedThis ? 1 : 0);
  bool get longBreak => breakMinutes == 15;
  String get title => task.isEmpty ? 'ركّز 🌱' : task;

  // الوقت اللي ركّزته فعلاً (بدون أوقات الإيقاف)
  Duration get focused {
    final running = paused ? Duration.zero : _clock().difference(_resumedAt!);
    final total = _accumulated + running;
    return total > planned ? planned : total;
  }

  Duration get remaining => planned - focused;
  double get growth => focused.inMilliseconds / planned.inMilliseconds;

  Duration get breakLeft {
    final left = _breakEndsAt?.difference(_clock()) ?? Duration.zero;
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _loadToday() async {
    final sessions = await _store.load();
    final dailyGoal = await _prefs.dailyGoal();
    final auto = await _prefs.autoNext();
    final chosen = await _prefs.sound();
    if (_closed) return;
    final today = _clock();
    _doneBefore = sessions
        .where(
          (s) => s.completed && s.id != _id && isSameDay(s.startedAt, today),
        )
        .length;
    goal = dailyGoal;
    autoNext = auto;
    sound = chosen;
    _applySound();
    _notify();
  }

  void _tick() {
    if (_closed) return;
    if (phase == FocusPhase.focusing && focused >= planned) {
      _complete();
      return;
    }
    if (phase == FocusPhase.onBreak && !_clock().isBefore(_breakEndsAt!)) {
      _breakOver();
      return;
    }
    // حفظ تلقائي كل ٣٠ ثانية (حتى وأنت موقف مؤقتاً): لو انقفل البرنامج
    // فجأة، وقتك ما يضيع، والبرنامج يعرض عليك تكمّل الجلسة
    if (phase == FocusPhase.focusing &&
        focused.inSeconds >= 60 &&
        (_lastSaveAt == null ||
            _clock().difference(_lastSaveAt!) >= const Duration(seconds: 30))) {
      _save(completed: false, active: true);
    }
    _notify(); // نحدّث العداد
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void togglePause() {
    if (paused) {
      _resumedAt = _clock();
    } else {
      _accumulated += _clock().difference(_resumedAt!);
      _resumedAt = null;
    }
    _applySound();
    _notify();
  }

  void addFiveMinutes() {
    plannedMinutes += 5;
    _notify();
  }

  // 🌹 خلص الوقت
  Future<void> _complete() async {
    _accumulated = planned;
    _resumedAt = null;
    phase = FocusPhase.bloomed;
    _completedThis = true;
    // كل ٤ جلسات اليوم: راحة طويلة
    breakMinutes = doneToday % 4 == 0
        ? 15
        : plannedMinutes >= 45
        ? 10
        : 5;
    env.stopSound();
    _notify();
    _alert(
      '🌹 تفتحت وردتك!',
      'ركّزت $plannedMinutes دقيقة على «$title». وقت الراحة ☕',
    );
    await _save(completed: true, active: false);
  }

  // 🌱 أنهيت بدري: الوردة توقف على حجمها، والوقت ينحسب
  Future<void> finishEarly() async {
    if (phase != FocusPhase.focusing) return;
    _accumulated = focused;
    _resumedAt = null;
    phase = FocusPhase.budded;
    env.stopSound();
    _notify();
    if (_accumulated.inSeconds >= 60 || _lastSaveAt != null) {
      await _save(completed: false, active: false);
    }
  }

  Future<void> _save({required bool completed, required bool active}) {
    final at = _clock();
    _lastSaveAt = at;
    return _store.upsert(
      FocusSession(
        id: _id,
        projectId: project?.id,
        projectName: project?.name ?? '',
        colorValue: color.toARGB32(),
        task: task,
        plannedMinutes: plannedMinutes,
        focusedSeconds: focused.inSeconds,
        completed: completed,
        startedAt: _startedAt,
        ideas: List.of(ideas),
        active: active,
        updatedAt: at,
      ),
    );
  }

  // 🔔 تنبيه: صوت + إشعار ويندوز + وميض في شريط المهام
  void _alert(String alertTitle, String body) {
    SystemSound.play(SystemSoundType.alert);
    env.notify(alertTitle, body);
    env.window.flash();
  }

  void startBreak() {
    phase = FocusPhase.onBreak;
    _breakEndsAt = _clock().add(Duration(minutes: breakMinutes));
    _notify();
  }

  void skipBreak() => _breakOver(skipped: true);

  void _breakOver({bool skipped = false}) {
    phase = FocusPhase.breakDone;
    _notify();
    if (!skipped) _alert('💪 خلصت الراحة', 'جاهز للجلسة الجاية؟');
    if (autoNext) onNext?.call('again-auto');
  }

  // "جلسة جديدة"
  void requestNext() => onNext?.call('again');

  Future<void> setAutoNext(bool on) async {
    autoNext = on;
    _notify();
    await _prefs.setAutoNext(on);
  }

  Future<void> setSound(String id) async {
    sound = id;
    _applySound();
    _notify();
    await _prefs.setSound(id);
  }

  // الصوت يشتغل بس وأنت مركّز، ويوقف مع الإيقاف المؤقت
  void _applySound() {
    final file = focusSounds
        .firstWhere((s) => s.id == sound, orElse: () => focusSounds.first)
        .file;
    if (phase == FocusPhase.focusing && !paused && file != null) {
      env.playSound(file);
    } else {
      env.stopSound();
    }
  }

  void addIdea(String text) {
    final idea = text.trim();
    if (idea.isEmpty) return;
    ideas.add(idea);
    _notify();
  }

  // 💡 الأفكار → ملاحظات المشروع
  Future<void> sendIdeasToNotes() async {
    final p = project;
    if (p == null) return;
    final all = await _projectStore.load();
    final fresh = all.where((x) => x.id == p.id).firstOrNull;
    if (fresh == null) {
      ideasMessage = 'ما لقيت المشروع، يمكن انحذف';
      _notify();
      return;
    }
    fresh.notes = [
      if (fresh.notes.trim().isNotEmpty) fresh.notes.trim(),
      for (final idea in ideas) '• $idea',
    ].join('\n');
    await _projectStore.upsert(fresh);
    ideasMessage = '✓ انضافت لملاحظات «${p.name}»';
    _notify();
  }

  // 💡 الأفكار → بطاقات في عمود الأفكار
  Future<void> sendIdeasToBoard() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final from = project?.name ?? '';
    await _projectStore.upsertAll([
      for (var i = 0; i < ideas.length; i++)
        Project(
          id: '${stamp}_$i',
          name: ideas[i],
          notes: from.isEmpty
              ? 'من جلسة «$title»'
              : 'من جلسة «$title» على $from',
          type: ProjectType.other,
          status: ProjectStatus.idea,
          color: color,
        ),
    ]);
    ideasMessage = '✓ صارت ${ideas.length} أفكار في عمود 💡 فكرة';
    _notify();
  }

  // 🪟 نافذة صغيرة فوق كل البرامج
  Future<void> enterMini(double devicePixelRatio) async {
    final bounds = await env.window.bounds();
    mini = true;
    _notify();
    if (bounds == null) return;
    _fullBounds = bounds;
    final w = 320 * devicePixelRatio, h = 470 * devicePixelRatio;
    await env.window.setBounds(
      Rect.fromLTWH(bounds.right - w, bounds.top, w, h),
    );
    await env.window.setAlwaysOnTop(true);
  }

  Future<void> exitMini() async {
    await env.window.setAlwaysOnTop(false);
    if (_fullBounds != null) await env.window.setBounds(_fullBounds!);
    mini = false;
    _notify();
  }

  // نهاية الجلسة: نوقف كل شي ونشيلها من "الجلسة الشغّالة"
  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    env.stopSound();
    if (mini) {
      env.window.setAlwaysOnTop(false);
      if (_fullBounds != null) env.window.setBounds(_fullBounds!);
    }
    if (activeFocus.value == this) activeFocus.value = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
