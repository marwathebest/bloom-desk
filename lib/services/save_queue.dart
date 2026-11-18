import 'dart:async';

// طابور الحفظ: كل عملية حفظ تنتظر اللي قبلها تخلص
//
// لو أضفت مشروعين ورا بعض بسرعة، بدون الطابور كانت العمليتين تقرأ القائمة
// بنفس اللحظة، وآخر وحدة تحفظ تمسح اللي أضافته الأولى.
class SaveQueue {
  SaveQueue();

  // المشاريع والجلسات في نفس الملف، فلازم يمشون في نفس الطابور
  static final shared = SaveQueue();

  bool _busy = false;
  final List<void Function()> _waiting = [];

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    void start() {
      _busy = true;
      Future<T>.sync(action)
          .then(completer.complete, onError: completer.completeError)
          .whenComplete(() {
            _busy = false;
            if (_waiting.isNotEmpty) _waiting.removeAt(0)();
          });
    }

    if (_busy) {
      _waiting.add(start);
    } else {
      start();
    }
    return completer.future;
  }

  // للاختبارات: كل اختبار يبدأ بطابور فاضي
  void reset() {
    _busy = false;
    _waiting.clear();
  }
}
