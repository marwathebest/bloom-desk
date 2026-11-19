import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bloom_desk/main.dart';
import 'package:bloom_desk/models/focus_session.dart';
import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/pages/focus_page.dart';
import 'package:bloom_desk/services/desktop_window.dart';
import 'package:bloom_desk/services/focus_environment.dart';
import 'package:bloom_desk/services/project_store.dart';
import 'package:bloom_desk/services/session_store.dart';

class FakeClock {
  DateTime now = DateTime(2026, 11, 19, 10);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

class FakeWindow implements WindowControls {
  Rect? rect = const Rect.fromLTWH(100, 100, 1280, 800);
  bool onTop = false;
  int flashes = 0;
  @override
  Future<Rect?> bounds() async => rect;
  @override
  Future<void> setBounds(Rect r) async => rect = r;
  @override
  Future<void> setAlwaysOnTop(bool v) async => onTop = v;
  @override
  Future<void> flash() async => flashes++;
  @override
  Future<void> bringToFront() async {}
}

class Recorder {
  final notifications = <String>[];
  final played = <String>[];
  int stops = 0;
}

final rose = Project(id: 'p1', name: 'Rose Garden', color: Colors.teal);

Future<({FakeWindow window, Recorder rec})> pumpFocus(
  WidgetTester tester,
  FakeClock clock, {
  int minutes = 1,
  Map<String, Object> prefs = const {},
  FocusSession? resume,
  Project? project,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final window = FakeWindow();
  final rec = Recorder();
  await tester.pumpWidget(
    MaterialApp(
      home: FocusPage(
        task: 'ألوان جديدة',
        minutes: minutes,
        project: project ?? rose,
        clock: clock.call,
        resume: resume,
        environment: FocusEnvironment(
          window: window,
          notify: (title, _) async => rec.notifications.add(title),
          playSound: (file) async => rec.played.add(file),
          stopSound: () async => rec.stops++,
        ),
      ),
    ),
  );
  await tester.pump();
  return (window: window, rec: rec);
}

Future<void> tick(WidgetTester tester, FakeClock clock, Duration by) async {
  clock.advance(by);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<List<FocusSession>> sessions(WidgetTester tester) async =>
    (await tester.runAsync(() => SessionStore().load()))!;

Future<List<Project>> projects(WidgetTester tester) async =>
    (await tester.runAsync(() => ProjectStore().load()))!;

FocusSession done(DateTime at, String id) => FocusSession(
  id: id,
  projectId: null,
  projectName: '',
  colorValue: 0,
  task: '',
  plannedMinutes: 25,
  focusedSeconds: 1500,
  completed: true,
  startedAt: at,
);

void main() {
  testWidgets('+5 minutes extends the session', (tester) async {
    final clock = FakeClock();
    await pumpFocus(tester, clock);
    expect(find.text('01:00'), findsOneWidget);
    await tester.tap(find.text('زِد ٥ دقائق'));
    await tester.pump();
    expect(find.text('06:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finishing sends a notification and flashes the taskbar', (
    tester,
  ) async {
    final clock = FakeClock();
    final env = await pumpFocus(tester, clock);
    await tick(tester, clock, const Duration(minutes: 1));
    expect(find.text('🌹 تفتحت وردتك!'), findsOneWidget);
    expect(env.rec.notifications, ['🌹 تفتحت وردتك!']);
    expect(env.window.flashes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back button offers continue, pause or end', (tester) async {
    final clock = FakeClock();
    await pumpFocus(tester, clock, minutes: 25);
    await tick(tester, clock, const Duration(minutes: 2));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    final dialog = find.byType(AlertDialog);

    nav.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('جلستك لسا شغّالة 🌱'), findsOneWidget);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('إيقاف مؤقت')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('⏸️ موقوف مؤقتاً'), findsOneWidget);

    nav.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('أنهِ الجلسة')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('🌱 وردتك صارت برعم'), findsOneWidget);
    expect((await sessions(tester)).single.focusedSeconds, 120);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a resumed session continues from its saved time', (
    tester,
  ) async {
    final clock = FakeClock();
    final cut = FocusSession(
      id: 'old',
      projectId: 'p1',
      projectName: 'Rose Garden',
      colorValue: 0,
      task: 'ألوان جديدة',
      plannedMinutes: 25,
      focusedSeconds: 600,
      completed: false,
      startedAt: clock.now.subtract(const Duration(minutes: 30)),
      ideas: const ['زر مشاركة'],
      active: true,
    );
    await pumpFocus(tester, clock, minutes: 25, resume: cut);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('💡 زر مشاركة'), findsOneWidget);

    await tick(tester, clock, const Duration(minutes: 15));
    expect(find.text('🌹 تفتحت وردتك!'), findsOneWidget);
    final saved = (await sessions(tester)).single;
    expect(saved.id, 'old');
    expect(saved.completed, isTrue);
    expect(saved.active, isFalse);
    expect(saved.focusedSeconds, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the 4th session of the day earns a long break', (tester) async {
    final clock = FakeClock();
    await pumpFocus(
      tester,
      clock,
      prefs: {
        'sessions': jsonEncode([
          for (var i = 0; i < 3; i++)
            done(clock.now.subtract(Duration(hours: i + 1)), 's$i').toJson(),
        ]),
      },
    );
    await tick(tester, clock, const Duration(minutes: 1));
    expect(find.text('ابدأ الراحة (15 د)'), findsOneWidget);
    expect(find.textContaining('4 جلسات اليوم'), findsOneWidget);
    expect(find.text('4 من 6'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto-start: when the break ends the page asks for the next', (
    tester,
  ) async {
    final clock = FakeClock();
    SharedPreferences.setMockInitialValues({'autoNext': true});
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => FocusPage(
                    task: 't',
                    minutes: 1,
                    clock: clock.call,
                    environment: FocusEnvironment.none(),
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tick(tester, clock, const Duration(minutes: 1));
    await tester.tap(find.text('ابدأ الراحة (5 د)'));
    await tester.pump();
    expect(find.byType(Switch), findsOneWidget);
    await tick(tester, clock, const Duration(minutes: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(result, 'again-auto');
  });

  testWidgets('quick ideas can go to the project notes', (tester) async {
    final clock = FakeClock();
    await pumpFocus(
      tester,
      clock,
      prefs: {
        'projects': jsonEncode([
          {'id': 'p1', 'name': 'Rose Garden', 'color': 0, 'notes': 'قديم'},
        ]),
      },
    );
    await tester.enterText(find.byType(TextField), 'وضع ليلي');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tick(tester, clock, const Duration(minutes: 1));

    await tester.tap(find.text('أضفها لملاحظات «Rose Garden»'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('✓ انضافت لملاحظات «Rose Garden»'), findsOneWidget);
    expect((await projects(tester)).single.notes, 'قديم\n• وضع ليلي');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick ideas can become idea cards on the board', (tester) async {
    final clock = FakeClock();
    await pumpFocus(tester, clock);
    for (final idea in ['فكرة أ', 'فكرة ب']) {
      await tester.enterText(find.byType(TextField), idea);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    await tick(tester, clock, const Duration(minutes: 1));

    await tester.tap(find.text('حوّلها لأفكار في اللوحة'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final ideas = await projects(tester);
    expect(ideas.map((p) => p.name), ['فكرة أ', 'فكرة ب']);
    expect(ideas.every((p) => p.status == ProjectStatus.idea), isTrue);
    expect(ideas.every((p) => p.isNoteOnly), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mini window shrinks, stays on top, then restores', (
    tester,
  ) async {
    final clock = FakeClock();
    final env = await pumpFocus(tester, clock, minutes: 25);
    final original = env.window.rect;
    final dpr = tester.view.devicePixelRatio;

    await tester.tap(find.byTooltip('نافذة صغيرة فوق البرامج'));
    await tester.pump();
    await tester.pump();
    expect(env.window.onTop, isTrue);
    expect(env.window.rect!.width, 320 * dpr);
    expect(env.window.rect!.right, original!.right);
    expect(find.byTooltip('رجّع النافذة كبيرة'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.byTooltip('رجّع النافذة كبيرة'));
    await tester.pump();
    await tester.pump();
    expect(env.window.onTop, isFalse);
    expect(env.window.rect, original);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('choosing a sound plays it, pausing stops it, and it is saved', (
    tester,
  ) async {
    final clock = FakeClock();
    final env = await pumpFocus(tester, clock, minutes: 25);
    await tester.tap(find.text('🌧️ مطر'));
    await tester.pump();
    expect(env.rec.played.last, 'sounds/rain.wav');
    final stopsBefore = env.rec.stops;

    await tester.tap(find.text('إيقاف مؤقت'));
    await tester.pump();
    expect(env.rec.stops, greaterThan(stopsBefore));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sound'), 'rain');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('custom length from the setup dialog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BloomDeskApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('ركّز'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مخصص'));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, 'ابدأ');

    await tester.enterText(find.widgetWithText(TextField, 'كم دقيقة؟'), '0');
    await tester.pump();
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'كم دقيقة؟'), '35');
    await tester.pump();
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // the real clock may tick a second during the test: 35:00 or 34:59
    expect(find.textContaining(RegExp(r'^(35:00|34:5\d)$')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unfinished session is offered on start, or kept as a bud', (
    tester,
  ) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'sessions': jsonEncode([
        FocusSession(
          id: 'cut',
          projectId: null,
          projectName: '',
          colorValue: 0,
          task: 'صفحة الدفع',
          plannedMinutes: 25,
          focusedSeconds: 720,
          completed: false,
          startedAt: now.subtract(const Duration(minutes: 20)),
          active: true,
          updatedAt: now.subtract(const Duration(minutes: 8)),
        ).toJson(),
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const BloomDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('🌱 عندك جلسة ما خلصت'), findsOneWidget);
    expect(find.textContaining('ركّزت 12 من 25 دقيقة'), findsOneWidget);
    await tester.tap(find.text('خلّها برعم'));
    await tester.pumpAndSettle();
    expect((await sessions(tester)).single.active, isFalse);
  });

  test('isUnfinished: only when the app really closed mid-session', () {
    final now = DateTime(2026, 11, 19, 12);
    FocusSession s(Duration since, {bool active = true, Duration? age}) =>
        FocusSession(
          id: 'x',
          projectId: null,
          projectName: '',
          colorValue: 0,
          task: '',
          plannedMinutes: 25,
          focusedSeconds: 300,
          completed: false,
          startedAt: now.subtract(age ?? const Duration(minutes: 20)),
          active: active,
          updatedAt: now.subtract(since),
        );
    // saved 30 s ago: probably still running in another window
    expect(s(const Duration(seconds: 30)).isUnfinished(now), isFalse);
    expect(s(const Duration(minutes: 5)).isUnfinished(now), isTrue);
    expect(
      s(const Duration(minutes: 5), active: false).isUnfinished(now),
      isFalse,
    );
    expect(
      s(
        const Duration(minutes: 5),
        age: const Duration(hours: 13),
      ).isUnfinished(now),
      isFalse,
    );
  });
}
