import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';

// التحكم بنافذة البرنامج في ويندوز: فوق كل البرامج، والحجم، والوميض
//
// نكلّم ويندوز مباشرة (user32.dll). وكل شي هنا ما يسوي شي على غير ويندوز
// أو لو صار خطأ، عشان البرنامج ما يطيح أبداً بسبب النافذة.
abstract class WindowControls {
  Future<Rect?> bounds();
  Future<void> setBounds(Rect rect);
  Future<void> setAlwaysOnTop(bool onTop);
  Future<void> flash(); // أيقونة البرنامج تومض في شريط المهام
  Future<void> bringToFront();
}

class Win32Window implements WindowControls {
  int _hwnd = 0;

  int get _handle {
    if (_hwnd != 0 && _isWindow(_hwnd) != 0) return _hwnd;
    _hwnd = _findOurWindow();
    return _hwnd;
  }

  @override
  Future<Rect?> bounds() async {
    final hwnd = _safeHandle();
    if (hwnd == 0) return null;
    final rect = calloc<_Rect>();
    try {
      if (_getWindowRect(hwnd, rect) == 0) return null;
      return Rect.fromLTRB(
        rect.ref.left.toDouble(),
        rect.ref.top.toDouble(),
        rect.ref.right.toDouble(),
        rect.ref.bottom.toDouble(),
      );
    } finally {
      calloc.free(rect);
    }
  }

  @override
  Future<void> setBounds(Rect r) async {
    final hwnd = _safeHandle();
    if (hwnd == 0) return;
    _moveWindow(
      hwnd,
      r.left.round(),
      r.top.round(),
      r.width.round(),
      r.height.round(),
      1,
    );
  }

  @override
  Future<void> setAlwaysOnTop(bool onTop) async {
    final hwnd = _safeHandle();
    if (hwnd == 0) return;
    const swpNoMove = 0x0002, swpNoSize = 0x0001;
    _setWindowPos(hwnd, onTop ? -1 : -2, 0, 0, 0, 0, swpNoMove | swpNoSize);
  }

  @override
  Future<void> flash() async {
    final hwnd = _safeHandle();
    if (hwnd == 0) return;
    final info = calloc<_FlashInfo>();
    try {
      info.ref
        ..cbSize = sizeOf<_FlashInfo>()
        ..hwnd = hwnd
        ..dwFlags =
            0x3 |
            0xC // FLASHW_ALL | FLASHW_TIMERNOFG: يومض لين ترجع للنافذة
        ..uCount = 0
        ..dwTimeout = 0;
      _flashWindowEx(info);
    } finally {
      calloc.free(info);
    }
  }

  @override
  Future<void> bringToFront() async {
    final hwnd = _safeHandle();
    if (hwnd == 0) return;
    const swRestore = 9;
    if (_isIconic(hwnd) != 0) _showWindow(hwnd, swRestore);
    _setForegroundWindow(hwnd);
  }

  int _safeHandle() {
    if (!Platform.isWindows) return 0;
    try {
      return _handle;
    } on Object {
      return 0;
    }
  }

  // ندوّر على نوافذ Flutter، ونختار اللي تتبع هالبرنامج (مو نافذة ثانية)
  static int _findOurWindow() {
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final pid = calloc<Uint32>();
    try {
      final ours = _getCurrentProcessId();
      var hwnd = 0;
      while (true) {
        hwnd = _findWindowEx(0, hwnd, className, nullptr);
        if (hwnd == 0) return 0;
        _getWindowThreadProcessId(hwnd, pid);
        if (pid.value == ours) return hwnd;
      }
    } finally {
      calloc.free(className);
      calloc.free(pid);
    }
  }
}

// نافذة وهمية للاختبارات وغير ويندوز
class NoWindowControls implements WindowControls {
  @override
  Future<Rect?> bounds() async => null;
  @override
  Future<void> setBounds(Rect rect) async {}
  @override
  Future<void> setAlwaysOnTop(bool onTop) async {}
  @override
  Future<void> flash() async {}
  @override
  Future<void> bringToFront() async {}
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _FlashInfo extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int uCount;
  @Uint32()
  external int dwTimeout;
}

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _findWindowEx = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowExW');
final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
final _getCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
final _isWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindow');
final _isIconic = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final _showWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'ShowWindow',
    );
final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );
final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_Rect>),
      int Function(int, Pointer<_Rect>)
    >('GetWindowRect');
final _moveWindow = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32),
      int Function(int, int, int, int, int, int)
    >('MoveWindow');
final _setWindowPos = _user32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(int, int, int, int, int, int, int)
    >('SetWindowPos');
final _flashWindowEx = _user32
    .lookupFunction<
      Int32 Function(Pointer<_FlashInfo>),
      int Function(Pointer<_FlashInfo>)
    >('FlashWindowEx');
