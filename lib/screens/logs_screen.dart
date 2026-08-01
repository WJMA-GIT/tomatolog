import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/time_log.dart';
import '../ui/ui_helpers.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = controller.logs;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_log',
        onPressed: () => _showManualLogDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('补记'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('时间日志', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    '每一次投入，都值得被看见。',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (logs.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _EmptyLogs())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList.separated(
                itemCount: logs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final category = controller.categoryById(log.categoryId);
                  if (category == null) return const SizedBox.shrink();
                  return Card(
                    color: theme.colorScheme.surfaceContainerLowest,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onLongPress: () => _confirmDelete(context, log),
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        formatMinutes(log.actualSeconds),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${formatDate(log.startedAt)} · ${logStatusLabel(log.status)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (log.note != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      log.note!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showManualLogDialog(BuildContext context) async {
    final minutesController = TextEditingController(text: '25');
    final noteController = TextEditingController();
    var categoryId =
        controller.selectedCategoryId ?? controller.activeCategories.first.id;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('补记时间'),
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
                      if (value != null) {
                        setDialogState(() => categoryId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '时长（分钟）'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: '备注（可选）'),
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
                  final minutes = int.tryParse(minutesController.text);
                  if (minutes == null ||
                      minutes <= 0 ||
                      minutes > AppController.maxMinutes) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入 1–1440 分钟')),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (shouldSave == true) {
      controller.addManualLog(
        categoryId: categoryId,
        minutes: int.parse(minutesController.text),
        note: noteController.text,
      );
    }
    minutesController.dispose();
    noteController.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, TimeLog log) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后无法恢复。'),
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
    if (shouldDelete == true) controller.deleteLog(log.id);
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 52, color: color),
          const SizedBox(height: 12),
          const Text('暂无时间记录'),
          const SizedBox(height: 4),
          Text('完成一次计时，或手动补记', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
