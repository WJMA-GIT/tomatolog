import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/controllers/app_controller.dart';
import 'package:tomatolog/main.dart';
import 'package:tomatolog/screens/categories_screen.dart';
import 'package:tomatolog/screens/home_shell.dart';
import 'package:tomatolog/screens/timer_screen.dart';
import 'package:tomatolog/services/app_platform_service.dart';
import 'package:tomatolog/services/app_storage.dart';

void main() {
  testWidgets('shows the timer and navigates to categories', (tester) async {
    const channel = MethodChannel('tomatolog/platform');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'notificationStatus') {
        return <String, bool>{
          'granted': true,
          'setupGuideShown': true,
          'batteryUnrestricted': true,
        };
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
    controller.setThemePreference(AppThemePreference.light);

    await tester.pumpWidget(TomatoLogApp(controller: controller));
    await tester.pumpAndSettle();

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 2);
    expect(
      navigationBar.destinations.cast<NavigationDestination>().map(
        (destination) => destination.label,
      ),
      ['今天', '日志', '计时', '统计', '分类'],
    );
    expect(find.text('专注计时'), findsOneWidget);
    expect(find.text('工作'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFFF7F7F7),
      ),
      findsOneWidget,
    );
    expect(calls.any((call) => call.method == 'notificationStatus'), isTrue);
    expect(find.text('开启通知提醒'), findsNothing);

    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();

    expect(find.text('新建分类'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();

    expect(find.text('日历与统计'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('notification permission guide blocks the app until granted', (
    tester,
  ) async {
    const channel = MethodChannel('tomatolog/platform');
    var granted = false;
    var requested = false;
    var setupGuideShown = false;
    var requestCount = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'requestNotificationPermission') {
        requested = true;
        requestCount++;
        if (requestCount > 1) granted = true;
      }
      if (call.method == 'notificationStatus') {
        return <String, bool>{
          'granted': granted,
          'requested': requested,
          'setupGuideShown': setupGuideShown,
        };
      }
      if (call.method == 'markNotificationSetupGuideShown') {
        setupGuideShown = true;
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

    await tester.pumpWidget(TomatoLogApp(controller: controller));
    await tester.pumpAndSettle();

    final guide = find.byKey(const Key('notification-permission-guide'));
    expect(guide, findsOneWidget);
    expect(requestCount, 1);
    expect(
      (tester.getCenter(guide) - tester.getCenter(find.byType(HomeShell)))
          .distance,
      lessThan(40),
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(guide, findsOneWidget);

    await tester.tap(find.text('去开启'));
    await tester.pumpAndSettle();
    expect(guide, findsNothing);
    expect(find.byKey(const Key('notification-setup-guide')), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-setup-guide')), findsNothing);
    expect(find.byKey(const Key('battery-optimization-guide')), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('notification guide refreshes after returning from settings', (
    tester,
  ) async {
    const channel = MethodChannel('tomatolog/platform');
    var granted = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'notificationStatus') {
        return <String, bool>{
          'granted': granted,
          'requested': true,
          'setupGuideShown': true,
        };
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

    await tester.pumpWidget(TomatoLogApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-permission-guide')),
      findsOneWidget,
    );

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-permission-guide')),
      findsNothing,
    );
    controller.dispose();
  });

  testWidgets('guides OEM notification settings and tests after return', (
    tester,
  ) async {
    const channel = MethodChannel('tomatolog/platform');
    var setupGuideShown = false;
    var settingsOpened = 0;
    var testsSent = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'notificationStatus') {
        return <String, bool>{
          'granted': true,
          'setupGuideShown': setupGuideShown,
        };
      }
      if (call.method == 'markNotificationSetupGuideShown') {
        setupGuideShown = true;
      }
      if (call.method == 'openCompletionNotificationSettings') {
        settingsOpened++;
      }
      if (call.method == 'showCompletionNotificationTest') testsSent++;
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

    await tester.pumpWidget(TomatoLogApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-setup-guide')), findsOneWidget);

    await tester.tap(find.text('去检查'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(find.byKey(const Key('notification-setup-guide')), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(testsSent, 1);
    controller.dispose();
  });

  testWidgets('guides battery optimization after notification setup', (
    tester,
  ) async {
    const channel = MethodChannel('tomatolog/platform');
    var batteryGuideShown = false;
    var exemptionRequests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'notificationStatus') {
        return <String, bool>{
          'granted': true,
          'setupGuideShown': true,
          'batteryUnrestricted': false,
          'batteryGuideShown': batteryGuideShown,
        };
      }
      if (call.method == 'markBatteryOptimizationGuideShown') {
        batteryGuideShown = true;
      }
      if (call.method == 'requestBatteryOptimizationExemption') {
        exemptionRequests++;
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

    await tester.pumpWidget(TomatoLogApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('battery-optimization-guide')), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(exemptionRequests, 1);
    expect(find.byKey(const Key('battery-optimization-guide')), findsNothing);
    controller.dispose();
  });

  testWidgets('expands category hierarchy and offers icon and color pickers', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage(), AppPlatformService());
    await controller.load();
    controller.addCategory(
      name: '子任务',
      colorValue: 0xFF81C784,
      iconKey: 'code',
      parentId: 'work',
    );

    await tester.pumpWidget(
      MaterialApp(home: CategoriesScreen(controller: controller)),
    );

    expect(find.text('子任务'), findsOneWidget);
    await tester.tap(find.text('工作'));
    await tester.pump();
    expect(find.text('子任务'), findsNothing);

    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    expect(find.text('红色系'), findsNothing);
    expect(find.text('墨绿色系'), findsNothing);
    expect(find.text('在线搜索 Iconify'), findsOneWidget);
    expect(find.text('自定义色盘'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    Finder workIcon(Color color) => find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.work_rounded &&
            widget.color == color,
      ),
    );
    expect(workIcon(const Color(0xFFFFB4AB)), findsOneWidget);
    final secondColor = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color ==
                const Color(0xFFE85D4A),
      ),
    );
    await tester.tap(secondColor);
    await tester.pump();
    expect(workIcon(const Color(0xFFE85D4A)), findsOneWidget);
    await tester.ensureVisible(find.text('在线搜索 Iconify'));
    await tester.tap(find.text('在线搜索 Iconify'));
    await tester.pumpAndSettle();
    expect(find.text('搜索 Iconify，例如 run'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('自定义色盘'));
    await tester.tap(find.text('自定义色盘'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPickerHueRing), findsOneWidget);
    expect(find.byType(ColorPickerArea), findsOneWidget);
    controller.dispose();
  });

  testWidgets('timer dial uses a 60 minute scale and follows circular drag', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) =>
              Scaffold(body: TimerScreen(controller: controller)),
        ),
      ),
    );

    CircularProgressIndicator ring() =>
        tester.widget(find.byType(CircularProgressIndicator));
    expect(controller.plannedMinutes, 25);
    expect(ring().value, closeTo(25 / 60, 0.001));

    final center = tester.getCenter(find.byType(CircularProgressIndicator));
    final gesture = await tester.startGesture(center + const Offset(0, -100));
    await gesture.moveTo(center + const Offset(100, 0));
    await gesture.up();
    await tester.pump();

    expect(controller.plannedMinutes, 15);
    expect(find.text('15:00'), findsOneWidget);
    expect(ring().value, closeTo(15 / 60, 0.001));
    controller.dispose();
  });

  testWidgets('configures timer cycles and interval statistics', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) =>
              Scaffold(body: TimerScreen(controller: controller)),
        ),
      ),
    );

    await tester.ensureVisible(find.byTooltip('增加循环次数'));
    await tester.tap(find.byTooltip('增加循环次数'));
    await tester.pump();
    expect(controller.groupCount, 2);
    expect(find.text('长休息时间'), findsOneWidget);

    await tester.ensureVisible(find.text('间隔计入统计'));
    await tester.tap(find.text('间隔计入统计'));
    await tester.pump();
    expect(controller.recordIntervals, isTrue);

    await tester.ensureVisible(find.text('悬浮倒计时'));
    await tester.tap(find.text('悬浮倒计时'));
    await tester.pump();
    expect(controller.floatingTimerEnabled, isTrue);
    controller.dispose();
  });
}
