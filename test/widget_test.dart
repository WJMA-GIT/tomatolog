import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tomato/controllers/app_controller.dart';
import 'package:time_tomato/main.dart';
import 'package:time_tomato/screens/categories_screen.dart';
import 'package:time_tomato/screens/home_shell.dart';
import 'package:time_tomato/screens/timer_screen.dart';
import 'package:time_tomato/services/app_platform_service.dart';
import 'package:time_tomato/services/app_storage.dart';

void main() {
  testWidgets('shows the timer and navigates to categories', (tester) async {
    const channel = MethodChannel('time_tomato/platform');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'notificationStatus') {
        return <String, bool>{'granted': true};
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

    await tester.pumpWidget(TimeTomatoApp(controller: controller));
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
    const channel = MethodChannel('time_tomato/platform');
    var granted = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'requestNotificationPermission') granted = true;
      if (call.method == 'notificationStatus') {
        return <String, bool>{'granted': granted};
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

    await tester.pumpWidget(TimeTomatoApp(controller: controller));
    await tester.pumpAndSettle();

    final guide = find.byKey(const Key('notification-permission-guide'));
    expect(guide, findsOneWidget);
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
}
