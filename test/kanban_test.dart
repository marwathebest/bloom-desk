import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bloom_desk/main.dart';
import 'package:bloom_desk/models/project.dart';

Map<String, Object> board(List<Map<String, Object>> projects) => {
  'projects': jsonEncode(projects),
};

Map<String, Object> p(
  String id,
  String name,
  String status, {
  String path = r'C:\x',
}) => {
  'id': id,
  'name': name,
  'color': 0xFFE0607E,
  'status': status,
  'path': path,
};

Future<void> pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const BloomDeskApp());
  await tester.pumpAndSettle();
}

// Center of the column (drop target) that holds a card
double columnX(WidgetTester tester, String text) => tester
    .getCenter(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byType(DragTarget<Project>),
          )
          .first,
    )
    .dx;

Future<List<Project>> saved() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return (jsonDecode(prefs.getString('projects')!) as List)
      .map((j) => Project.fromJson(j as Map<String, dynamic>))
      .toList();
}

void main() {
  testWidgets('board is the default: three columns with counts', (
    tester,
  ) async {
    await pumpApp(
      tester,
      board([
        p('1', 'Alpha', 'idea'),
        p('2', 'Beta', 'inProgress'),
        p('3', 'Gamma', 'inProgress'),
        p('4', 'Delta', 'done'),
      ]),
    );

    expect(find.text('💡 فكرة'), findsOneWidget);
    expect(find.text('🛠️ قيد العمل'), findsOneWidget);
    expect(find.text('✅ مكتمل'), findsOneWidget);
    // Status chips belong to the grid only
    expect(find.byType(ChoiceChip), findsNothing);

    // Each card sits in its own column
    double x(String text) => columnX(tester, text);
    expect(x('Beta'), moreOrLessEquals(x('Gamma'), epsilon: 1));
    expect(x('Alpha'), isNot(moreOrLessEquals(x('Beta'), epsilon: 50)));
    expect(x('Delta'), isNot(moreOrLessEquals(x('Beta'), epsilon: 50)));
  });

  testWidgets('dragging a card to another column changes its status', (
    tester,
  ) async {
    await pumpApp(
      tester,
      board([p('1', 'Alpha', 'idea'), p('2', 'Beta', 'done')]),
    );

    final from = tester.getCenter(find.text('Alpha'));
    final to = tester.getCenter(find.text('Beta')) + const Offset(0, 60);
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final alpha = (await saved()).firstWhere((x) => x.id == '1');
    expect(alpha.status, ProjectStatus.done);
    // Now both cards share the done column
    expect(
      columnX(tester, 'Alpha'),
      moreOrLessEquals(columnX(tester, 'Beta'), epsilon: 1),
    );
  });

  testWidgets('new idea note goes to the idea column with its notes', (
    tester,
  ) async {
    await pumpApp(tester, board([p('1', 'Beta', 'inProgress')]));

    await tester.tap(find.text('فكرة جديدة'));
    await tester.pumpAndSettle();
    // Title is required
    await tester.tap(find.text('احفظ الفكرة'));
    await tester.pumpAndSettle();
    expect(find.text('اكتب الفكرة'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'تطبيق ري النباتات',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'تذكير يومي\nصور النباتات',
    );
    await tester.tap(find.text('احفظ الفكرة'));
    await tester.pumpAndSettle();

    expect(find.text('تطبيق ري النباتات'), findsOneWidget);
    expect(find.textContaining('📝 تذكير يومي'), findsOneWidget);
    // An idea with no folder has nothing to run
    final ideaCard = find
        .ancestor(
          of: find.text('تطبيق ري النباتات'),
          matching: find.byType(Material),
        )
        .first;
    expect(
      find.descendant(of: ideaCard, matching: find.text('اعرض')),
      findsNothing,
    );

    final idea = (await saved()).firstWhere(
      (x) => x.name == 'تطبيق ري النباتات',
    );
    expect(idea.status, ProjectStatus.idea);
    expect(idea.notes, 'تذكير يومي\nصور النباتات');
    expect(idea.isNoteOnly, isTrue);
  });

  testWidgets('the pre-demo check skips ideas with no folder', (tester) async {
    await pumpApp(tester, board([p('1', 'Just an idea', 'idea', path: '')]));
    await tester.tap(find.text('جهّز للعرض'));
    await tester.pumpAndSettle();
    expect(find.text('ما فيه مجلد ولا رابط موقع'), findsNothing);
    expect(find.textContaining('كل مشاريعك جاهزة'), findsOneWidget);
  });

  testWidgets('switching to cards is remembered', (tester) async {
    await pumpApp(tester, board([p('1', 'Alpha', 'idea')]));

    await tester.tap(find.text('بطاقات'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsWidgets);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('view'), 'grid');
  });

  test('notes survive save and load', () {
    final project = Project(
      id: '1',
      name: 'x',
      color: Colors.pink,
      notes: 'سطر\nسطر ثاني',
    );
    expect(Project.fromJson(project.toJson()).notes, 'سطر\nسطر ثاني');
    expect(Project.fromJson({'id': '1', 'name': 'x', 'color': 0}).notes, '');
  });
}
