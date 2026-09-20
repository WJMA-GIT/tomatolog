import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/controllers/app_controller.dart';
import 'package:tomatolog/services/app_platform_service.dart';
import 'package:tomatolog/services/app_storage.dart';
import 'package:tomatolog/widgets/landscape_timer_mode.dart';

void main() {
  testWidgets('landscape running timer hides the clock for burn-in breaks', (
    tester,
  ) async {
    const channel = MethodChannel('tomatolog/platform');
    final keepScreenOn = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setKeepScreenOn') {
        keepScreenOn.add(call.arguments as bool);
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    final controller = AppController(MemoryAppStorage(), AppPlatformService());
    await controller.load();
    controller.startTimer();
    debugPaintBaselinesEnabled = true;
    addTearDown(() => debugPaintBaselinesEnabled = false);
    final size = ValueNotifier(const Size(800, 400));
    addTearDown(size.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: size,
          builder: (_, value, _) => MediaQuery(
            data: MediaQueryData(size: value),
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, _) => LandscapeTimerMode(
                controller: controller,
                displayDuration: const Duration(milliseconds: 10),
                blackoutDuration: const Duration(milliseconds: 5),
                child: const Text('普通页面'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('landscape-timer-clock')), findsOneWidget);
    expect(debugPaintBaselinesEnabled, isFalse);
    expect(
      find.ancestor(of: find.byType(Text), matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('landscape-timer-clock')))
          .style
          ?.fontSize,
      320,
    );
    final modeCenter = tester.getCenter(
      find.byKey(const Key('landscape-timer-mode')),
    );
    final clockCenter = tester.getCenter(
      find.byKey(const Key('landscape-timer-clock')),
    );
    expect(clockCenter.dx, closeTo(modeCenter.dx, 0.01));
    expect(clockCenter.dy, closeTo(modeCenter.dy, 0.01));
    expect(keepScreenOn, [true]);

    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(const Key('landscape-timer-blackout')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 5));
    expect(find.byKey(const Key('landscape-timer-clock')), findsOneWidget);

    size.value = const Size(400, 800);
    await tester.pump();
    await tester.pump();
    expect(find.text('普通页面'), findsOneWidget);
    expect(keepScreenOn, [true, false]);

    size.value = const Size(800, 400);
    await tester.pump();
    await tester.pump();
    expect(keepScreenOn, [true, false, true]);

    controller.stopTimer(saveInterrupted: false);
    await tester.pump();
    await tester.pump();
    expect(find.text('普通页面'), findsOneWidget);
    expect(keepScreenOn, [true, false, true, false]);
    controller.dispose();
  });

  testWidgets('portrait running timer stays on the normal page', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();
    controller.startTimer();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: LandscapeTimerMode(
            controller: controller,
            child: const Text('普通页面'),
          ),
        ),
      ),
    );

    expect(find.text('普通页面'), findsOneWidget);
    expect(find.byKey(const Key('landscape-timer-mode')), findsNothing);
    controller.dispose();
  });
}
