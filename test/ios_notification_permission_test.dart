import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomatolog/controllers/app_controller.dart';
import 'package:tomatolog/main.dart';
import 'package:tomatolog/services/app_platform_service.dart';
import 'package:tomatolog/services/app_storage.dart';

void main() {
  testWidgets(
    'iOS requests notifications and keeps the guide visible when denied',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('tomatolog/platform');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'notificationStatus') {
          return <String, bool>{
            'granted': false,
            'requested': false,
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

      final controller = AppController(
        MemoryAppStorage(),
        AppPlatformService(),
      );
      await controller.load();
      await tester.pumpWidget(TomatoLogApp(controller: controller));
      await tester.pumpAndSettle();

      expect(calls, contains('requestNotificationPermission'));
      expect(
        find.byKey(const Key('notification-permission-guide')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
