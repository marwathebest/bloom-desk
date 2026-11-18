import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:bloom_desk/models/focus_session.dart';
import 'package:bloom_desk/models/project.dart';
import 'package:bloom_desk/services/project_store.dart';
import 'package:bloom_desk/services/session_store.dart';

Project project(String id, {ProjectStatus status = ProjectStatus.inProgress}) =>
    Project(id: id, name: 'P$id', color: Colors.pink, status: status);

FocusSession session(String id) => FocusSession(
  id: id,
  projectId: null,
  projectName: '',
  colorValue: 0,
  task: '',
  plannedMinutes: 25,
  focusedSeconds: 1500,
  completed: true,
  startedAt: DateTime(2026, 11, 18),
);

// The "other window": writes straight to the file on disk,
// behind the back of this window's cached SharedPreferences.
Future<void> otherWindowWrites(String key, Object value) async {
  await SharedPreferencesStorePlatform.instance.setValue(
    'String',
    'flutter.$key',
    jsonEncode(value),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a change here keeps a project added in another window', () async {
    final store = ProjectStore();
    await store.upsert(project('1')); // this window adds project 1

    // The other window adds project 2 (this window doesn't know yet)
    await otherWindowWrites('projects', [
      project('1').toJson(),
      project('2').toJson(),
    ]);

    // This window marks project 1 as done
    final fresh = await store.upsert(project('1', status: ProjectStatus.done));

    expect(fresh.map((p) => p.id), ['1', '2']); // project 2 survived
    expect(fresh.first.status, ProjectStatus.done);
  });

  test('deleting here keeps a project added in another window', () async {
    final store = ProjectStore();
    await store.upsertAll([project('1'), project('2')]);
    await otherWindowWrites('projects', [
      project('1').toJson(),
      project('2').toJson(),
      project('3').toJson(),
    ]);

    final fresh = await store.remove('1');
    expect(fresh.map((p) => p.id), ['2', '3']);
  });

  test('two quick additions at the same moment both survive', () async {
    final store = ProjectStore();
    // Like dropping two folders back to back:
    // both start before either finishes
    await Future.wait([
      store.upsert(project('first')),
      store.upsert(project('second')),
      store.upsert(project('third')),
    ]);
    final all = await store.load();
    expect(all.map((p) => p.id), unorderedEquals(['first', 'second', 'third']));
  });

  test('a project and a rose saved at the same moment both survive', () async {
    await Future.wait([
      ProjectStore().upsert(project('p')),
      SessionStore().add(session('s')),
    ]);
    expect((await ProjectStore().load()).single.id, 'p');
    expect((await SessionStore().load()).single.id, 's');
  });

  test('load always sees the latest file', () async {
    final store = ProjectStore();
    expect(await store.load(), isEmpty);
    await otherWindowWrites('projects', [project('9').toJson()]);
    expect((await store.load()).single.id, '9');
  });

  test('a session saved here keeps sessions from another window', () async {
    final store = SessionStore();
    await store.add(session('a'));
    await otherWindowWrites('sessions', [
      session('a').toJson(),
      session('b').toJson(),
    ]);

    await store.add(session('c'));
    final all = await store.load();
    expect(all.map((s) => s.id), ['a', 'b', 'c']);
  });
}
