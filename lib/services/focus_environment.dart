import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';

import 'desktop_window.dart';

// الأصوات الهادئة المتوفرة
class FocusSound {
  const FocusSound(this.id, this.label, this.file);

  final String id;
  final String label;
  final String? file; // null = بدون صوت
}

const focusSounds = [
  FocusSound('off', '🔇 بدون', null),
  FocusSound('rain', '🌧️ مطر', 'sounds/rain.wav'),
  FocusSound('waves', '🌊 موج', 'sounds/waves.wav'),
  FocusSound('deep', '🟤 هدوء عميق', 'sounds/deep.wav'),
];

// كل اللي تحتاجه صفحة التركيز من الجهاز: النافذة، والتنبيهات، والأصوات
// في الاختبارات نستخدم FocusEnvironment.none() عشان ما تلمس شي حقيقي
class FocusEnvironment {
  FocusEnvironment({
    required this.window,
    required this.notify,
    required this.playSound,
    required this.stopSound,
  });

  final WindowControls window;
  final Future<void> Function(String title, String body) notify;
  final Future<void> Function(String file) playSound;
  final Future<void> Function() stopSound;

  // البيئة اللي تستخدمها الصفحة. main() يحطها "الحقيقية" على ويندوز
  static FocusEnvironment current = FocusEnvironment.none();

  factory FocusEnvironment.none() => FocusEnvironment(
    window: NoWindowControls(),
    notify: (_, _) async {},
    playSound: (_) async {},
    stopSound: () async {},
  );

  factory FocusEnvironment.windows() {
    AudioPlayer? player;
    return FocusEnvironment(
      window: Win32Window(),
      notify: (title, body) async {
        try {
          await LocalNotification(title: title, body: body).show();
        } on Object {
          SystemSound.play(SystemSoundType.alert);
        }
      },
      playSound: (file) async {
        try {
          player ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
          await player!.setVolume(0.45);
          await player!.play(AssetSource(file));
        } on Object {
          // الصوت إضافة، لو ما اشتغل نكمل عادي
        }
      },
      stopSound: () async {
        try {
          await player?.stop();
        } on Object {
          // تجاهل
        }
      },
    );
  }

  // تجهيز الإشعارات مرة وحدة وقت تشغيل البرنامج
  static Future<void> setupWindows() async {
    try {
      await localNotifier.setup(appName: 'Bloom Desk');
    } on Object {
      // لو ما زبطت، التنبيه بيكون صوت ووميض بس
    }
    current = FocusEnvironment.windows();
  }
}
