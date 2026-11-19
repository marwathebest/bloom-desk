import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bloom_desk/main.dart';
import 'package:bloom_desk/models/focus_session.dart';
import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/pages/focus_page.dart';
import 'package:bloom_desk/services/session_store.dart';

FocusSession session({
  required DateTime at,
  bool completed = true,
  int seconds = 1500,
}) => FocusSession(
  id: at.toIso8601String(),
  projectId: null,
  projectName: '',
  colorValue: 0xFFE0607E,
  task: 't',
  plannedMinutes: 25,
  focusedSeconds: seconds,
  completed: completed,
  startedAt: at,
);

// A clock the test moves forward by hand
class FakeClock {
  DateTime now = DateTime(2026, 11, 18, 10);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Future<void> pumpFocus(
  WidgetTester tester,
  FakeClock clock, {
  int minutes = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: FocusPage(
        task: 'أصلّح صفحة الدخول',
        minutes: minutes,
        project: Project(id: 'p1', name: 'Rose Garden', color: Colors.teal),
        clock: clock.call,
      ),
    ),
  );
}

Future<List<FocusSession>> savedSessions(WidgetTester tester) async =>
    (await tester.runAsync(() => SessionStore().load()))!;

void main() {
  test('session survives save and load', () {
    final s = FocusSession(
      id: '1',
      projectId: 'p',
      projectName: 'P',
      colorValue: 1,
      task: 'x',
      plannedMinutes: 45,
      focusedSeconds: 100,
      completed: false,
      startedAt: DateTime(2026, 1, 2, 3, 4),
      ideas: const ['a', 'b'],
    );
    final back = FocusSession.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(back.projectId, 'p');
    expect(back.completed, isFalse);
    expect(back.ideas, ['a', 'b']);
    expect(back.startedAt, DateTime(2026, 1, 2, 3, 4));
  });

  test('summarizeDay counts only that day', () {
    final day = DateTime(2026, 11, 18);
    final summary = summarizeDay([
      session(at: DateTime(2026, 11, 18, 9)),
      session(at: DateTime(2026, 11, 18, 14), completed: false, seconds: 600),
      session(at: DateTime(2026, 11, 17, 9)),
    ], day);
    expect(summary.bloomed, 1);
    expect(summary.wilted, 1);
    expect(summary.focusedMinutes, 35);
  });

  test('formatMinutes', () {
    expect(formatMinutes(40), '40 د');
    expect(formatMinutes(60), '1 س');
    expect(formatMinutes(75), '1 س 15 د');
  });

  testWidgets('timer counts down, pause stops it, rose blooms at the end', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final clock = FakeClock();
    await pumpFocus(tester, clock);
    expect(find.text('01:00'), findsOneWidget);

    clock.advance(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:30'), findsOneWidget);

    // Idea box
    await tester.enterText(find.byType(TextField), 'أضيف وضع ليلي');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('💡 أضيف وضع ليلي'), findsOneWidget);

    // Pause: time does not move
    await tester.tap(find.text('إيقاف مؤقت'));
    await tester.pump();
    clock.advance(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('⏸️ موقوف مؤقتاً'), findsOneWidget);

    // Resume and finish
    await tester.tap(find.text('كمّل'));
    await tester.pump();
    clock.advance(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('🌹 تفتحت وردتك!'), findsOneWidget);

    final saved = await savedSessions(tester);
    expect(saved.single.completed, isTrue);
    expect(saved.single.focusedSeconds, 60);
    expect(saved.single.projectName, 'Rose Garden');
    expect(saved.single.ideas, ['أضيف وضع ليلي']);

    // Break, then done
    await tester.tap(find.textContaining('ابدأ الراحة'));
    await tester.pump();
    expect(find.text('☕ وقت الراحة'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('💪 خلصت الراحة'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // stop timers
  });

  testWidgets('ending early leaves a bud and still saves the time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final clock = FakeClock();
    await pumpFocus(tester, clock, minutes: 25);

    clock.advance(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('أنهِ الجلسة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog opens
    await tester.tap(find.text('أنهِ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('🌱 وردتك صارت برعم'), findsOneWidget);
    final saved = await savedSessions(tester);
    expect(saved.single.completed, isFalse);
    expect(saved.single.focusedSeconds, 180);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('progress is saved while running, so closing the app keeps it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final clock = FakeClock();
    await pumpFocus(tester, clock, minutes: 25);

    // Under a minute: nothing saved yet
    clock.advance(const Duration(seconds: 45));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(await savedSessions(tester), isEmpty);

    // After 2 minutes: saved with the time so far
    clock.advance(const Duration(seconds: 75));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    var saved = await savedSessions(tester);
    expect(saved.single.focusedSeconds, 120);
    expect(saved.single.completed, isFalse);

    // Later: the same session is updated, not duplicated
    clock.advance(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    saved = await savedSessions(tester);
    expect(saved, hasLength(1));
    expect(saved.single.focusedSeconds, 300);

    // App closes suddenly mid-session: the 5 minutes stay saved
    await tester.pumpWidget(const SizedBox());
    saved = await savedSessions(tester);
    expect(saved.single.focusedSeconds, 300);

    // Finishing a session updates the same record to done
    clock.advance(const Duration(minutes: 1));
    await pumpFocus(tester, clock, minutes: 1);
    clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    saved = await savedSessions(tester);
    expect(saved, hasLength(2));
    expect(saved.last.completed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('focus button opens setup with the project list', (tester) async {
    SharedPreferences.setMockInitialValues({
      'projects': jsonEncode([
        {'id': '1', 'name': 'Alpha', 'color': 0xFFE0607E},
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BloomDeskApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('ركّز'));
    await tester.pumpAndSettle();
    expect(find.text('جلسة تركيز 🌱'), findsOneWidget);
    expect(find.text('25 د'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets("today's summary shows on the main page", (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'projects': jsonEncode([
        {'id': '1', 'name': 'Alpha', 'color': 0xFFE0607E},
      ]),
      'sessions': jsonEncode([
        session(at: now).toJson(),
        session(at: now, completed: false, seconds: 300).toJson(),
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BloomDeskApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('🌹 1'), findsOneWidget);
    expect(find.textContaining('🌱 1'), findsOneWidget);
    expect(find.textContaining('30 د تركيز'), findsOneWidget);
  });
}
