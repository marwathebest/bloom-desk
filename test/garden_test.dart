import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom_desk/models/focus_session.dart';
import 'package:bloom_desk/pages/garden_page.dart';

FocusSession session(
  DateTime at, {
  String? projectId,
  String projectName = '',
  int color = 0xFFE0607E,
  int seconds = 1500,
  bool completed = true,
  String task = '',
  List<String> ideas = const [],
}) => FocusSession(
  id: at.toIso8601String(),
  projectId: projectId,
  projectName: projectName,
  colorValue: color,
  task: task,
  plannedMinutes: 25,
  focusedSeconds: seconds,
  completed: completed,
  startedAt: at,
  ideas: ideas,
);

final now = DateTime(2026, 11, 18, 17); // Wednesday

final sample = [
  session(
    DateTime(2026, 11, 18, 9, 5),
    projectId: 'a',
    projectName: 'Rose Garden',
    task: 'أرسم الوردة',
    ideas: ['وضع ليلي'],
  ),
  session(
    DateTime(2026, 11, 18, 14, 30),
    projectId: 'b',
    projectName: 'SPL',
    color: 0xFF4A7FD0,
    seconds: 600,
    completed: false,
  ),
  session(
    DateTime(2026, 11, 18, 11),
    projectId: 'a',
    projectName: 'Rose Garden',
    seconds: 2700,
    ideas: ['أصوات هادئة', 'زر مشاركة'],
  ),
  session(DateTime(2026, 11, 17, 10), task: 'شغل أمس'),
];

Future<void> pumpGarden(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: GardenPage(sessions: sample, clock: () => now),
    ),
  );
  await tester.pump();
}

void main() {
  test('sessionsOn picks one day, oldest first', () {
    final today = sessionsOn(sample, now);
    expect(today.map((s) => s.startedAt.hour), [9, 11, 14]);
  });

  test('timePerProject adds up and sorts by time', () {
    final list = timePerProject(sessionsOn(sample, now));
    expect(list.first.name, 'Rose Garden');
    expect(list.first.minutes, 70);
    expect(list.first.sessions, 2);
    expect(list.last.name, 'SPL');
    expect(list.last.minutes, 10);
  });

  test('sessions with no project are grouped as "بدون مشروع"', () {
    final list = timePerProject([session(now), session(now)]);
    expect(list.single.name, 'بدون مشروع');
    expect(list.single.sessions, 2);
  });

  test('formatClock and dayLabel', () {
    expect(formatClock(DateTime(2026, 1, 1, 0, 5)), '12:05 ص');
    expect(formatClock(DateTime(2026, 1, 1, 14, 30)), '2:30 م');
    expect(dayLabel(now, now), 'اليوم');
    expect(dayLabel(DateTime(2026, 11, 17), now), 'أمس');
    expect(dayLabel(DateTime(2026, 11, 16), now), 'الاثنين 16/11');
  });

  testWidgets('shows today: summary, time per project, ideas', (tester) async {
    await pumpGarden(tester);

    expect(find.text('اليوم'), findsOneWidget);
    expect(find.textContaining('🌹 2'), findsOneWidget);
    expect(find.textContaining('🌱 1'), findsOneWidget);
    expect(find.textContaining('1 س 20 د تركيز'), findsOneWidget);

    // One rose per session, labelled with its start time
    expect(find.text('9:05 ص'), findsOneWidget);
    expect(find.text('11:00 ص'), findsOneWidget);
    expect(find.text('2:30 م'), findsOneWidget);

    expect(find.text('Rose Garden'), findsOneWidget);
    expect(find.textContaining('1 س 10 د'), findsOneWidget);
    expect(find.text('💡 أفكارك الطارئة (3)'), findsOneWidget);
    expect(find.text('زر مشاركة'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tap a rose to see its details', (tester) async {
    await pumpGarden(tester);
    await tester.tap(find.text('9:05 ص'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('🌹 أرسم الوردة'), findsOneWidget);
    expect(find.textContaining('ركّزت 25 د من 25 د'), findsOneWidget);
    expect(find.text('• وضع ليلي'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('move between days; cannot go past today', (tester) async {
    await pumpGarden(tester);

    final next = find.ancestor(
      of: find.byTooltip('اليوم اللي بعد'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(next).onPressed, isNull);

    await tester.tap(find.byTooltip('اليوم اللي قبل'));
    await tester.pump();
    expect(find.text('أمس'), findsOneWidget);
    expect(find.text('10:00 ص'), findsOneWidget);
    expect(find.text('9:05 ص'), findsNothing);

    await tester.tap(find.byTooltip('اليوم اللي قبل'));
    await tester.pump();
    expect(find.text('ما فيه جلسات هذا اليوم'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
