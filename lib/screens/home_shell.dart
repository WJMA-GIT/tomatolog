import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'categories_screen.dart';
import 'insights_screen.dart';
import 'logs_screen.dart';
import 'timer_screen.dart';
import 'today_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 2;
  bool _showNotificationGuide = false;
  bool _showNotificationSetupGuide = false;
  bool _showBatteryOptimizationGuide = false;
  bool _requestingNotificationPermission = false;
  bool _notificationGranted = false;
  bool _testNotificationOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotificationStatus(requestOnFirstOpen: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _handleAppResumed();
  }

  Future<void> _handleAppResumed() async {
    await _refreshNotificationStatus();
    if (!_testNotificationOnResume || !_notificationGranted) return;
    _testNotificationOnResume = false;
    await widget.controller.showCompletionNotificationTest();
  }

  Future<void> _refreshNotificationStatus({
    bool requestOnFirstOpen = false,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final status = await widget.controller.notificationStatus();
    if (!mounted) return;
    // An empty response means the native bridge is unavailable (for example,
    // a widget test), not that the user denied notification access.
    if (status.isEmpty) return;
    final granted = status['granted'] == true;
    setState(() {
      _notificationGranted = granted;
      _showNotificationGuide = !granted;
      _showNotificationSetupGuide =
          granted && status['setupGuideShown'] != true;
      _showBatteryOptimizationGuide =
          granted &&
          status['setupGuideShown'] == true &&
          status['batteryUnrestricted'] != true &&
          status['batteryGuideShown'] != true;
    });
    if (requestOnFirstOpen && !granted && status['requested'] != true) {
      await _requestNotificationPermission();
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_requestingNotificationPermission) return;
    _requestingNotificationPermission = true;
    try {
      await widget.controller.requestNotificationPermission();
      await _refreshNotificationStatus();
    } finally {
      _requestingNotificationPermission = false;
    }
  }

  Future<void> _dismissNotificationSetupGuide() async {
    await widget.controller.markNotificationSetupGuideShown();
    await _refreshNotificationStatus();
  }

  Future<void> _openNotificationSetup() async {
    await widget.controller.markNotificationSetupGuideShown();
    if (!mounted) return;
    setState(() {
      _showNotificationSetupGuide = false;
      _testNotificationOnResume = true;
    });
    await widget.controller.openCompletionNotificationSettings();
  }

  Future<void> _dismissBatteryOptimizationGuide() async {
    await widget.controller.markBatteryOptimizationGuideShown();
    if (mounted) setState(() => _showBatteryOptimizationGuide = false);
  }

  Future<void> _openBatteryOptimizationSetup() async {
    await widget.controller.markBatteryOptimizationGuideShown();
    if (!mounted) return;
    setState(() => _showBatteryOptimizationGuide = false);
    await widget.controller.requestBatteryOptimizationExemption();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final backgroundPath = widget.controller.backgroundImagePath;
        return PopScope(
          canPop:
              !_showNotificationGuide &&
              !_showNotificationSetupGuide &&
              !_showBatteryOptimizationGuide,
          child: Stack(
            children: [
              Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    if (backgroundPath != null)
                      Image.file(
                        File(backgroundPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (backgroundPath != null)
                      ColoredBox(
                        color: Theme.of(context).colorScheme.surface.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.72
                              : 0.82,
                        ),
                      ),
                    SafeArea(
                      bottom: false,
                      child: IndexedStack(
                        index: _index,
                        children: [
                          TodayScreen(controller: widget.controller),
                          LogsScreen(controller: widget.controller),
                          TimerScreen(controller: widget.controller),
                          InsightsScreen(controller: widget.controller),
                          CategoriesScreen(controller: widget.controller),
                        ],
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.today_outlined),
                      selectedIcon: Icon(Icons.today_rounded),
                      label: '今天',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long_rounded),
                      label: '日志',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.timer_outlined),
                      selectedIcon: Icon(Icons.timer_rounded),
                      label: '计时',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights_rounded),
                      label: '统计',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.category_outlined),
                      selectedIcon: Icon(Icons.category_rounded),
                      label: '分类',
                    ),
                  ],
                ),
              ),
              if (_showNotificationGuide)
                Positioned.fill(
                  child: Material(
                    color: Colors.black54,
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Card(
                            key: const Key('notification-permission-guide'),
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _requestNotificationPermission,
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.notifications_active_rounded,
                                      size: 40,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '开启通知提醒',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '允许通知、声音与震动，确保计时完成时及时提醒',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: _requestNotificationPermission,
                                      icon: const Icon(Icons.settings_rounded),
                                      label: const Text('去开启'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_showNotificationSetupGuide)
                Positioned.fill(
                  child: Material(
                    color: Colors.black54,
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Card(
                            key: const Key('notification-setup-guide'),
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_active_rounded,
                                    size: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '检查铃声和震动',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '部分手机在允许通知后，还需要在系统通知设置中手动开启铃声、震动和横幅。',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed:
                                            _dismissNotificationSetupGuide,
                                        child: const Text('稍后'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.icon(
                                        onPressed: _openNotificationSetup,
                                        icon: const Icon(
                                          Icons.settings_rounded,
                                        ),
                                        label: const Text('去检查'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_showBatteryOptimizationGuide)
                Positioned.fill(
                  child: Material(
                    color: Colors.black54,
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Card(
                            key: const Key('battery-optimization-guide'),
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.battery_saver_rounded,
                                    size: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '允许后台完成提醒',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '请允许番茄日志忽略电池优化，减少锁屏或离开应用后计时完成提醒被系统延迟的可能。',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed:
                                            _dismissBatteryOptimizationGuide,
                                        child: const Text('稍后'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.icon(
                                        onPressed:
                                            _openBatteryOptimizationSetup,
                                        icon: const Icon(
                                          Icons.battery_saver_rounded,
                                        ),
                                        label: const Text('去设置'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
