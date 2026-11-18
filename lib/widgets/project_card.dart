import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/project.dart';
import '../services/health_check.dart';

// ألوان نتيجة الفحص
const _healthColors = {
  HealthLevel.ok: Color(0xFF3A9A5B),
  HealthLevel.warn: Color(0xFFD99A1E),
  HealthLevel.error: Color(0xFFD64545),
};

// بطاقة المشروع الواحد في المعرض
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
    required this.onOpenCode,
    required this.onOpenFolder,
    required this.onRunLocal,
    required this.onStatusChanged,
    required this.onFocus,
    this.health,
    this.checking = false,
    this.onFix,
  });

  final Project project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRun;
  final VoidCallback onOpenCode;
  final VoidCallback onOpenFolder;
  final VoidCallback onRunLocal;
  final ValueChanged<ProjectStatus> onStatusChanged;
  final VoidCallback onFocus; // 🌱 جلسة تركيز على هالمشروع
  final HealthResult? health; // نتيجة "جهّز للعرض"
  final bool checking; // يفحص الحين؟
  final VoidCallback? onFix; // يصلّح المشكلة (لو لها حل)

  bool get _isLive => project.liveUrl.trim().isNotEmpty;

  Future<void> _openLink(String link) async {
    final withScheme = link.contains('://') ? link : 'https://$link';
    final uri = Uri.tryParse(withScheme);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _shortLink(String link) {
    final uri = Uri.tryParse(link.contains('://') ? link : 'https://$link');
    return (uri?.host.isNotEmpty ?? false) ? uri!.host : link;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: project.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط اللون فوق
          Container(height: 6, color: project.color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // الأيقونة + الاسم + النوع + القائمة
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: project.color.withValues(alpha: 0.15),
                        child: Icon(project.type.icon, color: project.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${project.type.label}  ·  ',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: muted,
                                    ),
                                  ),
                                ),
                                // الحالة: تضغطها وتغيّرها مباشرة
                                PopupMenuButton<ProjectStatus>(
                                  tooltip: 'غيّر الحالة',
                                  onSelected: onStatusChanged,
                                  itemBuilder: (_) => [
                                    for (final s in ProjectStatus.values)
                                      CheckedPopupMenuItem(
                                        value: s,
                                        checked: s == project.status,
                                        child: Text('${s.emoji}  ${s.label}'),
                                      ),
                                  ],
                                  child: Text(
                                    '${project.status.emoji} ${project.status.label}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
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
                          const PopupMenuItem(
                            value: 'focus',
                            child: Text('🌱 جلسة تركيز'),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('تعديل'),
                          ),
                          if (_isLive)
                            const PopupMenuItem(
                              value: 'local',
                              child: Text('شغّل من جهازي'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // الوصف
                  if (project.description.isNotEmpty)
                    Text(
                      project.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  const Spacer(),

                  // مسار المجلد
                  if (project.path.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.folder_outlined, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            project.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),

                  // الروابط
                  if (project.links.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: project.links.take(3).map((link) {
                        return InkWell(
                          onTap: () => _openLink(link),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link, size: 16, color: project.color),
                              const SizedBox(width: 4),
                              Text(
                                _shortLink(link),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: project.color,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // نتيجة الفحص قبل العرض
                  if (checking)
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'يفحص...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    )
                  else if (health != null)
                    SizedBox(
                      height: 28,
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: _healthColors[health!.level],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              health!.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _healthColors[health!.level],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (health!.fixCommand != null && onFix != null)
                            TextButton.icon(
                              onPressed: onFix,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.build_outlined, size: 16),
                              label: const Text('صلّح'),
                            ),
                        ],
                      ),
                    ),
                  if (checking || health != null) const SizedBox(height: 8),

                  // أزرار التشغيل
                  // لو البطاقة عريضة: "VS Code" بالاسم، ولو ضيقة: أيقونة بس
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onRun,
                            style: FilledButton.styleFrom(
                              backgroundColor: project.color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            icon: Icon(
                              _isLive ? Icons.public : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              _isLive ? 'افتح الموقع' : 'اعرض',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (constraints.maxWidth >= 300)
                          OutlinedButton.icon(
                            onPressed: onOpenCode,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            icon: const Icon(Icons.code, size: 18),
                            label: const Text('VS Code'),
                          )
                        else
                          IconButton.outlined(
                            tooltip: 'افتح في VS Code',
                            onPressed: onOpenCode,
                            icon: const Icon(Icons.code, size: 18),
                          ),
                        IconButton(
                          tooltip: 'افتح المجلد',
                          onPressed: onOpenFolder,
                          icon: const Icon(Icons.folder_open_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
