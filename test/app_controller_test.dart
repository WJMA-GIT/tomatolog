import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/controllers/app_controller.dart';
import 'package:tomatolog/models/daily_plan.dart';
import 'package:tomatolog/models/time_log.dart';
import 'package:tomatolog/services/app_platform_service.dart';
import 'package:tomatolog/services/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads defaults and persists a manual time log', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();

    expect(controller.activeCategories.length, 4);
    expect(controller.selectedCategoryId, 'work');

    controller.addCategory(
      name: '写作',
      colorValue: 0xFF123456,
      iconKey: 'creative',
    );
    controller.addManualLog(
      categoryId: controller.categories.last.id,
      minutes: 30,
      note: '完成文章初稿',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs.single.actualSeconds, 1800);
    expect(controller.logs.single.note, '完成文章初稿');
    expect(storage.value, isNotNull);
    controller.dispose();
  });

  test('can start and discard a timer', () async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();

    controller.startTimer();
    expect(controller.phase, TimerPhase.running);

    controller.stopTimer(saveInterrupted: false);
    expect(controller.phase, TimerPhase.idle);
    expect(controller.logs, isEmpty);
    controller.dispose();
  });

  test(
    'runs configured focus cycles and optionally records intervals',
    () async {
      final controller = AppController(MemoryAppStorage());
      await controller.load();
      controller
        ..setPlannedMinutes(1)
        ..setCycleCount(2)
        ..setIntervalMinutes(1)
        ..startTimer();

      controller.completeCurrentPhaseForTesting();
      expect(controller.phase, TimerPhase.interval);
      expect(controller.currentCycle, 1);
      expect(controller.logs, hasLength(1));

      controller.completeCurrentPhaseForTesting();
      expect(controller.phase, TimerPhase.running);
      expect(controller.currentCycle, 2);
      expect(controller.logs, hasLength(1));

      controller.completeCurrentPhaseForTesting();
      expect(controller.phase, TimerPhase.idle);
      expect(controller.logs, hasLength(2));
      expect(controller.logs.every((log) => log.note == null), isTrue);
      controller.dispose();

      final recorded = AppController(MemoryAppStorage());
      await recorded.load();
      recorded
        ..setPlannedMinutes(1)
        ..setCycleCount(2)
        ..setIntervalMinutes(1)
        ..setRecordIntervals(true)
        ..startTimer();
      recorded.completeCurrentPhaseForTesting();
      recorded.completeCurrentPhaseForTesting();
      recorded.completeCurrentPhaseForTesting();

      expect(recorded.logs, hasLength(3));
      expect(
        recorded.logs.where((log) => log.kind == LogKind.interval),
        hasLength(1),
      );
      expect(
        recorded.logs.fold<int>(0, (sum, log) => sum + log.actualSeconds),
        3 * 60,
      );
      recorded.dispose();
    },
  );

  test(
    'recorded intervals count in statistics but not daily plan progress',
    () async {
      final controller = AppController(MemoryAppStorage());
      await controller.load();
      final today = DateTime.now();
      controller.addPlan(
        startDate: today,
        endDate: today,
        categoryId: 'work',
        plannedMinutes: 2,
      );
      controller
        ..setPlannedMinutes(1)
        ..setCycleCount(2)
        ..setIntervalMinutes(1)
        ..setRecordIntervals(true)
        ..startTimer();

      controller.completeCurrentPhaseForTesting();
      controller.completeCurrentPhaseForTesting();
      expect(controller.logs, hasLength(2));
      expect(controller.plans.single.isCompletedOn(today), isFalse);

      controller.completeCurrentPhaseForTesting();
      expect(controller.plans.single.isCompletedOn(today), isTrue);
      expect(
        controller.logs.fold<int>(0, (sum, log) => sum + log.actualSeconds),
        3 * 60,
      );
      controller.dispose();
    },
  );

  test('persists cycle settings', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();
    controller
      ..setCycleCount(4)
      ..setIntervalMinutes(8)
      ..setRecordIntervals(true);
    await Future<void>.delayed(Duration.zero);

    final restored = AppController(storage);
    await restored.load();
    expect(restored.cycleCount, 4);
    expect(restored.intervalMinutes, 8);
    expect(restored.recordIntervals, isTrue);
    controller.dispose();
    restored.dispose();
  });

  test('restores across elapsed focus and interval phases', () async {
    final storage = MemoryAppStorage();
    final initial = AppController(storage);
    await initial.load();
    await Future<void>.delayed(Duration.zero);
    initial.dispose();

    final now = DateTime.now();
    storage.value!
      ..['plannedMinutes'] = 1
      ..['cycleCount'] = 3
      ..['intervalMinutes'] = 1
      ..['recordIntervals'] = true
      ..['timer'] = {
        'phase': 'running',
        'remainingSeconds': 0,
        'sessionStartedAt': now
            .subtract(const Duration(seconds: 130))
            .toIso8601String(),
        'targetEndAt': now
            .subtract(const Duration(seconds: 70))
            .toIso8601String(),
        'currentCycle': 1,
      };

    final restored = AppController(storage);
    await restored.load();
    expect(restored.phase, TimerPhase.running);
    expect(restored.currentCycle, 2);
    expect(restored.remainingSeconds, inInclusiveRange(49, 50));
    expect(restored.logs, hasLength(2));
    expect(
      restored.logs.where((log) => log.kind == LogKind.interval),
      hasLength(1),
    );
    restored.stopTimer(saveInterrupted: false);
    restored.dispose();
  });

  test('restores a legacy paused timer as running', () async {
    final storage = MemoryAppStorage();
    final initial = AppController(storage);
    await initial.load();
    await Future<void>.delayed(Duration.zero);
    initial.dispose();

    final data = storage.value!;
    data['timer'] = {
      'phase': 'paused',
      'remainingSeconds': 20 * 60,
      'sessionStartedAt': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'targetEndAt': null,
    };
    final restored = AppController(storage);
    await restored.load();

    expect(restored.phase, TimerPhase.running);
    expect(restored.remainingSeconds, inInclusiveRange(1199, 1200));
    restored.stopTimer(saveInterrupted: false);
    restored.dispose();
  });

  test('idle timer opens at the 25 minute default', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();
    controller.setPlannedMinutes(45);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();

    final restored = AppController(storage);
    await restored.load();
    expect(restored.plannedMinutes, 25);
    restored.dispose();
  });

  test('load is idempotent and recovers from invalid stored data', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);

    await controller.load();
    await controller.load();
    expect(controller.categories, hasLength(4));

    storage.value = {'categories': 'invalid'};
    await controller.load();

    expect(controller.categories, hasLength(4));
    expect(controller.selectedCategoryId, 'work');
    expect(controller.phase, TimerPhase.idle);
    controller.dispose();
  });

  test('rejects invalid selections and manual logs', () async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();

    controller.selectCategory('missing');
    controller.setPlannedMinutes(0);
    controller.addCategory(
      name: '   ',
      colorValue: 0xFF123456,
      iconKey: 'work',
    );
    controller.addManualLog(categoryId: 'missing', minutes: 25);
    controller.addManualLog(categoryId: 'work', minutes: 0);

    expect(controller.selectedCategoryId, 'work');
    expect(controller.plannedMinutes, 25);
    expect(controller.categories, hasLength(4));
    expect(controller.logs, isEmpty);
    controller.dispose();
  });

  test('generates unique IDs for rapid consecutive changes', () async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();

    controller.addCategory(
      name: '分类一',
      colorValue: 0xFF123456,
      iconKey: 'work',
    );
    controller.addCategory(
      name: '分类二',
      colorValue: 0xFF654321,
      iconKey: 'study',
    );

    final ids = controller.categories.map((category) => category.id).toSet();
    expect(ids, hasLength(controller.categories.length));
    controller.dispose();
  });

  test('persists and completes a daily plan', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();

    controller.addPlan(
      startDate: DateTime(2026, 7, 30),
      endDate: DateTime(2026, 8, 2),
      categoryId: 'work',
      plannedMinutes: 45,
    );
    controller.setPlanCompleted(
      controller.plans.single.id,
      DateTime(2026, 7, 31),
      true,
    );
    await Future<void>.delayed(Duration.zero);

    final restored = AppController(storage);
    await restored.load();
    expect(restored.plans.single.occursOn(DateTime(2026, 8, 2)), isTrue);
    expect(restored.plans.single.occursOn(DateTime(2026, 8, 3)), isFalse);
    expect(restored.plans.single.isCompletedOn(DateTime(2026, 7, 31)), isTrue);
    expect(restored.plans.single.plannedMinutes, 45);
    expect(restored.logs.single.actualSeconds, 45 * 60);
    controller.dispose();
    restored.dispose();
  });

  test('migrates old plan time ranges to target minutes', () {
    final plan = DailyPlan.fromJson({
      'id': 'old-plan',
      'startDate': '2026-07-31T00:00:00.000',
      'endDate': '2026-08-02T00:00:00.000',
      'categoryId': 'work',
      'startMinute': 9 * 60,
      'endMinute': 9 * 60 + 45,
    });

    expect(plan.plannedMinutes, 45);
    expect(plan.toJson(), isNot(contains('startMinute')));
  });

  test('persists the selected accent color', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();

    controller.setAccentColor(0xFF4169C1);
    await Future<void>.delayed(Duration.zero);

    final restored = AppController(storage);
    await restored.load();
    expect(restored.accentColorValue, 0xFF4169C1);
    controller.dispose();
    restored.dispose();
  });

  test('persists category hierarchy and prevents cycles', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();

    controller.addCategory(
      name: '健身',
      colorValue: 0xFF19A974,
      iconKey: 'exercise',
      parentId: 'exercise',
    );
    final fitness = controller.categories.last;
    controller.addCategory(
      name: '力量',
      colorValue: 0xFF19A974,
      iconKey: 'exercise',
      parentId: fitness.id,
    );
    final strength = controller.categories.last;

    expect(controller.categoryPath(strength), '运动 / 健身 / 力量');
    expect(controller.categoryDepth(strength), 2);
    controller.updateCategory(
      controller.categoryById('exercise')!,
      name: '运动',
      colorValue: 0xFF19A974,
      iconKey: 'exercise',
      parentId: strength.id,
    );
    expect(controller.categoryById('exercise')!.parentId, isNull);

    expect(
      controller.setCategoryArchived(
        controller.categoryById('exercise')!,
        true,
      ),
      isTrue,
    );
    expect(controller.categoryById(fitness.id)!.isArchived, isTrue);
    expect(controller.setCategoryArchived(strength, false), isTrue);
    expect(controller.categoryById('exercise')!.isArchived, isFalse);
    await Future<void>.delayed(Duration.zero);

    final restored = AppController(storage);
    await restored.load();
    expect(
      restored.categoryPath(restored.categoryById(strength.id)!),
      '运动 / 健身 / 力量',
    );
    controller.dispose();
    restored.dispose();
  });

  test('deleting a category cascades to children, logs and plans', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(storage);
    await controller.load();

    controller.addCategory(
      name: '健身',
      colorValue: 0xFF19A974,
      iconKey: 'exercise',
      parentId: 'exercise',
    );
    final fitness = controller.categories.last;
    controller.addManualLog(categoryId: fitness.id, minutes: 20);
    controller.addPlan(
      startDate: DateTime(2026, 7, 31),
      endDate: DateTime(2026, 8, 2),
      categoryId: fitness.id,
      plannedMinutes: 60,
    );

    expect(
      controller.deleteCategory(controller.categoryById('exercise')!),
      isTrue,
    );
    expect(controller.categoryById('exercise'), isNull);
    expect(controller.categoryById(fitness.id), isNull);
    expect(controller.logs, isEmpty);
    expect(controller.plans, isEmpty);
    await Future<void>.delayed(Duration.zero);

    final restored = AppController(storage);
    await restored.load();
    expect(restored.categoryById('exercise'), isNull);
    expect(restored.logs, isEmpty);
    expect(restored.plans, isEmpty);
    controller.dispose();
    restored.dispose();
  });

  test('daily logs automatically complete a plan target', () async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();
    final today = DateTime.now();
    controller.addPlan(
      startDate: today,
      endDate: today.add(const Duration(days: 2)),
      categoryId: 'work',
      plannedMinutes: 25,
    );
    final plan = controller.plans.single;

    controller.addManualLog(categoryId: 'work', minutes: 10);
    expect(plan.isCompletedOn(today), isFalse);
    controller.addManualLog(categoryId: 'work', minutes: 15);
    expect(controller.plans.single.isCompletedOn(today), isTrue);

    controller.deleteLog(controller.logs.first.id);
    expect(controller.plans.single.isCompletedOn(today), isFalse);
    controller.dispose();
  });

  test(
    'unchecking a manually completed plan removes its generated log',
    () async {
      final controller = AppController(MemoryAppStorage());
      await controller.load();
      final today = DateTime.now();
      controller.addPlan(
        startDate: today,
        endDate: today,
        categoryId: 'work',
        plannedMinutes: 25,
      );
      final id = controller.plans.single.id;

      controller.setPlanCompleted(id, today, true);
      expect(controller.logs, hasLength(1));
      expect(controller.plans.single.isCompletedOn(today), isTrue);
      controller.setPlanCompleted(id, today, false);
      expect(controller.logs, isEmpty);
      expect(controller.plans.single.isCompletedOn(today), isFalse);
      controller.dispose();
    },
  );

  test(
    'sends category and countdown to the Android notification bridge',
    () async {
      const channel = MethodChannel('tomatolog/platform');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = AppController(
        MemoryAppStorage(),
        AppPlatformService(),
      );
      await controller.load();
      controller.startTimer();
      await pumpEventQueue(times: 20);

      expect(calls.where((call) => call.method == 'showTimer'), hasLength(1));
      final show = calls.lastWhere((call) => call.method == 'showTimer');
      final arguments = (show.arguments as Map).cast<String, Object?>();
      expect(arguments['category'], '工作');
      expect(arguments['remainingSeconds'], 25 * 60);
      expect(arguments['totalSeconds'], 25 * 60);
      expect(arguments['isInterval'], isFalse);
      expect(arguments['currentCycle'], 1);
      expect(arguments['cycleCount'], 1);
      expect(arguments['focusSeconds'], 25 * 60);
      expect(arguments['intervalSeconds'], 5 * 60);
      expect(arguments, isNot(contains('isRunning')));
      expect(arguments['icon'], isNotNull);

      await controller.requestBatteryOptimizationExemption();
      expect(calls.last.method, 'requestBatteryOptimizationExemption');
      controller.dispose();
    },
  );
}
