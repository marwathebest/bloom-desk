import 'package:flutter/material.dart';

import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/focus_controller.dart';
import '../services/focus_environment.dart';
import '../services/project_store.dart';
import '../services/session_store.dart';
import '../widgets/focus_rose_painter.dart';

export '../services/focus_controller.dart' show FocusPhase;

// صفحة جلسة التركيز: تعرض "محرّك" الجلسة (FocusController)
//
// لما تنفتح من صفحة المشاريع، المحرّك يجي جاهز من برا: ترجع لمشاريعك
// والجلسة تكمل بالخلفية، ويطلع شريط الجلسة فوق.
// ولو انفتحت لحالها (مثل الاختبارات)، تسوي محرّكها بنفسها وتوقفه لما تنقفل.
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
    this.controller,
  });

  final String task;
  final int minutes;
  final Project? project;
  final SessionStore? store;
  final ProjectStore? projectStore;
  final DateTime Function()? clock; // للاختبارات: ساعة نتحكم فيها
  final FocusSession? resume; // جلسة انقطعت ونكمّلها
  final FocusEnvironment? environment; // النافذة والتنبيهات والأصوات
  final FocusController? controller; // جلسة شغّالة جاية من صفحة المشاريع

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

  late final bool _ownsSession = widget.controller == null;
  late final FocusController _c =
      widget.controller ??
      FocusController(
        task: widget.task,
        minutes: widget.minutes,
        project: widget.project,
        store: widget.store,
        projectStore: widget.projectStore,
        clock: widget.clock,
        resume: widget.resume,
        environment: widget.environment,
      );
  final _ideaController = TextEditingController();

  // الجلسة تكمل بالخلفية لو رجعت؟ (بس لما المحرّك جاي من برا)
  bool get _background => !_ownsSession;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.pageOpen = true;
    if (_ownsSession) {
      _c.onNext = (kind) {
        if (mounted) Navigator.pop(context, kind);
      };
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.pageOpen = false;
    if (_ownsSession) _c.dispose();
    _motion.dispose();
    _ideaController.dispose();
    super.dispose();
  }

  // "رجوع" بعد ما تخلص الجلسة: الجلسة انتهت، نقفلها ونرجع
  void _done() {
    _c.close();
    Navigator.pop(context);
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
    if (confirmed == true && mounted) await _c.finishEarly();
  }

  // زر الرجوع وسط جلسة ما تكمل بالخلفية: ثلاث خيارات
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
    if (choice == 'pause' && !_c.paused) _c.togglePause();
    if (choice == 'end') await _c.finishEarly();
  }

  void _addIdea() {
    _c.addIdea(_ideaController.text);
    _ideaController.clear();
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
            growth:
                _c.phase == FocusPhase.focusing || _c.phase == FocusPhase.budded
                ? _c.growth
                : 1,
            color: _c.color,
            time: _motion.value * 600,
            sparkles: _c.phase == FocusPhase.focusing && !_c.paused,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusing = _c.phase == FocusPhase.focusing;
    return PopScope(
      // جلسة بالخلفية: ترجع عادي والجلسة تكمل
      canPop: _background || !focusing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Color.lerp(Colors.white, _c.color, 0.06),
        appBar: _c.mini
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                title: Text(_c.project?.name ?? 'جلسة تركيز'),
                actions: [
                  if (focusing || _c.phase == FocusPhase.onBreak)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: IconButton(
                        tooltip: 'نافذة صغيرة فوق البرامج',
                        onPressed: () =>
                            _c.enterMini(View.of(context).devicePixelRatio),
                        icon: const Icon(Icons.picture_in_picture_alt_outlined),
                      ),
                    ),
                ],
              ),
        body: _c.mini ? _miniBody(context) : _fullBody(context),
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
              if (_background &&
                  (_c.phase == FocusPhase.focusing ||
                      _c.phase == FocusPhase.onBreak))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '↩ ارجع لمشاريعك متى ما تبي، والجلسة تكمل',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _c.title,
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
    final done = _c.doneToday;
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
        for (var i = 0; i < _c.goal; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              i < done ? Icons.circle : Icons.circle_outlined,
              size: 12,
              color: _c.color,
            ),
          ),
        const SizedBox(width: 10),
        Text(
          '$done من ${_c.goal}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (done >= _c.goal) const Text('  🎉'),
      ],
    );
  }

  List<Widget> _phaseContent(ThemeData theme) {
    final big = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w300,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    switch (_c.phase) {
      case FocusPhase.focusing:
        return [
          Text(_format(_c.remaining), style: big),
          if (_c.paused)
            Text('⏸️ موقوف مؤقتاً', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _c.togglePause,
                icon: Icon(_c.paused ? Icons.play_arrow : Icons.pause),
                label: Text(_c.paused ? 'كمّل' : 'إيقاف مؤقت'),
              ),
              OutlinedButton.icon(
                onPressed: _c.addFiveMinutes,
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
                  selected: _c.sound == s.id,
                  onSelected: (_) => _c.setSound(s.id),
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
            'ركّزت ${_c.plannedMinutes} دقيقة',
            style: theme.textTheme.bodyLarge,
          ),
          if (_c.longBreak)
            Text(
              '🎉 ${_c.doneToday} جلسات اليوم! تستاهل راحة طويلة',
              style: theme.textTheme.bodyLarge,
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _c.startBreak,
            icon: const Icon(Icons.local_cafe_outlined),
            label: Text('ابدأ الراحة (${_c.breakMinutes} د)'),
          ),
          TextButton(onPressed: _done, child: const Text('رجوع')),
          _ideasAfter(theme),
        ];

      case FocusPhase.budded:
        final minutes = _c.focused.inMinutes;
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
          FilledButton(onPressed: _done, child: const Text('رجوع')),
          _ideasAfter(theme),
        ];

      case FocusPhase.onBreak:
        return [
          Text(
            _c.longBreak ? '☕ راحة طويلة' : '☕ وقت الراحة',
            style: theme.textTheme.headlineMedium,
          ),
          Text(_format(_c.breakLeft), style: big),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: _c.autoNext, onChanged: _c.setAutoNext),
              const SizedBox(width: 8),
              Text(
                'ابدأ الجلسة الجاية لحالها',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          TextButton(
            onPressed: _c.skipBreak,
            child: const Text('تخطّى الراحة'),
          ),
        ];

      case FocusPhase.breakDone:
        return [
          Text('💪 خلصت الراحة', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _c.requestNext,
            icon: const Icon(Icons.replay),
            label: const Text('جلسة جديدة'),
          ),
          TextButton(onPressed: _done, child: const Text('رجوع')),
        ];
    }
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
        if (_c.ideas.isNotEmpty) ...[const SizedBox(height: 12), _ideasList()],
      ],
    );
  }

  Widget _ideasList() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [for (final idea in _c.ideas) Chip(label: Text('💡 $idea'))],
    );
  }

  // بعد الجلسة: وين تروح الأفكار؟
  Widget _ideasAfter(ThemeData theme) {
    if (_c.ideas.isEmpty) return const SizedBox.shrink();
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
            '💡 أفكارك الطارئة (${_c.ideas.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _ideasList(),
          const SizedBox(height: 12),
          if (_c.ideasMessage != null)
            Text(
              _c.ideasMessage!,
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
                if (_c.project != null)
                  FilledButton.tonalIcon(
                    onPressed: _c.sendIdeasToNotes,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: Text('أضفها لملاحظات «${_c.project!.name}»'),
                  ),
                OutlinedButton.icon(
                  onPressed: _c.sendIdeasToBoard,
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
    final time = switch (_c.phase) {
      FocusPhase.focusing => _format(_c.remaining),
      FocusPhase.onBreak => _format(_c.breakLeft),
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
                    _c.phase == FocusPhase.onBreak ? '☕ راحة' : _c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'رجّع النافذة كبيرة',
                  onPressed: _c.exitMini,
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
            if (_c.phase == FocusPhase.focusing)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: _c.paused ? 'كمّل' : 'إيقاف مؤقت',
                    onPressed: _c.togglePause,
                    icon: Icon(_c.paused ? Icons.play_arrow : Icons.pause),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'زِد ٥ دقائق',
                    onPressed: _c.addFiveMinutes,
                    icon: const Icon(Icons.more_time),
                  ),
                ],
              )
            else if (_c.phase == FocusPhase.bloomed)
              FilledButton(
                onPressed: _c.startBreak,
                child: Text('ابدأ الراحة (${_c.breakMinutes} د)'),
              )
            else
              FilledButton(
                onPressed: _c.exitMini,
                child: const Text('افتح النافذة'),
              ),
          ],
        ),
      ),
    );
  }
}
