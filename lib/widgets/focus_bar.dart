import 'package:flutter/material.dart';

import '../services/focus_controller.dart';
import 'focus_rose_painter.dart';

// شريط الجلسة: يطلع فوق صفحة المشاريع والجلسة شغّالة بالخلفية
// وردة صغيرة تتمايل، والوقت الباقي، وإيقاف مؤقت، وزر يفتح الجلسة
class FocusBar extends StatefulWidget {
  const FocusBar({super.key, required this.controller, required this.onOpen});

  final FocusController controller;
  final VoidCallback onOpen;

  @override
  State<FocusBar> createState() => _FocusBarState();
}

class _FocusBarState extends State<FocusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(minutes: 10),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final (status, time) = switch (c.phase) {
          FocusPhase.focusing => (
            c.paused ? '⏸️ موقوف مؤقتاً' : '🌱 تركيز',
            _format(c.remaining),
          ),
          FocusPhase.bloomed => ('🌹 تفتحت وردتك!', ''),
          FocusPhase.budded => ('🌱 صارت برعم', ''),
          FocusPhase.onBreak => ('☕ راحة', _format(c.breakLeft)),
          FocusPhase.breakDone => ('💪 خلصت الراحة', ''),
        };

        return Material(
          color: Color.lerp(Colors.white, c.color, 0.10),
          child: InkWell(
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  // وردة صغيرة تتمايل
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: AnimatedBuilder(
                      animation: _motion,
                      builder: (context, _) => CustomPaint(
                        painter: FocusRosePainter(
                          growth:
                              c.phase == FocusPhase.focusing ||
                                  c.phase == FocusPhase.budded
                              ? c.growth
                              : 1,
                          color: c.color,
                          time: _motion.value * 600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.project == null
                              ? c.title
                              : '${c.title} · ${c.project!.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          status,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (time.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: Text(
                        time,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  if (c.phase == FocusPhase.focusing)
                    IconButton(
                      tooltip: c.paused ? 'كمّل' : 'إيقاف مؤقت',
                      onPressed: c.togglePause,
                      icon: Icon(c.paused ? Icons.play_arrow : Icons.pause),
                    ),
                  if (c.phase == FocusPhase.bloomed)
                    TextButton(
                      onPressed: c.startBreak,
                      child: Text('ابدأ الراحة (${c.breakMinutes} د)'),
                    ),
                  // جلسة خلصت: تقدر تقفل الشريط
                  if (c.phase == FocusPhase.budded ||
                      c.phase == FocusPhase.breakDone)
                    IconButton(
                      tooltip: 'قفل الجلسة',
                      onPressed: c.close,
                      icon: const Icon(Icons.close),
                    ),
                  FilledButton.tonal(
                    onPressed: widget.onOpen,
                    child: const Text('افتح الجلسة'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
