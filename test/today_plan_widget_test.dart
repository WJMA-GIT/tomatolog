import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/controllers/app_controller.dart';
import 'package:tomatolog/main.dart';
import 'package:tomatolog/services/app_platform_service.dart';
import 'package:tomatolog/services/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tomatolog/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'widget actions preserve stop actions and handle cold and hot opens',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'consumeWidgetPlanAction') return 'cold-plan';
        if (call.method == 'consumeNotificationAction') return 'stopTimer';
        return null;
      });
      final opened = <String>[];
      var stops = 0;
      await AppPlatformService().listenForNotificationActions(
        () => stops++,
        onOpenPlan: opened.add,
      );
      expect(opened, ['cold-plan']);
      expect(stops, 1);
      for (final call in [
        const MethodCall('openPlanTimer', 'hot-plan'),
        const MethodCall('stopTimer'),
      ]) {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(call),
          (_) {},
        );
      }
      expect(opened, ['cold-plan', 'hot-plan']);
      expect(stops, 2);
    },
  );

  test(
    'plan opens configure the exact duration without changing presets or running timers',
    () async {
      final storage = MemoryAppStorage();
      final controller = AppController(storage);
      await controller.load();
      final now = DateTime.now();
      controller.addPlan(
        startDate: now,
        endDate: now,
        categoryId: 'study',
        plannedMinutes: 125,
      );
      controller.selectTimerPreset(0);
      final oldPreset = controller.timerPresets.first.toJson();
      expect(controller.preparePlanTimer(controller.plans.single.id), isTrue);
      expect(controller.selectedCategoryId, 'study');
      expect(controller.plannedMinutes, 125);
      expect(controller.remainingSeconds, 7500);
      expect(controller.cycleCount, 1);
      expect(controller.groupCount, 1);
      expect(controller.intervalMinutes, 0);
      expect(controller.longIntervalMinutes, 0);
      expect(controller.recordIntervals, isFalse);
      expect(controller.activeTimerPresetIndex, isNull);
      expect(controller.timerPresets.first.toJson(), oldPreset);
      await Future<void>.delayed(Duration.zero);
      final restored = AppController(storage);
      await restored.load();
      expect(restored.plannedMinutes, 125);
      controller.startTimer();
      final remaining = controller.remainingSeconds;
      controller.openPlanTimer(controller.plans.single.id);
      expect(controller.phase, TimerPhase.running);
      expect(controller.remainingSeconds, remaining);
      expect(controller.widgetTimerNavigationRevision, 1);
      controller.dispose();
      restored.dispose();
    },
  );

  test(
    'widget data refreshes after load, plan completion and deletion without logs or secrets',
    () async {
      final payloads = <Map<String, dynamic>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'updateTodayPlanWidget') {
          payloads.add(
            jsonDecode(call.arguments as String) as Map<String, dynamic>,
          );
        }
        return null;
      });
      final controller = AppController(
        MemoryAppStorage(),
        AppPlatformService(),
      );
      await controller.load();
      expect(payloads.single.keys.toSet(), {
        'plans',
        'categories',
        'themePreference',
        'accentColorValue',
      });
      controller.setThemePreference(AppThemePreference.dark);
      controller.setAccentColor(0xFF4169C1);
      await Future<void>.delayed(Duration.zero);
      expect(payloads.last['themePreference'], 'dark');
      expect(payloads.last['accentColorValue'], 0xFF4169C1);
      final now = DateTime.now();
      controller.addPlan(
        startDate: now,
        endDate: now,
        categoryId: 'work',
        plannedMinutes: 25,
      );
      await Future<void>.delayed(Duration.zero);
      final id = controller.plans.single.id;
      expect((payloads.last['plans'] as List).length, 1);
      controller.setPlanCompleted(id, now, true);
      await Future<void>.delayed(Duration.zero);
      expect(
        (payloads.last['plans'] as List).single['completedDates'],
        isNotEmpty,
      );
      final backup = await controller.exportPortableData();
      controller.deletePlan(id);
      await Future<void>.delayed(Duration.zero);
      expect(payloads.last['plans'], isEmpty);
      expect(controller.preparePlanTimer(id), isFalse);
      await controller.importPortableData(backup);
      expect((payloads.last['plans'] as List).single['id'], id);
      controller.dispose();
    },
  );

  test('rejects expired plans and archived categories', () async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    controller.addPlan(
      startDate: yesterday,
      endDate: yesterday,
      categoryId: 'work',
      plannedMinutes: 25,
    );
    expect(controller.preparePlanTimer(controller.plans.single.id), isFalse);
    final now = DateTime.now();
    controller.addPlan(
      startDate: now,
      endDate: now,
      categoryId: 'study',
      plannedMinutes: 25,
    );
    final today = controller.plans.last;
    controller.setCategoryArchived(controller.categoryById('study')!, true);
    expect(controller.preparePlanTimer(today.id), isFalse);
    controller.dispose();
  });

  testWidgets('a hot widget action opens the configured timer tab', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();
    final now = DateTime.now();
    controller.addPlan(
      startDate: now,
      endDate: now,
      categoryId: 'study',
      plannedMinutes: 45,
    );
    await tester.pumpWidget(TomatoLogApp(controller: controller));
    await tester.tap(find.text('日志'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    controller.openPlanTimer(controller.plans.single.id);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(controller.selectedCategoryId, 'study');
    expect(find.text('45:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
