import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../ui/ui_helpers.dart';

class AppPlatformService {
  static const _channel = MethodChannel('tomatolog/platform');
  final _iconCache = <String, Uint8List>{};

  Future<void> listenForNotificationActions(VoidCallback onStop) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopTimer') onStop();
    });
    if (await _invoke<String>('consumeNotificationAction') == 'stopTimer') {
      onStop();
    }
  }

  Future<void> requestNotificationPermission() =>
      _invoke<void>('requestNotificationPermission');

  Future<Map<String, bool>> notificationStatus() async {
    final result = await _invoke<Map<Object?, Object?>>('notificationStatus');
    return result?.map(
          (key, value) => MapEntry(key.toString(), value == true),
        ) ??
        const {};
  }

  Future<void> openCompletionNotificationSettings() =>
      _invoke<void>('openCompletionNotificationSettings');

  Future<void> markNotificationSetupGuideShown() =>
      _invoke<void>('markNotificationSetupGuideShown');

  Future<void> markBatteryOptimizationGuideShown() =>
      _invoke<void>('markBatteryOptimizationGuideShown');

  Future<void> showCompletionNotificationTest() =>
      _invoke<void>('showCompletionNotificationTest');

  Future<void> requestBatteryOptimizationExemption() =>
      _invoke<void>('requestBatteryOptimizationExemption');

  Future<String?> pickBackgroundImage() =>
      _invoke<String>('pickBackgroundImage');

  Future<String?> saveBackgroundImage(Uint8List bytes) =>
      _invoke<String>('saveBackgroundImage', bytes);

  Future<bool> exportBackupFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('exportBackupFile', {
            'fileName': fileName,
            'bytes': bytes,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> showTimer({
    required String categoryName,
    required String iconKey,
    required int colorValue,
    required int remainingSeconds,
    required int totalSeconds,
    required bool isInterval,
    required int currentCycle,
    required int cycleCount,
    required int focusSeconds,
    required int intervalSeconds,
  }) async {
    final arguments = <String, Object?>{
      'category': categoryName,
      'remainingSeconds': remainingSeconds,
      'totalSeconds': totalSeconds,
      'color': colorValue,
      'isInterval': isInterval,
      'currentCycle': currentCycle,
      'cycleCount': cycleCount,
      'focusSeconds': focusSeconds,
      'intervalSeconds': intervalSeconds,
    };
    final icon = await _notificationIcon(iconKey);
    await _invoke<void>(
      'showTimer',
      icon == null ? arguments : {...arguments, 'icon': icon},
    );
  }

  Future<void> cancelTimer() => _invoke<void>('cancelTimer');

  Future<void> completeTimer() => _invoke<void>('completeTimer');

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('Android platform call $method failed: $error');
      return null;
    }
  }

  Future<Uint8List?> _notificationIcon(String key) async {
    final cached = _iconCache[key];
    if (cached != null) return cached;
    try {
      const size = 96;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (isIconifyIcon(key)) {
        final info = await vg.loadPicture(
          SvgNetworkLoader(
            iconifySvgUrl(key),
            theme: const SvgTheme(currentColor: Colors.white),
          ),
          null,
        );
        final scale = size / info.size.longestSide;
        canvas
          ..translate(
            (size - info.size.width * scale) / 2,
            (size - info.size.height * scale) / 2,
          )
          ..scale(scale)
          ..drawPicture(info.picture);
        info.picture.dispose();
      } else {
        final icon = categoryIcon(key);
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              color: Colors.white,
              fontSize: 72,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
            ),
          ),
        )..layout();
        painter.paint(
          canvas,
          Offset((size - painter.width) / 2, (size - painter.height) / 2),
        );
      }
      final image = await recorder.endRecording().toImage(size, size);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      return _iconCache[key] = data.buffer.asUint8List();
    } on Object catch (error) {
      debugPrint('Category notification icon failed: $error');
      return null;
    }
  }
}
