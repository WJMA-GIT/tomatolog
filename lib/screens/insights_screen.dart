import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../ui/ui_helpers.dart';
import 'today_screen.dart';

enum _StatsPeriod { day, week, month }

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  DateTime _selectedDate = DateTime.now();
  _StatsPeriod _period = _StatsPeriod.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = _dateRange(_selectedDate, _period);
    final logs = widget.controller.logs.where((log) {
      return !log.startedAt.isBefore(range.$1) &&
          log.startedAt.isBefore(range.$2);
    }).toList();
    final selectedPlans = widget.controller.plans
        .where((plan) => plan.occursOn(_selectedDate))
        .toList();
    final planStats = _planOccurrenceStats(widget.controller, range);
    final secondsByCategory = <String, int>{};
    for (final log in logs) {
      secondsByCategory.update(
        log.categoryId,
        (seconds) => seconds + log.actualSeconds,
        ifAbsent: () => log.actualSeconds,
      );
    }
    final total = secondsByCategory.values.fold(0, (sum, value) => sum + value);
    final categories = widget.controller.categories
        .where((category) => secondsByCategory.containsKey(category.id))
        .toList();
    final slices = categories
        .map(
          (category) => _DonutSlice(
            seconds: secondsByCategory[category.id]!,
            color: Color(category.colorValue),
          ),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('日历与统计', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          '查看计划完成情况和专注时间。',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.surfaceContainerLowest,
          child: CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(DateTime.now().year + 5),
            onDateChanged: (date) => setState(() => _selectedDate = date),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedDate.month}月${_selectedDate.day}日计划',
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: '添加计划',
              onPressed: () =>
                  showPlanDialog(context, widget.controller, _selectedDate),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (selectedPlans.isEmpty)
          Text(
            '当天没有计划',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          ...selectedPlans.map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlanTile(
                plan: plan,
                controller: widget.controller,
                date: _selectedDate,
              ),
            ),
          ),
        const SizedBox(height: 24),
        SegmentedButton<_StatsPeriod>(
          segments: const [
            ButtonSegment(value: _StatsPeriod.day, label: Text('日')),
            ButtonSegment(value: _StatsPeriod.week, label: Text('周')),
            ButtonSegment(value: _StatsPeriod.month, label: Text('月')),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => _period = value.first),
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rangeLabel(range), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  formatMinutes(total),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${logs.length} 条记录 · '
                  '${planStats.completed}/${planStats.total} 项计划完成',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('分类统计', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (secondsByCategory.isEmpty)
          Text(
            '这个周期还没有专注记录',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          )
        else ...[
          Semantics(
            label: '分类专注时间占比环形图',
            child: Center(
              child: SizedBox.square(
                dimension: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(180),
                      painter: _DonutChartPainter(slices),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('总计', style: theme.textTheme.labelLarge),
                        Text(
                          formatMinutes(total),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...categories.map((category) {
            final seconds = secondsByCategory[category.id]!;
            final percentage = seconds * 100 / total;
            return Card(
              color: theme.colorScheme.surfaceContainerLowest,
              child: ListTile(
                leading: CategoryAvatar(category: category),
                title: Text(widget.controller.categoryPath(category)),
                subtitle: LinearProgressIndicator(
                  value: seconds / total,
                  color: Color(category.colorValue),
                ),
                trailing: Text(
                  '${percentage.toStringAsFixed(1)}%\n${formatMinutes(seconds)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

({int total, int completed}) _planOccurrenceStats(
  AppController controller,
  (DateTime, DateTime) range,
) {
  var total = 0;
  var completed = 0;
  for (
    var date = range.$1;
    date.isBefore(range.$2);
    date = DateTime(date.year, date.month, date.day + 1)
  ) {
    for (final plan in controller.plans) {
      if (!plan.occursOn(date)) continue;
      total++;
      if (plan.isCompletedOn(date)) completed++;
    }
  }
  return (total: total, completed: completed);
}

class _DonutSlice {
  const _DonutSlice({required this.seconds, required this.color});

  final int seconds;
  final Color color;
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter(this.slices);

  final List<_DonutSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.seconds);
    if (total == 0) return;
    final strokeWidth = size.shortestSide * 0.16;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final gap = slices.length > 1 ? 0.025 : 0.0;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = slice.seconds / total * math.pi * 2;
      canvas.drawArc(
        arcRect,
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutChartPainter oldDelegate) => true;
}

(DateTime, DateTime) _dateRange(DateTime date, _StatsPeriod period) {
  final day = DateTime(date.year, date.month, date.day);
  final start = switch (period) {
    _StatsPeriod.day => day,
    _StatsPeriod.week => DateTime(
      day.year,
      day.month,
      day.day - day.weekday + 1,
    ),
    _StatsPeriod.month => DateTime(day.year, day.month),
  };
  final end = switch (period) {
    _StatsPeriod.day => DateTime(day.year, day.month, day.day + 1),
    _StatsPeriod.week => DateTime(start.year, start.month, start.day + 7),
    _StatsPeriod.month => DateTime(day.year, day.month + 1),
  };
  return (start, end);
}

String _rangeLabel((DateTime, DateTime) range) {
  final end = range.$2.subtract(const Duration(days: 1));
  if (DateUtils.isSameDay(range.$1, end)) {
    return '${range.$1.month}月${range.$1.day}日';
  }
  return '${range.$1.month}月${range.$1.day}日'
      ' – ${end.month}月${end.day}日';
}
