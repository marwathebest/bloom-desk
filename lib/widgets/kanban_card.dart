import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/health_check.dart';

const _healthColors = {
  HealthLevel.ok: Color(0xFF3A9A5B),
  HealthLevel.warn: Color(0xFFD99A1E),
  HealthLevel.error: Color(0xFFD64545),
};

// بطاقة المشروع في لوحة كانبان: نسخة مصغّرة تنسحب بين الأعمدة
class KanbanCard extends StatelessWidget {
  const KanbanCard({
    super.key,
    required this.project,
    required this.onRun,
    required this.onRunLocal,
    required this.onOpenCode,
    required this.onOpenFolder,
    required this.onEdit,
    required this.onDelete,
    required this.onFocus,
    this.health,
    this.checking = false,
    this.onFix,
  });

  final Project project;
  final VoidCallback onRun;
  final VoidCallback onRunLocal;
  final VoidCallback onOpenCode;
  final VoidCallback onOpenFolder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFocus;
  final HealthResult? health;
  final bool checking;
  final VoidCallback? onFix;

  bool get _isLive => project.liveUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: project.color.withValues(alpha: 0.3)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط لون المشروع على الجنب
            Container(width: 5, color: project.color),
            Expanded(
              child: InkWell(
                onTap: onEdit, // تضغط البطاقة = تفتحها للتعديل
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: project.color.withValues(
                              alpha: 0.15,
                            ),
                            child: Icon(
                              project.isNoteOnly
                                  ? Icons.lightbulb_outline
                                  : project.type.icon,
                              size: 17,
                              color: project.color,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  project.isNoteOnly
                                      ? 'ملاحظة'
                                      : project.type.label,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _menu(),
                        ],
                      ),
                      if (project.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          project.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      // 📝 الملاحظات
                      if (project.notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4D6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '📝 ${project.notes}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      if (checking || health != null) ...[
                        const SizedBox(height: 6),
                        _healthLine(theme, muted),
                      ],
                      // فكرة بدون مجلد: ما فيه شي نشغّله، فنخفي الأزرار
                      if (project.isNoteOnly)
                        const SizedBox(height: 6)
                      else ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: onRun,
                              style: FilledButton.styleFrom(
                                backgroundColor: project.color,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              icon: Icon(
                                _isLive
                                    ? Icons.public
                                    : Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text(_isLive ? 'الموقع' : 'اعرض'),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'افتح في VS Code',
                              visualDensity: VisualDensity.compact,
                              onPressed: onOpenCode,
                              icon: const Icon(Icons.code, size: 20),
                            ),
                            IconButton(
                              tooltip: 'افتح المجلد',
                              visualDensity: VisualDensity.compact,
                              onPressed: onOpenFolder,
                              icon: const Icon(
                                Icons.folder_open_outlined,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      tooltip: 'خيارات',
      onSelected: (value) {
        switch (value) {
          case 'focus':
            onFocus();
          case 'edit':
            onEdit();
          case 'local':
            onRunLocal();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'focus', child: Text('🌱 جلسة تركيز')),
        const PopupMenuItem(value: 'edit', child: Text('تعديل')),
        if (_isLive)
          const PopupMenuItem(value: 'local', child: Text('شغّل من جهازي')),
        const PopupMenuItem(value: 'delete', child: Text('حذف')),
      ],
    );
  }

  Widget _healthLine(ThemeData theme, Color muted) {
    if (checking) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'يفحص...',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      );
    }
    final color = _healthColors[health!.level];
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            health!.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (health!.fixCommand != null && onFix != null)
          TextButton(
            onPressed: onFix,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('صلّح'),
          ),
      ],
    );
  }
}
