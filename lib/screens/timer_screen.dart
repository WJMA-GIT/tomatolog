import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../ui/ui_helpers.dart';

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key, required this.controller});

  static const _dialDimension = 248.0;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedCategory;
    final isIdle = controller.phase == TimerPhase.idle;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('专注计时', style: theme.textTheme.headlineSmall),
          Text(
            isIdle ? '选择一件事，然后只做这一件事。' : '保持专注，时间正在被认真记录。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _CategoryPicker(controller: controller),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              label: '计时圆环，${controller.remainingSeconds} 秒',
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
                  dimension: _dialDimension,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: controller.progress,
                        strokeWidth: 16,
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
                              fontSize: 42,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -2,
                            ),
                          ),
                          if (!isIdle) ...[
                            const SizedBox(height: 8),
                            Text(
                              switch (controller.phase) {
                                TimerPhase.idle => '',
                                TimerPhase.running =>
                                  '第 ${controller.currentGroup}/${controller.groupCount} 组 · '
                                      '第 ${controller.currentCycle}/${controller.cycleCount} 轮 · 专注中',
                                TimerPhase.interval =>
                                  '第 ${controller.currentGroup} 组 · '
                                      '第 ${controller.currentCycle} 轮完成 · 休息中',
                                TimerPhase.longInterval =>
                                  '第 ${controller.currentGroup}/${controller.groupCount} 组完成 · 长休息',
                              },
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                height: 1.1,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('timer-primary-button'),
                            onPressed: selected == null
                                ? null
                                : isIdle
                                ? controller.startTimer
                                : () => showTimerEndDialog(context, controller),
                            icon: Icon(
                              isIdle
                                  ? Icons.play_arrow_rounded
                                  : Icons.stop_circle_outlined,
                            ),
                            label: Text(isIdle ? '开始专注' : '结束'),
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          if (defaultTargetPlatform == TargetPlatform.android)
                            SizedBox(
                              height: 28,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => controller.setFloatingTimerEnabled(
                                  !controller.floatingTimerEnabled,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '悬浮倒计时',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Transform.scale(
                                      scale: 0.68,
                                      child: Switch(
                                        value: controller.floatingTimerEnabled,
                                        onChanged:
                                            controller.setFloatingTimerEnabled,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
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
          const SizedBox(height: 10),
          if (isIdle) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...controller.timerPresets.indexed.map(
                  (entry) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: GestureDetector(
                        onLongPress: () =>
                            _renamePreset(context, entry.$1, entry.$2.name),
                        child: ChoiceChip(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${entry.$2.name} ${entry.$2.minutes}分',
                            ),
                          ),
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 3,
                          ),
                          selected:
                              controller.activeTimerPresetIndex == entry.$1,
                          onSelected: (_) =>
                              controller.selectTimerPreset(entry.$1),
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CycleSettings(controller: controller),
          ],
        ],
      ),
    );
  }

  void _setMinutes(Offset position) {
    const center = Offset(_dialDimension / 2, _dialDimension / 2);
    var angle =
        math.atan2(position.dy - center.dy, position.dx - center.dx) +
        math.pi / 2;
    if (angle <= 0) angle += math.pi * 2;
    final minutes = (angle / (math.pi * 2) * AppController.timerDialMinutes)
        .round()
        .clamp(1, AppController.timerDialMinutes);
    controller.setPlannedMinutes(minutes);
  }

  Future<void> _renamePreset(
    BuildContext context,
    int index,
    String currentName,
  ) async {
    var editedName = currentName;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改配置名称'),
        content: TextFormField(
          initialValue: currentName,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(labelText: '配置名称', counterText: ''),
          onChanged: (value) => editedName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editedName),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null) controller.renameTimerPreset(index, name);
  }
}

class _CycleSettings extends StatelessWidget {
  const _CycleSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final shortBreakEnabled = controller.cycleCount > 1;
    final longBreakEnabled = controller.groupCount > 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CounterTile(
                    label: '循环次数',
                    value: controller.groupCount,
                    suffix: '组',
                    onDecrease: controller.groupCount > 1
                        ? () => controller.setGroupCount(
                            controller.groupCount - 1,
                          )
                        : null,
                    onIncrease:
                        controller.groupCount < AppController.maxGroupCount
                        ? () => controller.setGroupCount(
                            controller.groupCount + 1,
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: _CounterTile(
                    label: '组内轮次',
                    value: controller.cycleCount,
                    suffix: '轮',
                    onDecrease: controller.cycleCount > 1
                        ? () => controller.setCycleCount(
                            controller.cycleCount - 1,
                          )
                        : null,
                    onIncrease:
                        controller.cycleCount < AppController.maxCycleCount
                        ? () => controller.setCycleCount(
                            controller.cycleCount + 1,
                          )
                        : null,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _CounterTile(
                    label: '休息时间',
                    value: controller.intervalMinutes,
                    suffix: '分钟',
                    enabled: shortBreakEnabled,
                    onDecrease:
                        shortBreakEnabled && controller.intervalMinutes > 1
                        ? () => controller.setIntervalMinutes(
                            controller.intervalMinutes - 1,
                          )
                        : null,
                    onIncrease:
                        shortBreakEnabled &&
                            controller.intervalMinutes <
                                AppController.maxIntervalMinutes
                        ? () => controller.setIntervalMinutes(
                            controller.intervalMinutes + 1,
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: _CounterTile(
                    label: '长休息时间',
                    value: controller.longIntervalMinutes,
                    suffix: '分钟',
                    enabled: longBreakEnabled,
                    onDecrease:
                        longBreakEnabled && controller.longIntervalMinutes > 1
                        ? () => controller.setLongIntervalMinutes(
                            controller.longIntervalMinutes - 1,
                          )
                        : null,
                    onIncrease:
                        longBreakEnabled &&
                            controller.longIntervalMinutes <
                                AppController.maxIntervalMinutes
                        ? () => controller.setLongIntervalMinutes(
                            controller.longIntervalMinutes + 1,
                          )
                        : null,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: const Text('间隔计入统计'),
              value: controller.recordIntervals,
              onChanged: controller.setRecordIntervals,
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.value,
    required this.suffix,
    this.enabled = true,
    this.onDecrease,
    this.onIncrease,
  });

  final String label;
  final int value;
  final String suffix;
  final bool enabled;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            color: enabled
                ? null
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '减少$label',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: enabled ? onDecrease : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            ),
            SizedBox(
              width: 58,
              child: Text(
                '$value $suffix',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: '增加$label',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: enabled ? onIncrease : null,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
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
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('继续', maxLines: 1, softWrap: false),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context, _TimerEndChoice.discard),
                child: const Text('丢弃', maxLines: 1, softWrap: false),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _TimerEndChoice.save),
                child: const Text('保存', maxLines: 1, softWrap: false),
              ),
            ),
          ],
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
