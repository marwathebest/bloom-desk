import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/session_store.dart';
import '../widgets/focus_setup_dialog.dart';
import 'focus_page.dart';
import 'garden_page.dart';
import '../services/health_check.dart';
import '../services/project_detector.dart';
import '../services/project_launcher.dart';
import '../services/project_store.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/save_queue.dart';
import '../widgets/idea_dialog.dart';
import '../widgets/kanban_board.dart';
import '../widgets/kanban_card.dart';
import '../widgets/project_card.dart';
import '../widgets/project_form.dart';

// صفحة "مشاريعي": معرض كل مشاريعك
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, this.pickFolder});

  // طريقة اختيار المجلد (الاختبارات تعطي طريقة بديلة)
  final Future<String?> Function()? pickFolder;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final _store = ProjectStore();

  // الحالة
  List<Project> _projects = [];
  bool _loading = true;
  String _search = '';
  bool _dragging = false; // فيه مجلد يتسحب فوق النافذة؟
  ProjectStatus? _filter; // null = الكل
  String _view = 'board'; // 'board' = لوحة كانبان، 'grid' = بطاقات
  final Map<String, HealthResult> _health = {}; // نتائج "جهّز للعرض"
  final Set<String> _checking = {}; // المشاريع اللي تنفحص الحين
  final _sessionStore = SessionStore();
  List<FocusSession> _sessions = []; // جلسات التركيز

  @override
  void initState() {
    super.initState();
    _load();
    // لما ترجع لهالنافذة، نحدّث القائمة بالتغييرات اللي صارت في نافذة ثانية
    _lifecycle = AppLifecycleListener(onResume: _load);
  }

  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final projects = await _store.load();
    final sessions = await _sessionStore.load();
    final prefs = await SharedPreferences.getInstance();
    final view = prefs.getString('view');
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _sessions = sessions;
      if (view == 'board' || view == 'grid') _view = view!;
      _loading = false;
    });
  }

  // نحفظ اختيارك (لوحة أو بطاقات) عشان يفتح عليه المرة الجاية
  Future<void> _setView(String view) async {
    setState(() => _view = view);
    await SaveQueue.shared.run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.setString('view', view);
    });
  }

  // 💡 فكرة جديدة: ملاحظة في عمود الأفكار، بدون مجلد
  Future<void> _addIdea() async {
    final idea = await showDialog<({String title, String notes})>(
      context: context,
      builder: (_) => const IdeaDialog(),
    );
    if (idea == null) return;
    final fresh = await _store.upsert(
      Project(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: idea.title,
        notes: idea.notes,
        type: ProjectType.other,
        status: ProjectStatus.idea,
        color: projectColors[_projects.length % projectColors.length],
      ),
    );
    if (!mounted) return;
    setState(() => _projects = fresh);
  }

  // 🌷 حديقة اليوم
  void _openGarden() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GardenPage(sessions: _sessions)),
    );
  }

  // 🌱 جلسة تركيز: تختار المشروع والمدة، وتنفتح صفحة الوردة
  Future<void> _startFocus([Project? project]) async {
    final setup = await showDialog<FocusSetup>(
      context: context,
      builder: (_) =>
          FocusSetupDialog(projects: _projects, initialProject: project),
    );
    if (setup == null || !mounted) return;

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => FocusPage(
          task: setup.task,
          minutes: setup.minutes,
          project: setup.project,
        ),
      ),
    );

    final sessions = await _sessionStore.load();
    if (!mounted) return;
    setState(() => _sessions = sessions);
    if (result == 'again') _startFocus(setup.project);
  }

  // إضافة مشروع جديد، أو تعديل مشروع موجود
  Future<void> _addOrEdit([Project? existing]) async {
    final result = await showDialog<Project>(
      context: context,
      builder: (_) => ProjectForm(project: existing),
    );
    if (result == null) return; // ضغط "إلغاء"

    final fresh = await _store.upsert(result);
    if (!mounted) return;
    setState(() {
      _projects = fresh;
      _health.remove(result.id); // تغيّر المشروع، فالفحص القديم ما عاد ينفع
    });
  }

  Future<void> _delete(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف "${project.name}"؟'),
        content: const Text(
          'بينحذف من Bloom Desk بس. ملفات المشروع في جهازك ما تنلمس.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final fresh = await _store.remove(project.id);
    if (!mounted) return;
    setState(() => _projects = fresh);
  }

  // أسرع طريقة: تختار المجلد، والباقي يتعبّى تلقائياً
  Future<void> _pickAndAdd() async {
    if (kIsWeb) return _addOrEdit(); // المتصفح ما يقدر يقرأ مجلدات جهازك
    final pick =
        widget.pickFolder ??
        () => getDirectoryPath(confirmButtonText: 'اختر المجلد');
    final path = await pick();
    if (path == null) return; // قفل نافذة الاختيار
    await _addFromFolders([path]);
  }

  // يضيف مجلد أو أكثر كمشاريع، ويعرف اسم ونوع كل واحد بنفسه
  Future<void> _addFromFolders(List<String> paths) async {
    final added = <Project>[];
    var skipped = 0;
    // نقرأ آخر نسخة، عشان نعرف المشاريع اللي انضافت من نافذة ثانية
    final current = await _store.load();

    for (final path in paths) {
      final isFolder = Directory(path).existsSync();
      final alreadyAdded = current.any(
        (p) => p.path.toLowerCase() == path.toLowerCase(),
      );
      if (!isFolder || alreadyAdded) {
        skipped++;
        continue;
      }

      // لو صار أي خطأ وقت فحص المجلد، نضيفه باسم المجلد بدل ما نوقف
      DetectedProject detected;
      try {
        detected = detectProject(path);
      } on Object {
        detected = DetectedProject(
          name: path
              .split(RegExp(r'[\\/]'))
              .lastWhere((part) => part.isNotEmpty, orElse: () => path),
          description: '',
          type: ProjectType.other,
          links: const [],
        );
      }
      added.add(
        Project(
          id: '${DateTime.now().microsecondsSinceEpoch}_${added.length}',
          name: detected.name,
          description: detected.description,
          path: path,
          type: detected.type,
          color:
              projectColors[(current.length + added.length) %
                  projectColors.length],
          links: detected.links,
          liveUrl: detected.liveUrl,
        ),
      );
    }

    if (!mounted) return;
    if (added.isEmpty) {
      setState(() => _projects = current);
      _showMessage(
        skipped > 0
            ? 'هذا المشروع موجود من قبل، أو اللي سحبته ملف مو مجلد'
            : 'ما انضاف شيء',
      );
      return;
    }

    final fresh = await _store.upsertAll(added);
    if (!mounted) return;
    setState(() => _projects = fresh);

    final first = added.first;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added.length == 1
              ? 'انضاف «${first.name}» ✓'
              : 'انضافت ${added.length} مشاريع ✓',
        ),
        action: added.length == 1
            ? SnackBarAction(label: 'تعديل', onPressed: () => _addOrEdit(first))
            : null,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ينفّذ أمر (تشغيل، أو VS Code، أو المجلد) ويعرض النتيجة
  Future<void> _act(
    Future<String?> Function(Project) action,
    Project project, {
    String? successMessage,
  }) async {
    if (kIsWeb) {
      _showMessage('هذا يشتغل في نسخة ويندوز بس 🪟');
      return;
    }
    final error = await action(project);
    if (!mounted) return;
    if (error != null) {
      _showMessage('⚠️ $error');
    } else if (successMessage != null) {
      _showMessage(successMessage);
    }
  }

  Future<void> _setStatus(Project project, ProjectStatus status) async {
    setState(() => project.status = status); // يتغير فوراً على الشاشة
    final fresh = await _store.upsert(project);
    if (!mounted) return;
    setState(() => _projects = fresh);
  }

  // ✅ جهّز للعرض: يفحص كل المشاريع مع بعض
  Future<void> _checkAll() async {
    if (kIsWeb) {
      _showMessage('الفحص يشتغل في نسخة ويندوز بس 🪟');
      return;
    }
    // الأفكار اللي لسا ما لها مجلد ولا موقع ما فيه شي نفحصه فيها
    final projects = _projects.where((p) => !p.isNoteOnly).toList();
    setState(() {
      _health.clear();
      _checking.addAll(projects.map((p) => p.id));
    });

    await Future.wait(
      projects.map((project) async {
        final result = await checkProject(project);
        if (!mounted) return;
        setState(() {
          _health[project.id] = result;
          _checking.remove(project.id);
        });
      }),
    );
    if (!mounted) return;

    int count(HealthLevel level) =>
        _health.values.where((r) => r.level == level).length;
    final warn = count(HealthLevel.warn);
    final error = count(HealthLevel.error);
    _showMessage(
      warn == 0 && error == 0
          ? '🟢 كل مشاريعك جاهزة للعرض!'
          : '🟢 ${count(HealthLevel.ok)} جاهز  ·  🟡 $warn يحتاج تجهيز  ·  🔴 $error فيه مشكلة',
    );
  }

  // يصلّح المشكلة (مثل npm install) في نافذة تيرمنال
  Future<void> _fix(Project project) async {
    final command = _health[project.id]?.fixCommand;
    if (command == null) return;
    final error = await runInTerminal(project, command);
    if (!mounted) return;
    if (error != null) {
      _showMessage('⚠️ $error');
      return;
    }
    setState(() => _health.remove(project.id));
    _showMessage(
      '🔧 يجهّز «${project.name}»... لما يخلص اضغط "جهّز للعرض" مرة ثانية',
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final visible = _projects
        .where(
          (p) =>
              (_view == 'board' || _filter == null || p.status == _filter) &&
              (p.name.toLowerCase().contains(query) ||
                  p.description.toLowerCase().contains(query)),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          '🌸 Bloom Desk',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'حديقتي',
            onPressed: _openGarden,
            icon: const Icon(Icons.local_florist_outlined),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => _startFocus(),
            icon: const Icon(Icons.spa_outlined),
            label: const Text('ركّز'),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: FilledButton.tonalIcon(
              onPressed: _projects.isEmpty || _checking.isNotEmpty
                  ? null
                  : _checkAll,
              icon: _checking.isNotEmpty
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: const Text('جهّز للعرض'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndAdd,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('أضف مشروع'),
      ),
      // تسحب مجلد (أو أكثر) من الملفات وتفلته فوق النافذة = ينضاف
      body: DropTarget(
        enable: !kIsWeb,
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _addFromFolders(details.files.map((f) => f.path).toList());
        },
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent(visible)),
            if (_dragging) const Positioned.fill(child: _DropOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<Project> visible) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _projects.isEmpty
        ? _EmptyState(onAdd: _pickAndAdd)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'مشاريعي (${_projects.length})',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        // التبديل بين اللوحة والبطاقات
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 'board',
                              icon: Icon(Icons.view_kanban_outlined),
                              label: Text('لوحة'),
                            ),
                            ButtonSegment(
                              value: 'grid',
                              icon: Icon(Icons.grid_view_outlined),
                              label: Text('بطاقات'),
                            ),
                          ],
                          selected: {_view},
                          onSelectionChanged: (s) => _setView(s.first),
                        ),
                      ],
                    ),
                    // ملخص اليوم من جلسات التركيز
                    Builder(
                      builder: (context) {
                        final today = summarizeDay(_sessions, DateTime.now());
                        if (today.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: InkWell(
                            onTap: _openGarden,
                            borderRadius: BorderRadius.circular(8),
                            child: Text(
                              'اليوم:  🌹 ${today.bloomed}   🥀 ${today.wilted}'
                              '   ·   ${formatMinutes(today.focusedMinutes)} تركيز  ‹',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: TextField(
                        onChanged: (value) => setState(() => _search = value),
                        decoration: InputDecoration(
                          hintText: 'ابحث في مشاريعك...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    // فلتر الحالة (في البطاقات بس؛ اللوحة فيها أعمدة الحالة)
                    if (_view == 'grid') ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('الكل (${_projects.length})'),
                            selected: _filter == null,
                            onSelected: (_) => setState(() => _filter = null),
                          ),
                          for (final s in ProjectStatus.values)
                            ChoiceChip(
                              label: Text(
                                '${s.emoji} ${s.label} '
                                '(${_projects.where((p) => p.status == s).length})',
                              ),
                              selected: _filter == s,
                              onSelected: (_) => setState(() => _filter = s),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _view == 'board'
                    // 📋 لوحة كانبان
                    ? KanbanBoard(
                        projects: visible,
                        onMove: _setStatus,
                        onAddIdea: _addIdea,
                        cardBuilder: (project) => KanbanCard(
                          project: project,
                          onRun: () => _run(project),
                          onRunLocal: () => _runLocal(project),
                          onOpenCode: () => _act(openInVsCode, project),
                          onOpenFolder: () => _act(openFolder, project),
                          onEdit: () => _addOrEdit(project),
                          onDelete: () => _delete(project),
                          onFocus: () => _startFocus(project),
                          health: _health[project.id],
                          checking: _checking.contains(project.id),
                          onFix: () => _fix(project),
                        ),
                      )
                    // 🔲 البطاقات
                    : visible.isEmpty
                    ? const Center(child: Text('ما فيه مشاريع هنا 🔍'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 380,
                              mainAxisExtent: 296,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final project = visible[index];
                          return ProjectCard(
                            project: project,
                            onEdit: () => _addOrEdit(project),
                            onDelete: () => _delete(project),
                            onRun: () => _run(project),
                            onRunLocal: () => _runLocal(project),
                            onOpenCode: () => _act(openInVsCode, project),
                            onOpenFolder: () => _act(openFolder, project),
                            onStatusChanged: (s) => _setStatus(project, s),
                            onFocus: () => _startFocus(project),
                            health: _health[project.id],
                            checking: _checking.contains(project.id),
                            onFix: () => _fix(project),
                          );
                        },
                      ),
              ),
            ],
          );
  }

  void _run(Project project) => _act(
    runProject,
    project,
    successMessage: project.liveUrl.trim().isNotEmpty
        ? '🌐 يفتح موقع «${project.name}»...'
        : project.type == ProjectType.react
        ? '▶️ يشتغل «${project.name}»... والمتصفح بينفتح لحاله أول ما يجهز'
        : '▶️ يشتغل «${project.name}»...',
  );

  void _runLocal(Project project) => _act(
    (p) => runProject(p, local: true),
    project,
    successMessage:
        '▶️ يشتغل «${project.name}» من جهازك... والمتصفح بينفتح لحاله أول ما يجهز',
  );
}

// يظهر لما تسحب مجلد فوق النافذة
class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Text(
            'افلت المجلد هنا 🌱',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// شاشة البداية لما ما فيه مشاريع
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📂', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('اسحب مجلد مشروعك هنا', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'أو اضغط الزر واختر المجلد، والاسم والنوع ورابط GitHub تتعبّى لحالها',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('أضف مشروع'),
            ),
          ],
        ),
      ),
    );
  }
}
