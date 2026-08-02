import 'dart:io';

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
  bool _requestingNotificationPermission = false;

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
    if (state == AppLifecycleState.resumed) _refreshNotificationStatus();
  }

  Future<void> _refreshNotificationStatus({
    bool requestOnFirstOpen = false,
  }) async {
    final status = await widget.controller.notificationStatus();
    if (!mounted) return;
    final granted = status['granted'] == true;
    setState(() => _showNotificationGuide = !granted);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final backgroundPath = widget.controller.backgroundImagePath;
        return PopScope(
          canPop: !_showNotificationGuide,
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
            ],
          ),
        );
      },
    );
  }
}
