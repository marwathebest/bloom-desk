import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bloom_desk/main.dart';
import 'package:bloom_desk/services/focus_controller.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

// Opens the app with one project and starts a 25-minute session on it
Future<void> startSession(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'projects': jsonEncode([
      {'id': 'p1', 'name': 'Alpha', 'color': 0xFFE0607E, 'path': r'C:\x'},
    ]),
  });
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const BloomDeskApp());
  await tester.pumpAndSettle();

  await tester.tap(find.text('ركّز'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'وش بتسوي؟'),
    'صفحة الدخول',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'ابدأ'));
  await settle(tester);
  expect(find.textContaining('ارجع لمشاريعك متى ما تبي'), findsOneWidget);
}

Future<void> goBack(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
  await settle(tester);
}

void main() {
  testWidgets('going back keeps the session running and shows the bar', (
    tester,
  ) async {
    await startSession(tester);
    await goBack(tester);

    // No "end or pause?" question: you are back on your projects
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('مشاريعي (1)'), findsOneWidget);
    // The session bar is on top, and the session is still running
    expect(find.text('افتح الجلسة'), findsOneWidget);
    expect(find.textContaining('صفحة الدخول'), findsOneWidget);
    expect(activeFocus.value, isNotNull);
    expect(activeFocus.value!.phase, FocusPhase.focusing);
    expect(activeFocus.value!.paused, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(activeFocus.value, isNull); // closing the app stops it
  });

  testWidgets('pause from the bar, then reopen the same session', (
    tester,
  ) async {
    await startSession(tester);
    await goBack(tester);
    final session = activeFocus.value;

    await tester.tap(find.byTooltip('إيقاف مؤقت'));
    await tester.pump();
    expect(session!.paused, isTrue);
    expect(find.text('⏸️ موقوف مؤقتاً'), findsOneWidget);

    await tester.tap(find.text('افتح الجلسة'));
    await settle(tester);
    expect(activeFocus.value, same(session)); // same session, not a new one
    expect(find.text('⏸️ موقوف مؤقتاً'), findsOneWidget);
    expect(find.text('كمّل'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"ركّز" while a session runs opens it instead of a new one', (
    tester,
  ) async {
    await startSession(tester);
    await goBack(tester);
    final session = activeFocus.value;

    await tester.tap(find.text('ركّز'));
    await settle(tester);
    expect(find.text('جلسة تركيز 🌱'), findsNothing); // no setup dialog
    expect(activeFocus.value, same(session));
    expect(find.textContaining('ارجع لمشاريعك متى ما تبي'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ending, then "رجوع", closes the session and the bar', (
    tester,
  ) async {
    await startSession(tester);

    await tester.tap(find.text('أنهِ الجلسة'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'أنهِ'));
    await settle(tester);
    expect(find.text('🌱 وردتك صارت برعم'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'رجوع'));
    await settle(tester);
    expect(find.text('مشاريعي (1)'), findsOneWidget);
    expect(find.text('افتح الجلسة'), findsNothing);
    expect(activeFocus.value, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finished session left in the bar can be closed with ✕', (
    tester,
  ) async {
    await startSession(tester);
    await tester.tap(find.text('أنهِ الجلسة'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'أنهِ'));
    await settle(tester);
    await goBack(tester); // leave with the back arrow instead of "رجوع"

    expect(find.text('🌱 صارت برعم'), findsOneWidget);
    await tester.tap(find.byTooltip('قفل الجلسة'));
    await tester.pump();
    expect(find.text('افتح الجلسة'), findsNothing);
    expect(activeFocus.value, isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
