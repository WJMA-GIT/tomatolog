import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/focus_category.dart';
import '../models/time_log.dart';

IconData categoryIcon(String key) {
  return switch (key) {
    'study' => Icons.school_rounded,
    'reading' => Icons.auto_stories_rounded,
    'exercise' => Icons.directions_run_rounded,
    'creative' => Icons.palette_rounded,
    'life' => Icons.home_rounded,
    'code' => Icons.code_rounded,
    'meeting' => Icons.groups_rounded,
    'music' => Icons.music_note_rounded,
    'travel' => Icons.flight_rounded,
    'finance' => Icons.account_balance_wallet_rounded,
    'health' => Icons.favorite_rounded,
    'food' => Icons.restaurant_rounded,
    'chores' => Icons.cleaning_services_rounded,
    'mindfulness' => Icons.self_improvement_rounded,
    'social' => Icons.forum_rounded,
    'project' => Icons.rocket_launch_rounded,
    'idea' => Icons.lightbulb_rounded,
    _ => Icons.work_rounded,
  };
}

bool isIconifyIcon(String key) => key.contains(':');

String iconifySvgUrl(String key) {
  final parts = key.split(':');
  return 'https://api.iconify.design/${parts.first}/${parts.last}.svg';
}

Widget categoryIconWidget(String key, {required Color color, double? size}) {
  if (!isIconifyIcon(key)) {
    return Icon(categoryIcon(key), color: color, size: size);
  }
  return SvgPicture.network(
    iconifySvgUrl(key),
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    placeholderBuilder: (_) =>
        Icon(Icons.hourglass_empty_rounded, color: color, size: size),
    errorBuilder: (_, _, _) =>
        Icon(Icons.broken_image_outlined, color: color, size: size),
  );
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatClock(int seconds) {
  final minutes = seconds ~/ 60;
  return '${twoDigits(minutes)}:${twoDigits(seconds % 60)}';
}

String formatMinutes(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '$minutes 分钟';
  return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
}

String formatDate(DateTime date) =>
    '${date.month}月${date.day}日  ${twoDigits(date.hour)}:${twoDigits(date.minute)}';

String logStatusLabel(LogStatus status) => switch (status) {
  LogStatus.completed => '已完成',
  LogStatus.interrupted => '已中断',
  LogStatus.manuallyAdded => '手动补记',
};

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 44});

  final FocusCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Center(
        child: categoryIconWidget(
          category.iconKey,
          color: color,
          size: size * 0.5,
        ),
      ),
    );
  }
}
