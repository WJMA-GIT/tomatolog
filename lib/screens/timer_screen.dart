import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../ui/ui_helpers.dart';

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedCategory;
    final isIdle = controller.phase == TimerPhase.idle;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('专注计时', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            isIdle ? '选择一件事，然后只做这一件事。' : '保持专注，时间正在被认真记录。',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _CategoryPicker(controller: controller),
          const SizedBox(height: 30),
          Center(
            child: Semantics(
              label: '计时圆环，${controller.plannedMinutes} 分钟',
              hint: isIdle ? '沿圆环拖动可设置 1 到 60 分钟' : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: isIdle
                    ? (details) => _setMinutes(details.localPosition)
                    : null,
                onPanUpdate: isIdle
                    ? (details) => _setMinutes(details.localPosition)
                    : null,
                child: SizedBox.square(
                  dimension: 264,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: controller.progress,
                        strokeWidth: 13,
                        strokeCap: StrokeCap.round,
                        color: selected == null
                            ? theme.colorScheme.primary
                            : Color(selected.colorValue),
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            formatClock(controller.remainingSeconds),
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: 56,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            switch (controller.phase) {
                              TimerPhase.idle => '准备开始',
                              TimerPhase.running => '专注中',
                            },
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (isIdle) ...[
            Center(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 15, label: Text('15 分')),
                  ButtonSegment(value: 25, label: Text('25 分')),
                  ButtonSegment(value: 45, label: Text('45 分')),
                ],
                selected: {controller.plannedMinutes},
                onSelectionChanged: (values) =>
                    controller.setPlannedMinutes(values.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 22),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: selected == null
                  ? null
                  : switch (controller.phase) {
                      TimerPhase.idle => controller.startTimer,
                      TimerPhase.running => () => showTimerEndDialog(
                        context,
                        controller,
                      ),
                    },
              icon: Icon(
                controller.phase == TimerPhase.running
                    ? Icons.stop_circle_outlined
                    : Icons.play_arrow_rounded,
              ),
              label: Text(switch (controller.phase) {
                TimerPhase.idle => '开始专注',
                TimerPhase.running => '结束',
              }),
            ),
          ),
        ],
      ),
    );
  }

  void _setMinutes(Offset position) {
    const center = Offset(132, 132);
    var angle =
        math.atan2(position.dy - center.dy, position.dx - center.dx) +
        math.pi / 2;
    if (angle <= 0) angle += math.pi * 2;
    final minutes = (angle / (math.pi * 2) * AppController.timerDialMinutes)
        .round()
        .clamp(1, AppController.timerDialMinutes);
    controller.setPlannedMinutes(minutes);
  }
}

enum _TimerEndChoice { save, discard }

Future<void> showTimerEndDialog(
  BuildContext context,
  AppController controller,
) async {
  if (controller.phase == TimerPhase.idle) return;
  final choice = await showDialog<_TimerEndChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('结束这次专注？'),
      content: const Text('你可以保存当前已专注的时间，也可以丢弃本次记录。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('继续专注'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _TimerEndChoice.discard),
          child: const Text('丢弃记录'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _TimerEndChoice.save),
          child: const Text('保存记录'),
        ),
      ],
    ),
  );
  switch (choice) {
    case _TimerEndChoice.save:
      controller.stopTimer();
    case _TimerEndChoice.discard:
      controller.stopTimer(saveInterrupted: false);
    case null:
      break;
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedCategory;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected?.id,
          isExpanded: true,
          borderRadius: BorderRadius.circular(18),
          icon: const Icon(Icons.expand_more_rounded),
          onChanged: controller.phase == TimerPhase.idle
              ? (value) {
                  if (value != null) controller.selectCategory(value);
                }
              : null,
          items: controller.activeCategories.map((category) {
            final depth = controller.categoryDepth(category);
            return DropdownMenuItem(
              value: category.id,
              child: Row(
                children: [
                  SizedBox(width: depth * 18),
                  if (depth > 0) ...[
                    Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                  ],
                  CategoryAvatar(category: category, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
