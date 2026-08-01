import 'dart:convert';

import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../controllers/app_controller.dart';
import '../models/focus_category.dart';
import '../ui/ui_helpers.dart';

const _categoryColors = <int>[
  0xFFFFB4AB,
  0xFFE85D4A,
  0xFF8C1D18,
  0xFFFFCC9A,
  0xFFEF8B35,
  0xFF9C4A00,
  0xFFFFE08A,
  0xFFE0A800,
  0xFF765900,
  0xFFC8E6C9,
  0xFF81C784,
  0xFF388E3C,
  0xFFB7D7C4,
  0xFF3D8063,
  0xFF174D38,
  0xFFB2EBF2,
  0xFF24A1A1,
  0xFF006064,
  0xFFB9CDFE,
  0xFF4D7CFE,
  0xFF183B8F,
  0xFFD8C4F4,
  0xFF8B5CF6,
  0xFF4C1D95,
  0xFFFFC1D9,
  0xFFE2508B,
  0xFF8E2452,
  0xFFD7D3CF,
  0xFF817974,
  0xFF35302D,
];

const _categoryIcons = [
  'work',
  'study',
  'reading',
  'exercise',
  'creative',
  'life',
  'code',
  'meeting',
  'music',
  'travel',
  'finance',
  'health',
  'food',
  'chores',
  'mindfulness',
  'social',
  'project',
  'idea',
];

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _collapsedIds = <String>{};

  AppController get controller => widget.controller;

  bool _hasChildren(FocusCategory category, List<FocusCategory> categories) =>
      categories.any((item) => item.parentId == category.id);

  bool _isVisible(FocusCategory category) {
    var parentId = category.parentId;
    final visited = <String>{category.id};
    while (parentId != null && visited.add(parentId)) {
      if (_collapsedIds.contains(parentId)) return false;
      parentId = controller.categoryById(parentId)?.parentId;
    }
    return true;
  }

  void _collapseAll() {
    setState(() {
      _collapsedIds
        ..clear()
        ..addAll(
          controller.categories
              .where(
                (category) => _hasChildren(category, controller.categories),
              )
              .map((category) => category.id),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final secondsByCategory = <String, int>{};
    for (final log in controller.logs) {
      if (!DateUtils.isSameDay(log.startedAt, now)) continue;
      secondsByCategory.update(
        log.categoryId,
        (seconds) => seconds + log.actualSeconds,
        ifAbsent: () => log.actualSeconds,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_category',
        onPressed: () => _showCategoryDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建分类'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('分类', style: theme.textTheme.headlineMedium),
              ),
              TextButton.icon(
                onPressed: _collapsedIds.isEmpty
                    ? _collapseAll
                    : () => setState(_collapsedIds.clear),
                icon: Icon(
                  _collapsedIds.isEmpty
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
                label: Text(_collapsedIds.isEmpty ? '一键折叠' : '全部展开'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '一级分类下可以继续创建子分类。',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          ...controller.activeCategories
              .where(_isVisible)
              .map(
                (category) => _IndentedCategoryCard(
                  depth: controller.categoryDepth(category),
                  child: _CategoryCard(
                    category: category,
                    todaySeconds: secondsByCategory[category.id] ?? 0,
                    isExpanded: !_collapsedIds.contains(category.id),
                    hasChildren: _hasChildren(
                      category,
                      controller.activeCategories,
                    ),
                    onToggle: () => setState(() {
                      if (!_collapsedIds.remove(category.id)) {
                        _collapsedIds.add(category.id);
                      }
                    }),
                    onAddChild: () =>
                        _showCategoryDialog(context, null, category.id),
                    onEdit: () => _showCategoryDialog(context, category),
                    onArchive: () => _setArchived(context, category, true),
                    onDelete: () => _confirmDelete(context, category),
                  ),
                ),
              ),
          if (controller.archivedCategories.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('已归档', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            ...controller.archivedCategories
                .where(_isVisible)
                .map(
                  (category) => _IndentedCategoryCard(
                    depth: controller.categoryDepth(category),
                    child: _CategoryCard(
                      category: category,
                      todaySeconds: secondsByCategory[category.id] ?? 0,
                      isExpanded: !_collapsedIds.contains(category.id),
                      hasChildren: _hasChildren(
                        category,
                        controller.archivedCategories,
                      ),
                      onToggle: () => setState(() {
                        if (!_collapsedIds.remove(category.id)) {
                          _collapsedIds.add(category.id);
                        }
                      }),
                      onEdit: () => _showCategoryDialog(context, category),
                      onArchive: () => _setArchived(context, category, false),
                      onDelete: () => _confirmDelete(context, category),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  void _setArchived(
    BuildContext context,
    FocusCategory category,
    bool archived,
  ) {
    if (controller.setCategoryArchived(category, archived)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(archived ? '至少保留一个可用分类，正在计时的分类也不能归档' : '分类状态没有变化'),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    FocusCategory category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${category.name}”？'),
        content: const Text('该分类、子分类及其所有记录和每日计划都会永久删除。'),
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
    if (confirmed != true || controller.deleteCategory(category)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在计时的分类或最后一个可用分类不能删除')));
  }

  Future<void> _showCategoryDialog(
    BuildContext context, [
    FocusCategory? existing,
    String? initialParentId,
  ]) async {
    final nameController = TextEditingController(text: existing?.name);
    final initialParent = controller.categoryById(
      existing?.parentId ?? initialParentId ?? '',
    );
    var parentId = existing?.parentId ?? initialParentId;
    var colorValue =
        existing?.colorValue ??
        initialParent?.colorValue ??
        _categoryColors.first;
    var iconKey =
        existing?.iconKey ?? initialParent?.iconKey ?? _categoryIcons.first;
    final parentOptions =
        (existing?.isArchived == true
                ? controller.categories
                : controller.activeCategories)
            .where(
              (category) =>
                  category.id != existing?.id &&
                  (existing == null ||
                      !controller.isDescendantOf(category.id, existing.id)),
            )
            .toList();
    if (parentId != null &&
        !parentOptions.any((category) => category.id == parentId)) {
      parentId = null;
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新建分类' : '编辑分类'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: parentId,
                  decoration: const InputDecoration(labelText: '上级分类'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('无（一级分类）'),
                    ),
                    ...parentOptions.map(
                      (category) => DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(controller.categoryPath(category)),
                      ),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => parentId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  maxLength: AppController.maxCategoryNameLength,
                  decoration: const InputDecoration(labelText: '分类名称'),
                ),
                const SizedBox(height: 10),
                const Text('颜色'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _categoryColors
                      .map(
                        (value) => _ColorButton(
                          value: value,
                          selected: colorValue == value,
                          onTap: () => setDialogState(() => colorValue = value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickCustomColor(context, colorValue);
                    if (picked != null) {
                      setDialogState(() => colorValue = picked);
                    }
                  },
                  icon: Icon(Icons.colorize_rounded, color: Color(colorValue)),
                  label: const Text('自定义色盘'),
                ),
                const SizedBox(height: 18),
                const Text('图标'),
                const SizedBox(height: 8),
                _IconPicker(
                  selected: iconKey,
                  color: Color(colorValue),
                  onSelected: (value) => setDialogState(() => iconKey = value),
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
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('请输入分类名称')));
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
      if (existing == null) {
        controller.addCategory(
          name: nameController.text,
          colorValue: colorValue,
          iconKey: iconKey,
          parentId: parentId,
        );
      } else {
        controller.updateCategory(
          existing,
          name: nameController.text,
          colorValue: colorValue,
          iconKey: iconKey,
          parentId: parentId,
        );
      }
    }
    nameController.dispose();
  }

  Future<int?> _pickCustomColor(BuildContext context, int initialColor) {
    var color = Color(initialColor);
    var hsv = HSVColor.fromColor(color);
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) => AlertDialog(
          title: const Text('自定义色盘'),
          content: SizedBox.square(
            dimension: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 230,
                  child: ColorPickerHueRing(
                    hsv,
                    (value) => setPickerState(() {
                      hsv = value;
                      color = value.toColor();
                    }),
                    strokeWidth: 20,
                  ),
                ),
                SizedBox.square(
                  dimension: 112,
                  child: ColorPickerArea(
                    hsv,
                    (value) => setPickerState(() {
                      hsv = value;
                      color = value.toColor();
                    }),
                    PaletteType.hsv,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, color.toARGB32()),
              child: const Text('使用此颜色'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Color(value),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final String selected;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categoryIcons
              .map(
                (key) => _IconChoice(
                  keyName: key,
                  selected: selected == key,
                  color: color,
                  onTap: () => onSelected(key),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.travel_explore_rounded),
          label: const Text('在线搜索 Iconify'),
          onPressed: () async {
            final key = await showDialog<String>(
              context: context,
              builder: (context) => _IconifySearchDialog(color: color),
            );
            if (key != null) onSelected(key);
          },
        ),
        if (isIconifyIcon(selected)) ...[
          const SizedBox(height: 8),
          _IconChoice(
            keyName: selected,
            selected: true,
            color: color,
            onTap: () {},
          ),
        ],
      ],
    );
  }
}

class _IconifySearchDialog extends StatefulWidget {
  const _IconifySearchDialog({required this.color});

  final Color color;

  @override
  State<_IconifySearchDialog> createState() => _IconifySearchDialogState();
}

class _IconifySearchDialogState extends State<_IconifySearchDialog> {
  final _controller = TextEditingController();
  List<String> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final response = await http
          .get(
            Uri.https('api.iconify.design', '/search', {
              'query': query,
              'limit': '30',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const FormatException('搜索服务暂时不可用');
      }
      final data = jsonDecode(response.body) as Map<String, Object?>;
      final icons = (data['icons'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList();
      if (mounted) {
        setState(() {
          _results = icons;
          _error = icons.isEmpty ? '没有找到图标' : null;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = '搜索失败，请检查网络');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('在线图标'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索 Iconify，例如 run',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: '搜索在线图标',
                        onPressed: _search,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _error ?? '输入关键词搜索图标',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final key = _results[index];
                        return _IconChoice(
                          keyName: key,
                          selected: false,
                          color: widget.color,
                          onTap: () => Navigator.pop(context, key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.keyName,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String keyName;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: keyName,
      isSelected: selected,
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: selected ? 0.24 : 0.12),
      ),
      onPressed: onTap,
      icon: categoryIconWidget(keyName, color: color, size: 24),
    );
  }
}

class _IndentedCategoryCard extends StatelessWidget {
  const _IndentedCategoryCard({required this.depth, required this.child});

  final int depth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0) ...[
            SizedBox(width: depth * 18),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.todaySeconds,
    required this.hasChildren,
    required this.isExpanded,
    required this.onToggle,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
    this.onAddChild,
  });

  final FocusCategory category;
  final int todaySeconds;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onAddChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListTile(
        onTap: hasChildren ? onToggle : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: Opacity(
          opacity: category.isArchived ? 0.45 : 1,
          child: CategoryAvatar(category: category),
        ),
        title: Text(
          category.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: category.isArchived
                ? theme.colorScheme.onSurfaceVariant
                : null,
          ),
        ),
        subtitle: Text(
          category.isArchived
              ? '已归档，历史记录仍会保留'
              : '今天 ${formatMinutes(todaySeconds)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasChildren)
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'child') onAddChild?.call();
                if (action == 'edit') onEdit();
                if (action == 'archive') onArchive();
                if (action == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                if (onAddChild != null)
                  const PopupMenuItem(
                    value: 'child',
                    child: ListTile(
                      leading: Icon(Icons.account_tree_outlined),
                      title: Text('添加子分类'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('编辑'),
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                    leading: Icon(
                      category.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    title: Text(category.isArchived ? '恢复' : '归档'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      '删除',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
