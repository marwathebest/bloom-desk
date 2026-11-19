import 'package:flutter/material.dart';

import '../models/project.dart';

// لون كل عمود (حالة)
const Map<ProjectStatus, Color> statusColors = {
  ProjectStatus.idea: Color(0xFFC98A1A), // عسلي
  ProjectStatus.inProgress: Color(0xFFE0607E), // وردي
  ProjectStatus.done: Color(0xFF4E9A6B), // أخضر
};

// لوحة كانبان: عمود لكل حالة، وتسحب البطاقة من عمود لعمود عشان تغيّر حالتها
class KanbanBoard extends StatelessWidget {
  const KanbanBoard({
    super.key,
    required this.projects,
    required this.cardBuilder,
    required this.onMove,
    required this.onAddIdea,
  });

  final List<Project> projects;
  final Widget Function(Project project) cardBuilder;
  final void Function(Project project, ProjectStatus status) onMove;
  final VoidCallback onAddIdea; // 💡 فكرة جديدة (ملاحظة بدون مجلد)

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          for (final status in ProjectStatus.values)
            _KanbanColumn(
              status: status,
              projects: projects.where((p) => p.status == status).toList(),
              cardBuilder: cardBuilder,
              onMove: onMove,
              onAdd: status == ProjectStatus.idea ? onAddIdea : null,
            ),
        ];

        // نافذة عريضة: الأعمدة تتقاسم العرض
        if (constraints.maxWidth >= 840) {
          return Padding(
            // مسافة تحت عشان زر "أضف مشروع" ما يغطي الأعمدة
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: columns[i]),
                ],
              ],
            ),
          );
        }

        // نافذة ضيقة: الأعمدة تتمرر جنب بعض
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          // مسافة تحت عشان زر "أضف مشروع" ما يغطي الأعمدة
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          itemCount: columns.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) => SizedBox(width: 300, child: columns[i]),
        );
      },
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.projects,
    required this.cardBuilder,
    required this.onMove,
    this.onAdd,
  });

  final ProjectStatus status;
  final List<Project> projects;
  final Widget Function(Project project) cardBuilder;
  final void Function(Project project, ProjectStatus status) onMove;
  final VoidCallback? onAdd; // زر إضافة (عمود الأفكار بس)

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = statusColors[status]!;

    return DragTarget<Project>(
      // نقبل البطاقة بس لو جاية من عمود ثاني
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => onMove(details.data, status),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: hovering
                ? accent.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hovering ? accent : const Color(0xFFF3D9DF),
              width: hovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // رأس العمود: الحالة + العدد
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${status.emoji} ${status.label}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${projects.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onAdd != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: OutlinedButton.icon(
                    onPressed: onAdd,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('فكرة جديدة'),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth - 20;
                    if (projects.isEmpty) {
                      return Center(
                        child: Text(
                          hovering
                              ? 'افلتها هنا ✨'
                              : onAdd != null
                              ? 'اكتب فكرة، أو اسحب مشروع هنا'
                              : 'اسحب مشروع هنا',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: projects.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final project = projects[i];
                        final card = cardBuilder(project);
                        return Draggable<Project>(
                          data: project,
                          // شكل البطاقة وهي تنسحب: مايلة شوي ومرفوعة
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: cardWidth,
                              child: Transform.rotate(
                                angle: -0.025,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: project.color.withValues(
                                          alpha: 0.25,
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: cardBuilder(project),
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: card,
                          ),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: card,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
