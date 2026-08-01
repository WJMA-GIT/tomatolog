import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/daily_plan.dart';
import '../ui/ui_helpers.dart';
import 'settings_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final todayLogs = controller.logs
        .where((log) => DateUtils.isSameDay(log.startedAt, now))
        .toList();
    final todayPlans = controller.plans
        .where((plan) => plan.occursOn(now))
        .toList();
    final secondsByCategory = <String, int>{};
    for (final log in todayLogs) {
      secondsByCategory.update(
        log.categoryId,
        (seconds) => seconds + log.actualSeconds,
        ifAbsent: () => log.actualSeconds,
      );
    }
    final total = secondsByCategory.values.fold(0, (sum, value) => sum + value);
    final usedCategories = controller.categories
        .where((category) => secondsByCategory.containsKey(category.id))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            Expanded(child: Text('今天', style: theme.textTheme.headlineMedium)),
            IconButton.filledTonal(
              tooltip: '添加每日计划',
              onPressed: () => showPlanDialog(context, controller, now),
              icon: const Icon(Icons.add_task_rounded),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '设置',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(controller: controller),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        Text(
          '${now.month}月${now.day}日，把时间花在重要的事上。',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.colorScheme.primary, const Color(0xFFFF8A65)],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日专注',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatMinutes(total),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${todayLogs.length} 条记录 · '
                '${todayPlans.where((plan) => plan.isCompletedOn(now)).length}/'
                '${todayPlans.length} 项计划',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('今日计划', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (todayPlans.isEmpty)
          const _EmptyCard(
            icon: Icons.event_note_rounded,
            text: '还没有计划，点击右上角添加',
          )
        else
          ...todayPlans.map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlanTile(plan: plan, controller: controller, date: now),
            ),
          ),
        const SizedBox(height: 16),
        Text('分类用时', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (usedCategories.isEmpty)
          const _EmptyCard(
            icon: Icons.hourglass_empty_rounded,
            text: '今天还没有时间记录',
          )
        else
          ...usedCategories.map((category) {
            final seconds = secondsByCategory[category.id]!;
            final color = Color(category.colorValue);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                color: theme.colorScheme.surfaceContainerLowest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CategoryAvatar(category: category),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    controller.categoryPath(category),
                                  ),
                                ),
                                Text(
                                  formatMinutes(seconds),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: seconds / total,
                              minHeight: 7,
                              color: color,
                              backgroundColor: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class PlanTile extends StatelessWidget {
  const PlanTile({
    super.key,
    required this.plan,
    required this.controller,
    required this.date,
  });

  final DailyPlan plan;
  final AppController controller;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final category = controller.categoryById(plan.categoryId);
    if (category == null) return const SizedBox.shrink();
    final completed = plan.isCompletedOn(date);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: ListTile(
        onTap: () => controller.setPlanCompleted(plan.id, date, !completed),
        leading: CategoryAvatar(category: category, size: 38),
        title: Text(
          controller.categoryPath(category),
          style: TextStyle(
            decoration: completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text('每日 ${plan.plannedMinutes} 分钟'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: completed,
              onChanged: (value) =>
                  controller.setPlanCompleted(plan.id, date, value ?? false),
            ),
            IconButton(
              tooltip: '删除计划',
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这项循环计划？'),
        content: const Text('整个日期范围内的计划和完成记录都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) controller.deletePlan(plan.id);
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(text, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

Future<void> showPlanDialog(
  BuildContext context,
  AppController controller,
  DateTime initialDate,
) async {
  var startDate = DateTime(
    initialDate.year,
    initialDate.month,
    initialDate.day,
  );
  var endDate = startDate.add(const Duration(days: 29));
  final minutesController = TextEditingController(text: '25');
  var categoryId =
      controller.selectedCategoryId ?? controller.activeCategories.first.id;

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('添加每日循环计划'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: '分类'),
                items: controller.activeCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(controller.categoryPath(category)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => categoryId = value);
                },
              ),
              const SizedBox(height: 8),
              _DateTile(
                label: '开始日期',
                date: startDate,
                onTap: () async {
                  final selected = await _pickDate(context, startDate);
                  if (selected == null) return;
                  setState(() {
                    startDate = selected;
                    if (endDate.isBefore(startDate)) endDate = startDate;
                  });
                },
              ),
              _DateTile(
                label: '结束日期',
                date: endDate,
                onTap: () async {
                  final selected = await _pickDate(context, endDate);
                  if (selected != null) setState(() => endDate = selected);
                },
              ),
              TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '每日目标',
                  suffixText: '分钟',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('计划会在所选日期范围内每天出现。'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final invalidDates = endDate.isBefore(startDate);
              final minutes = int.tryParse(minutesController.text);
              if (invalidDates ||
                  minutes == null ||
                  minutes <= 0 ||
                  minutes > AppController.maxMinutes) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入 1–1440 分钟的每日目标')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );

  if (shouldSave == true) {
    final minutes = int.parse(minutesController.text);
    controller.addPlan(
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
      plannedMinutes: minutes,
    );
  }
  minutesController.dispose();
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('${date.year}-${date.month}-${date.day}'),
      trailing: const Icon(Icons.calendar_month_rounded),
      onTap: onTap,
    );
  }
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initialDate) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2020),
    lastDate: DateTime(DateTime.now().year + 5),
  );
}
