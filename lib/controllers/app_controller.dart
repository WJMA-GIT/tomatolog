import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/daily_plan.dart';
import '../models/focus_category.dart';
import '../models/time_log.dart';
import '../services/app_platform_service.dart';
import '../services/app_storage.dart';
import '../services/webdav_sync_manager.dart';

enum TimerPhase { idle, running, interval, longInterval }

enum AppThemePreference { system, light, dark }

class TimerPreset {
  const TimerPreset({
    required this.name,
    required this.minutes,
    this.groupCount = 1,
    this.cycleCount = 4,
    this.intervalMinutes = 5,
    this.longIntervalMinutes = 0,
    this.recordIntervals = false,
  });

  final String name;
  final int minutes;
  final int groupCount;
  final int cycleCount;
  final int intervalMinutes;
  final int longIntervalMinutes;
  final bool recordIntervals;

  TimerPreset copyWith({
    String? name,
    int? minutes,
    int? groupCount,
    int? cycleCount,
    int? intervalMinutes,
    int? longIntervalMinutes,
    bool? recordIntervals,
  }) => TimerPreset(
    name: name ?? this.name,
    minutes: minutes ?? this.minutes,
    groupCount: groupCount ?? this.groupCount,
    cycleCount: cycleCount ?? this.cycleCount,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    longIntervalMinutes: longIntervalMinutes ?? this.longIntervalMinutes,
    recordIntervals: recordIntervals ?? this.recordIntervals,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'minutes': minutes,
    'groupCount': groupCount,
    'cycleCount': cycleCount,
    'intervalMinutes': intervalMinutes,
    'longIntervalMinutes': longIntervalMinutes,
    'recordIntervals': recordIntervals,
  };
}

class AppController extends ChangeNotifier {
  AppController(this._storage, [this._platform, this.webDav]) {
    webDav?.attach(
      exportData: exportPortableData,
      importData: importPortableData,
    );
  }

  static const maxCategoryNameLength = 12;
  static const maxMinutes = 1440;
  static const timerDialMinutes = 60;
  static const maxCycleCount = 10;
  static const maxGroupCount = 10;
  static const maxIntervalMinutes = 60;
  static const defaultAccentColorValue = 0xFFE05446;

  final AppStorage _storage;
  final AppPlatformService? _platform;
  final WebDavSyncManager? webDav;
  final List<FocusCategory> _categories = [];
  final List<TimeLog> _logs = [];
  final List<DailyPlan> _plans = [];
  final List<TimerPreset> _timerPresets = [];
  late final List<FocusCategory> _categoriesView = UnmodifiableListView(
    _categories,
  );
  late final List<TimeLog> _logsView = UnmodifiableListView(_logs);
  late final List<DailyPlan> _plansView = UnmodifiableListView(_plans);
  late final List<TimerPreset> _timerPresetsView = UnmodifiableListView(
    _timerPresets,
  );
  Timer? _ticker;
  Timer? _midnightRefresh;
  Future<void> _pendingPersist = Future.value();
  int _lastGeneratedId = 0;

  TimerPhase _phase = TimerPhase.idle;
  String? _selectedCategoryId;
  int _plannedMinutes = 25;
  int _remainingSeconds = 25 * 60;
  int _cycleCount = 4;
  int _groupCount = 1;
  int _intervalMinutes = 5;
  int _longIntervalMinutes = 0;
  bool _recordIntervals = false;
  int? _activeTimerPresetIndex;
  int _currentCycle = 1;
  int _currentGroup = 1;
  DateTime? _sessionStartedAt;
  DateTime? _targetEndAt;
  AppThemePreference _themePreference = AppThemePreference.system;
  int _accentColorValue = defaultAccentColorValue;
  String? _backgroundImagePath;
  bool _floatingTimerEnabled = false;
  bool _appInForeground = true;

  TimerPhase get phase => _phase;

  String? get selectedCategoryId => _selectedCategoryId;

  int get plannedMinutes => _plannedMinutes;

  int get remainingSeconds => _remainingSeconds;

  int get cycleCount => _cycleCount;

  int get groupCount => _groupCount;

  int get intervalMinutes => _intervalMinutes;

  int get longIntervalMinutes => _longIntervalMinutes;

  bool get recordIntervals => _recordIntervals;

  int? get activeTimerPresetIndex => _activeTimerPresetIndex;

  int get currentCycle => _currentCycle;

  int get currentGroup => _currentGroup;

  bool get isBreak =>
      phase == TimerPhase.interval || phase == TimerPhase.longInterval;

  AppThemePreference get themePreference => _themePreference;

  int get accentColorValue => _accentColorValue;

  String? get backgroundImagePath => _backgroundImagePath;

  bool get floatingTimerEnabled => _floatingTimerEnabled;

  Future<void> setKeepScreenOn(bool enabled) async {
    await _platform?.setKeepScreenOn(enabled);
  }

  List<FocusCategory> get categories => _categoriesView;

  List<FocusCategory> get activeCategories =>
      List<FocusCategory>.unmodifiable(_orderedCategories(archived: false));

  List<FocusCategory> get archivedCategories =>
      List<FocusCategory>.unmodifiable(_orderedCategories(archived: true));

  List<TimeLog> get logs => _logsView;

  List<DailyPlan> get plans => _plansView;

  List<TimerPreset> get timerPresets => _timerPresetsView;

  FocusCategory? get selectedCategory => categoryById(selectedCategoryId ?? '');

  int get currentPhaseSeconds =>
      switch (phase) {
        TimerPhase.interval => intervalMinutes,
        TimerPhase.longInterval => longIntervalMinutes,
        _ => plannedMinutes,
      } *
      60;

  int get elapsedSeconds => currentPhaseSeconds - remainingSeconds;

  double get progress =>
      (remainingSeconds / (timerDialMinutes * 60)).clamp(0.0, 1.0).toDouble();

  Future<void> load() async {
    _ticker?.cancel();
    _midnightRefresh?.cancel();
    _activeTimerPresetIndex = null;
    _categories.clear();
    _logs.clear();
    _plans.clear();

    final data = await _storage.read();
    if (data == null) {
      _loadDefaults();
      await _persist();
      _scheduleMidnightRefresh();
      notifyListeners();
      return;
    }

    try {
      final categoryData = (data['categories'] as List<Object?>?) ?? [];
      _categories.addAll(
        categoryData.map(
          (item) =>
              FocusCategory.fromJson((item as Map).cast<String, Object?>()),
        ),
      );
      final logData = (data['logs'] as List<Object?>?) ?? [];
      _logs.addAll(
        logData.map(
          (item) => TimeLog.fromJson((item as Map).cast<String, Object?>()),
        ),
      );
      final planData = (data['plans'] as List<Object?>?) ?? [];
      _plans.addAll(
        planData.map(
          (item) => DailyPlan.fromJson((item as Map).cast<String, Object?>()),
        ),
      );
      if (_categories.isEmpty) _categories.addAll(_defaultCategories);
      _repairCategoryParents();
      _logs.removeWhere((log) => categoryById(log.categoryId) == null);
      _plans.removeWhere((plan) => categoryById(plan.categoryId) == null);
      _logs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      _plans.sort((a, b) => a.startDate.compareTo(b.startDate));
      _rememberExistingIds();

      final timerData = (data['timer'] as Map?)?.cast<String, Object?>();
      _timerPresets
        ..clear()
        ..addAll(_parseTimerPresets(data['timerPresets']));
      _plannedMinutes = _validPlannedMinutes(data['plannedMinutes']);
      _selectedCategoryId = data['selectedCategoryId'] as String?;
      _themePreference = _parseThemePreference(data['themePreference']);
      _accentColorValue =
          data['accentColorValue'] as int? ?? defaultAccentColorValue;
      _backgroundImagePath = data['backgroundImagePath'] as String?;
      _floatingTimerEnabled = data['floatingTimerEnabled'] == true;
      _cycleCount = _validCycleCount(data['cycleCount']);
      _groupCount = _validGroupCount(data['groupCount']);
      _intervalMinutes = cycleCount == 1
          ? 0
          : _validIntervalMinutes(data['intervalMinutes']);
      _longIntervalMinutes = groupCount == 1
          ? 0
          : _validLongIntervalMinutes(data['longIntervalMinutes']);
      _recordIntervals = data['recordIntervals'] == true;
      _ensureSelectedCategory();
      _restoreTimer(timerData);
    } on FormatException {
      _loadDefaults();
      await _persist();
    } on TypeError {
      _loadDefaults();
      await _persist();
    } on ArgumentError {
      _loadDefaults();
      await _persist();
    }
    if (_syncPlanCompletions(DateTime.now())) await _persist();
    _scheduleMidnightRefresh();
    notifyListeners();
  }

  FocusCategory? categoryById(String id) {
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  String categoryPath(FocusCategory category) {
    final names = <String>[];
    final visited = <String>{};
    FocusCategory? current = category;
    while (current != null && visited.add(current.id)) {
      names.add(current.name);
      current = current.parentId == null
          ? null
          : categoryById(current.parentId!);
    }
    return names.reversed.join(' / ');
  }

  int categoryDepth(FocusCategory category) {
    var depth = 0;
    final visited = <String>{category.id};
    var parentId = category.parentId;
    while (parentId != null && visited.add(parentId)) {
      final parent = categoryById(parentId);
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  bool isDescendantOf(String categoryId, String ancestorId) {
    final visited = <String>{};
    var current = categoryById(categoryId);
    while (current?.parentId != null && visited.add(current!.id)) {
      if (current.parentId == ancestorId) return true;
      current = categoryById(current.parentId!);
    }
    return false;
  }

  void selectCategory(String id) {
    final category = categoryById(id);
    if (phase != TimerPhase.idle ||
        category == null ||
        category.isArchived ||
        selectedCategoryId == id) {
      return;
    }
    _selectedCategoryId = id;
    notifyListeners();
    _schedulePersist();
  }

  void setPlannedMinutes(int minutes) {
    if (phase != TimerPhase.idle ||
        minutes <= 0 ||
        minutes > timerDialMinutes ||
        plannedMinutes == minutes) {
      return;
    }
    _plannedMinutes = minutes;
    _remainingSeconds = minutes * 60;
    _syncActiveTimerPreset();
    notifyListeners();
    _schedulePersist();
  }

  void selectTimerPreset(int index) {
    if (phase != TimerPhase.idle || index < 0 || index >= timerPresets.length) {
      return;
    }
    final preset = timerPresets[index];
    _activeTimerPresetIndex = index;
    _plannedMinutes = preset.minutes;
    _groupCount = preset.groupCount;
    _cycleCount = preset.cycleCount;
    _intervalMinutes = preset.cycleCount == 1 ? 0 : preset.intervalMinutes;
    _longIntervalMinutes = preset.groupCount == 1
        ? 0
        : preset.longIntervalMinutes;
    _recordIntervals = preset.recordIntervals;
    _remainingSeconds = plannedMinutes * 60;
    notifyListeners();
    _schedulePersist();
  }

  void renameTimerPreset(int index, String value) {
    final name = value.trim();
    if (phase != TimerPhase.idle ||
        index < 0 ||
        index >= timerPresets.length ||
        name.isEmpty ||
        name.length > 8 ||
        timerPresets[index].name == name) {
      return;
    }
    _timerPresets[index] = timerPresets[index].copyWith(name: name);
    notifyListeners();
    _schedulePersist();
  }

  void setTimerPresets(List<TimerPreset> presets) {
    if (phase != TimerPhase.idle || presets.length != 3) return;
    final normalized = <TimerPreset>[];
    for (final preset in presets) {
      final name = preset.name.trim();
      if (name.isEmpty ||
          name.length > 8 ||
          preset.minutes <= 0 ||
          preset.minutes > timerDialMinutes ||
          preset.groupCount <= 0 ||
          preset.groupCount > maxGroupCount ||
          preset.cycleCount <= 0 ||
          preset.cycleCount > maxCycleCount ||
          (preset.cycleCount == 1 && preset.intervalMinutes != 0) ||
          (preset.cycleCount > 1 &&
              (preset.intervalMinutes <= 0 ||
                  preset.intervalMinutes > maxIntervalMinutes)) ||
          (preset.groupCount == 1 && preset.longIntervalMinutes != 0) ||
          (preset.groupCount > 1 &&
              (preset.longIntervalMinutes <= 0 ||
                  preset.longIntervalMinutes > maxIntervalMinutes))) {
        return;
      }
      normalized.add(preset.copyWith(name: name));
    }
    _timerPresets
      ..clear()
      ..addAll(normalized);
    _activeTimerPresetIndex = null;
    notifyListeners();
    _schedulePersist();
  }

  void setCycleCount(int count) {
    if (phase != TimerPhase.idle ||
        count <= 0 ||
        count > maxCycleCount ||
        cycleCount == count) {
      return;
    }
    _cycleCount = count;
    if (count == 1) {
      _intervalMinutes = 0;
    } else if (intervalMinutes == 0) {
      _intervalMinutes = 5;
    }
    _syncActiveTimerPreset();
    notifyListeners();
    _schedulePersist();
  }

  void setGroupCount(int count) {
    if (phase != TimerPhase.idle ||
        count <= 0 ||
        count > maxGroupCount ||
        groupCount == count) {
      return;
    }
    _groupCount = count;
    if (count == 1) {
      _longIntervalMinutes = 0;
    } else if (longIntervalMinutes == 0) {
      _longIntervalMinutes = 15;
    }
    _syncActiveTimerPreset();
    notifyListeners();
    _schedulePersist();
  }

  void setIntervalMinutes(int minutes) {
    if (phase != TimerPhase.idle ||
        cycleCount == 1 ||
        minutes <= 0 ||
        minutes > maxIntervalMinutes ||
        intervalMinutes == minutes) {
      return;
    }
    _intervalMinutes = minutes;
    _syncActiveTimerPreset();
    notifyListeners();
    _schedulePersist();
  }

  void setLongIntervalMinutes(int minutes) {
    if (phase != TimerPhase.idle ||
        groupCount == 1 ||
        minutes <= 0 ||
        minutes > maxIntervalMinutes ||
        longIntervalMinutes == minutes) {
      return;
    }
    _longIntervalMinutes = minutes;
    _syncActiveTimerPreset();
    notifyListeners();
    _schedulePersist();
  }

  void setRecordIntervals(bool value) {
    if (phase != TimerPhase.idle || recordIntervals == value) return;
    _recordIntervals = value;
    _syncActiveTimerPreset();
    notifyListeners();
    _schedulePersist();
  }

  void _syncActiveTimerPreset() {
    final index = _activeTimerPresetIndex;
    if (index == null || index < 0 || index >= _timerPresets.length) return;
    _timerPresets[index] = _timerPresets[index].copyWith(
      minutes: plannedMinutes,
      groupCount: groupCount,
      cycleCount: cycleCount,
      intervalMinutes: intervalMinutes,
      longIntervalMinutes: longIntervalMinutes,
      recordIntervals: recordIntervals,
    );
  }

  void startTimer() {
    if (phase != TimerPhase.idle || selectedCategory == null) return;
    _currentCycle = 1;
    _currentGroup = 1;
    _beginTimerPhase(TimerPhase.running, DateTime.now());
    notifyListeners();
    _schedulePersist();
  }

  void stopTimer({bool saveInterrupted = true}) {
    if (phase == TimerPhase.idle) return;
    _updateRemaining();
    _ticker?.cancel();
    final actual = elapsedSeconds;
    if (saveInterrupted &&
        actual > 0 &&
        _sessionStartedAt != null &&
        (phase == TimerPhase.running || recordIntervals)) {
      final now = DateTime.now();
      _logs.insert(
        0,
        TimeLog(
          id: _newId(),
          categoryId: selectedCategoryId!,
          startedAt: _sessionStartedAt!,
          endedAt: now,
          plannedSeconds: currentPhaseSeconds,
          actualSeconds: actual,
          status: LogStatus.interrupted,
          kind: isBreak ? LogKind.interval : LogKind.focus,
          note: _breakLogNote(phase),
        ),
      );
      _syncPlanCompletions(now);
    }
    _resetTimer();
    unawaited(_platform?.cancelTimer());
    notifyListeners();
    _schedulePersist();
  }

  void addCategory({
    required String name,
    required int colorValue,
    required String iconKey,
    String? parentId,
  }) {
    final trimmedName = name.trim();
    final parent = parentId == null ? null : categoryById(parentId);
    if (trimmedName.isEmpty ||
        trimmedName.length > maxCategoryNameLength ||
        (parentId != null && (parent == null || parent.isArchived))) {
      return;
    }
    final category = FocusCategory(
      id: _newId(),
      name: trimmedName,
      colorValue: colorValue,
      iconKey: iconKey,
      parentId: parentId,
    );
    _categories.add(category);
    _selectedCategoryId ??= category.id;
    notifyListeners();
    _schedulePersist();
  }

  void updateCategory(
    FocusCategory category, {
    required String name,
    required int colorValue,
    required String iconKey,
    required String? parentId,
  }) {
    final trimmedName = name.trim();
    final parent = parentId == null ? null : categoryById(parentId);
    if (trimmedName.isEmpty ||
        trimmedName.length > maxCategoryNameLength ||
        parentId == category.id ||
        (parentId != null && parent == null) ||
        (parent != null && !category.isArchived && parent.isArchived) ||
        (parentId != null && isDescendantOf(parentId, category.id))) {
      return;
    }
    final index = _categories.indexWhere((item) => item.id == category.id);
    if (index == -1) return;
    _categories[index] = _categories[index].copyWith(
      name: trimmedName,
      colorValue: colorValue,
      iconKey: iconKey,
      parentId: parentId,
      clearParent: parentId == null,
    );
    if (category.id == selectedCategoryId && phase != TimerPhase.idle) {
      _showTimerNotification();
    }
    notifyListeners();
    _schedulePersist();
  }

  bool setCategoryArchived(FocusCategory category, bool archived) {
    final index = _categories.indexWhere((item) => item.id == category.id);
    if (index == -1) return false;
    final current = _categories[index];
    if (current.isArchived == archived) return false;
    final affectedIds = _subtreeIds(category.id);
    if (archived) {
      final remaining = activeCategories.where(
        (item) => !affectedIds.contains(item.id),
      );
      if (remaining.isEmpty ||
          (phase != TimerPhase.idle &&
              affectedIds.contains(selectedCategoryId))) {
        return false;
      }
    } else {
      var parentId = current.parentId;
      while (parentId != null) {
        affectedIds.add(parentId);
        parentId = categoryById(parentId)?.parentId;
      }
    }
    for (var i = 0; i < _categories.length; i++) {
      if (affectedIds.contains(_categories[i].id)) {
        _categories[i] = _categories[i].copyWith(isArchived: archived);
      }
    }
    _ensureSelectedCategory();
    notifyListeners();
    _schedulePersist();
    return true;
  }

  bool deleteCategory(FocusCategory category) {
    if (categoryById(category.id) == null) return false;
    final affectedIds = _subtreeIds(category.id);
    if ((phase != TimerPhase.idle &&
            affectedIds.contains(selectedCategoryId)) ||
        activeCategories.every((item) => affectedIds.contains(item.id))) {
      return false;
    }
    _categories.removeWhere((item) => affectedIds.contains(item.id));
    _logs.removeWhere((log) => affectedIds.contains(log.categoryId));
    _plans.removeWhere((plan) => affectedIds.contains(plan.categoryId));
    _ensureSelectedCategory();
    notifyListeners();
    _schedulePersist();
    return true;
  }

  void addManualLog({
    required String categoryId,
    required int minutes,
    String? note,
  }) {
    final category = categoryById(categoryId);
    if (category == null ||
        category.isArchived ||
        minutes <= 0 ||
        minutes > maxMinutes) {
      return;
    }
    final now = DateTime.now();
    _logs.insert(
      0,
      TimeLog(
        id: _newId(),
        categoryId: categoryId,
        startedAt: now.subtract(Duration(minutes: minutes)),
        endedAt: now,
        plannedSeconds: minutes * 60,
        actualSeconds: minutes * 60,
        status: LogStatus.manuallyAdded,
        note: note?.trim().isEmpty == true ? null : note?.trim(),
      ),
    );
    _syncPlanCompletions(now);
    notifyListeners();
    _schedulePersist();
  }

  void deleteLog(String id) {
    final index = _logs.indexWhere((log) => log.id == id);
    if (index == -1) return;
    final date = _logs[index].startedAt;
    _logs.removeAt(index);
    _syncPlanCompletions(date);
    notifyListeners();
    _schedulePersist();
  }

  void addPlan({
    required DateTime startDate,
    required DateTime endDate,
    required String categoryId,
    required int plannedMinutes,
  }) {
    final category = categoryById(categoryId);
    if (category == null ||
        category.isArchived ||
        endDate.isBefore(startDate) ||
        plannedMinutes <= 0 ||
        plannedMinutes > maxMinutes) {
      return;
    }
    _plans.add(
      DailyPlan(
        id: _newId(),
        startDate: DateTime(startDate.year, startDate.month, startDate.day),
        endDate: DateTime(endDate.year, endDate.month, endDate.day),
        categoryId: categoryId,
        plannedMinutes: plannedMinutes,
      ),
    );
    _syncPlanCompletions(DateTime.now());
    _plans.sort((a, b) => a.startDate.compareTo(b.startDate));
    notifyListeners();
    _schedulePersist();
  }

  void setPlanCompleted(String id, DateTime date, bool completed) {
    final index = _plans.indexWhere((plan) => plan.id == id);
    if (index == -1 ||
        !_plans[index].occursOn(date) ||
        _plans[index].isCompletedOn(date) == completed) {
      return;
    }
    final plan = _plans[index];
    _plans[index] = plan.withCompletion(date, completed);
    if (completed) {
      final startedAt = DateTime(date.year, date.month, date.day);
      _logs.insert(
        0,
        TimeLog(
          id: 'plan:${plan.id}:${DailyPlan.dayKey(date)}',
          categoryId: plan.categoryId,
          startedAt: startedAt,
          endedAt: startedAt.add(Duration(minutes: plan.plannedMinutes)),
          plannedSeconds: plan.plannedMinutes * 60,
          actualSeconds: plan.plannedMinutes * 60,
          status: LogStatus.completed,
          note: '每日计划完成',
        ),
      );
      _logs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } else {
      final generatedId = 'plan:${plan.id}:${DailyPlan.dayKey(date)}';
      final previousLength = _logs.length;
      _logs.removeWhere((log) => log.id == generatedId);
      if (_logs.length == previousLength) {
        final legacyIndex = _logs.indexWhere(
          (log) =>
              log.categoryId == plan.categoryId &&
              DailyPlan.dayKey(log.startedAt) == DailyPlan.dayKey(date) &&
              log.actualSeconds == plan.plannedMinutes * 60 &&
              log.note == '每日计划完成',
        );
        if (legacyIndex != -1) _logs.removeAt(legacyIndex);
      }
    }
    _syncPlanCompletions(date);
    notifyListeners();
    _schedulePersist();
  }

  void deletePlan(String id) {
    final previousLength = _plans.length;
    _plans.removeWhere((plan) => plan.id == id);
    if (_plans.length == previousLength) return;
    notifyListeners();
    _schedulePersist();
  }

  void setThemePreference(AppThemePreference preference) {
    if (_themePreference == preference) return;
    _themePreference = preference;
    notifyListeners();
    _schedulePersist();
  }

  void setAccentColor(int colorValue) {
    if (_accentColorValue == colorValue) return;
    _accentColorValue = colorValue;
    notifyListeners();
    _schedulePersist();
  }

  Future<void> chooseBackgroundImage() async {
    final path = await _platform?.pickBackgroundImage();
    if (path == null || path.isEmpty) return;
    _backgroundImagePath = path;
    notifyListeners();
    _schedulePersist();
  }

  void clearBackgroundImage() {
    if (_backgroundImagePath == null) return;
    _backgroundImagePath = null;
    notifyListeners();
    _schedulePersist();
  }

  Future<void> requestNotificationPermission() async {
    await _platform?.requestNotificationPermission();
  }

  Future<Map<String, bool>> notificationStatus() async {
    return await _platform?.notificationStatus() ?? const {};
  }

  Future<void> openCompletionNotificationSettings() async {
    await _platform?.openCompletionNotificationSettings();
  }

  Future<void> markNotificationSetupGuideShown() async {
    await _platform?.markNotificationSetupGuideShown();
  }

  Future<void> markBatteryOptimizationGuideShown() async {
    await _platform?.markBatteryOptimizationGuideShown();
  }

  Future<void> showCompletionNotificationTest() async {
    await _platform?.showCompletionNotificationTest();
  }

  Future<void> requestBatteryOptimizationExemption() async {
    await _platform?.requestBatteryOptimizationExemption();
  }

  Future<void> setFloatingTimerEnabled(bool enabled) async {
    if (floatingTimerEnabled == enabled) return;
    _floatingTimerEnabled = enabled;
    notifyListeners();
    _schedulePersist();
    if (!enabled) {
      await _platform?.hideFloatingTimer();
      return;
    }
    if (!await (_platform?.floatingTimerPermissionGranted() ??
        Future.value(false))) {
      await _platform?.requestFloatingTimerPermission();
    }
    _showFloatingTimer();
  }

  void setAppInForeground(bool foreground) {
    if (_appInForeground == foreground) return;
    _appInForeground = foreground;
    if (foreground) {
      unawaited(_platform?.hideFloatingTimer());
    } else {
      _showFloatingTimer();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
      if (remainingSeconds <= 0) {
        _completeTimer();
      } else {
        notifyListeners();
      }
    });
  }

  void _updateRemaining() {
    final target = _targetEndAt;
    if (target == null) return;
    final milliseconds = target.difference(DateTime.now()).inMilliseconds;
    _remainingSeconds = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  void _completeTimer() {
    _ticker?.cancel();
    final endedAt = _targetEndAt ?? DateTime.now();
    final finished = _advanceTimerPhase(endedAt);
    if (finished) {
      unawaited(_platform?.completeTimer());
    } else {
      _startTicker();
      _showTimerNotification();
    }
    notifyListeners();
    _schedulePersist();
  }

  bool _advanceTimerPhase(DateTime endedAt) {
    final completedPhase = phase;
    final start =
        _sessionStartedAt ??
        endedAt.subtract(Duration(seconds: currentPhaseSeconds));
    if (completedPhase == TimerPhase.running || recordIntervals) {
      _logs.insert(
        0,
        TimeLog(
          id: _newId(),
          categoryId: selectedCategoryId!,
          startedAt: start,
          endedAt: endedAt,
          plannedSeconds: currentPhaseSeconds,
          actualSeconds: currentPhaseSeconds,
          status: LogStatus.completed,
          kind: completedPhase == TimerPhase.running
              ? LogKind.focus
              : LogKind.interval,
          note: _breakLogNote(completedPhase),
        ),
      );
      _syncPlanCompletions(endedAt);
    }
    if (completedPhase == TimerPhase.running && currentCycle < cycleCount) {
      _setTimerPhase(TimerPhase.interval, endedAt);
    } else if (completedPhase == TimerPhase.running && groupCount > 1) {
      _setTimerPhase(TimerPhase.longInterval, endedAt);
    } else if (completedPhase == TimerPhase.running) {
      _resetTimer();
      return true;
    } else if (completedPhase == TimerPhase.interval) {
      _currentCycle++;
      _setTimerPhase(TimerPhase.running, endedAt);
    } else if (completedPhase == TimerPhase.longInterval) {
      if (currentGroup < groupCount) {
        _currentGroup++;
        _currentCycle = 1;
        _setTimerPhase(TimerPhase.running, endedAt);
      } else {
        _resetTimer();
        return true;
      }
    } else {
      _resetTimer();
      return true;
    }
    return false;
  }

  void _beginTimerPhase(TimerPhase nextPhase, DateTime startedAt) {
    _setTimerPhase(nextPhase, startedAt);
    _startTicker();
    _showTimerNotification();
  }

  void _setTimerPhase(TimerPhase nextPhase, DateTime startedAt) {
    _phase = nextPhase;
    _remainingSeconds = currentPhaseSeconds;
    _sessionStartedAt = startedAt;
    _targetEndAt = startedAt.add(Duration(seconds: remainingSeconds));
  }

  @visibleForTesting
  void completeCurrentPhaseForTesting() {
    if (phase != TimerPhase.idle) _completeTimer();
  }

  void _resetTimer() {
    _phase = TimerPhase.idle;
    _remainingSeconds = plannedMinutes * 60;
    _sessionStartedAt = null;
    _targetEndAt = null;
    _currentCycle = 1;
    _currentGroup = 1;
  }

  void _restoreTimer(Map<String, Object?>? timerData) {
    _remainingSeconds = plannedMinutes * 60;
    if (timerData == null) return;

    _phase = _parseTimerPhase(timerData['phase']);
    _currentCycle = (timerData['currentCycle'] as int? ?? 1)
        .clamp(1, cycleCount)
        .toInt();
    _currentGroup = (timerData['currentGroup'] as int? ?? 1)
        .clamp(1, groupCount)
        .toInt();
    if ((phase == TimerPhase.interval && cycleCount == 1) ||
        (phase == TimerPhase.longInterval && groupCount == 1)) {
      _resetTimer();
      return;
    }
    final savedRemaining = timerData['remainingSeconds'] as int?;
    final maximumSeconds = currentPhaseSeconds;
    if (savedRemaining == null) {
      _remainingSeconds = maximumSeconds;
    } else if (savedRemaining < 0) {
      _remainingSeconds = 0;
    } else if (savedRemaining > maximumSeconds) {
      _remainingSeconds = maximumSeconds;
    } else {
      _remainingSeconds = savedRemaining;
    }
    final start = timerData['sessionStartedAt'] as String?;
    final target = timerData['targetEndAt'] as String?;
    _sessionStartedAt = start == null ? null : DateTime.tryParse(start);
    _targetEndAt = target == null ? null : DateTime.tryParse(target);

    if (phase == TimerPhase.idle) {
      _resetTimer();
    } else if (_sessionStartedAt == null) {
      _resetTimer();
    } else if (_targetEndAt != null) {
      _resumeRestoredTimer();
    } else if (phase == TimerPhase.running) {
      // Older versions could persist a paused timer without a deadline.
      _targetEndAt = DateTime.now().add(Duration(seconds: remainingSeconds));
      _startTicker();
      _showTimerNotification();
    } else {
      _resetTimer();
    }
  }

  void _resumeRestoredTimer() {
    final now = DateTime.now();
    while (phase != TimerPhase.idle &&
        _targetEndAt != null &&
        !_targetEndAt!.isAfter(now)) {
      if (_advanceTimerPhase(_targetEndAt!)) break;
    }
    if (phase != TimerPhase.idle) {
      _updateRemaining();
      _startTicker();
      _showTimerNotification();
    }
  }

  List<FocusCategory> _orderedCategories({required bool archived}) {
    final matches = _categories
        .where((category) => category.isArchived == archived)
        .toList();
    final ids = matches.map((category) => category.id).toSet();
    final result = <FocusCategory>[];

    void addBranch(FocusCategory category) {
      result.add(category);
      for (final child in matches.where(
        (item) => item.parentId == category.id,
      )) {
        addBranch(child);
      }
    }

    for (final category in matches.where(
      (item) => item.parentId == null || !ids.contains(item.parentId),
    )) {
      addBranch(category);
    }
    return result;
  }

  Set<String> _subtreeIds(String categoryId) {
    final ids = <String>{categoryId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final category in _categories) {
        if (category.parentId != null &&
            ids.contains(category.parentId) &&
            ids.add(category.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  void _repairCategoryParents() {
    for (var index = 0; index < _categories.length; index++) {
      final category = _categories[index];
      final visited = <String>{category.id};
      var parentId = category.parentId;
      var valid = true;
      while (parentId != null) {
        final parent = categoryById(parentId);
        if (parent == null || !visited.add(parentId)) {
          valid = false;
          break;
        }
        parentId = parent.parentId;
      }
      if (!valid) {
        _categories[index] = category.copyWith(clearParent: true);
      }
    }
  }

  void _ensureSelectedCategory() {
    final selected = categoryById(selectedCategoryId ?? '');
    if (selected == null || selected.isArchived) {
      _selectedCategoryId = activeCategories.isEmpty
          ? null
          : activeCategories.first.id;
    }
  }

  bool _syncPlanCompletions(DateTime date) {
    final secondsByCategory = <String, int>{};
    for (final log in _logs) {
      if (DailyPlan.dayKey(log.startedAt) != DailyPlan.dayKey(date)) continue;
      if (log.kind == LogKind.interval) continue;
      secondsByCategory.update(
        log.categoryId,
        (seconds) => seconds + log.actualSeconds,
        ifAbsent: () => log.actualSeconds,
      );
    }
    var changed = false;
    for (var index = 0; index < _plans.length; index++) {
      final plan = _plans[index];
      if (!plan.occursOn(date)) continue;
      final completed =
          (secondsByCategory[plan.categoryId] ?? 0) >= plan.plannedMinutes * 60;
      if (plan.isCompletedOn(date) == completed) continue;
      _plans[index] = plan.withCompletion(date, completed);
      changed = true;
    }
    return changed;
  }

  void _scheduleMidnightRefresh() {
    _midnightRefresh?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnightRefresh = Timer(tomorrow.difference(now), () {
      final changed = _syncPlanCompletions(DateTime.now());
      notifyListeners();
      if (changed) _schedulePersist();
      _scheduleMidnightRefresh();
    });
  }

  Map<String, Object?> _dataSnapshot() => {
    'categories': _categories.map((item) => item.toJson()).toList(),
    'logs': _logs.map((item) => item.toJson()).toList(),
    'plans': _plans.map((item) => item.toJson()).toList(),
    'selectedCategoryId': selectedCategoryId,
    'plannedMinutes': plannedMinutes,
    'timerPresets': timerPresets.map((preset) => preset.toJson()).toList(),
    'themePreference': themePreference.name,
    'accentColorValue': accentColorValue,
    'backgroundImagePath': backgroundImagePath,
    'floatingTimerEnabled': floatingTimerEnabled,
    'cycleCount': cycleCount,
    'groupCount': groupCount,
    'intervalMinutes': intervalMinutes,
    'longIntervalMinutes': longIntervalMinutes,
    'recordIntervals': recordIntervals,
    'timer': {
      'phase': phase.name,
      'remainingSeconds': remainingSeconds,
      'sessionStartedAt': _sessionStartedAt?.toIso8601String(),
      'targetEndAt': _targetEndAt?.toIso8601String(),
      'currentCycle': currentCycle,
      'currentGroup': currentGroup,
    },
  };

  Future<void> _persist() => _storage.write(_dataSnapshot());

  Future<Map<String, Object?>> exportPortableData() async {
    await _pendingPersist;
    final data = _dataSnapshot();
    data['timer'] = {
      'phase': TimerPhase.idle.name,
      'remainingSeconds': 25 * 60,
      'sessionStartedAt': null,
      'targetEndAt': null,
      'currentCycle': 1,
      'currentGroup': 1,
    };
    final backgroundPath = _backgroundImagePath;
    data.remove('backgroundImagePath');
    if (backgroundPath != null) {
      try {
        final bytes = await File(backgroundPath).readAsBytes();
        data['backgroundImage'] = {
          'encoding': 'base64',
          'bytes': base64Encode(bytes),
        };
      } on FileSystemException catch (error) {
        throw StateError('无法读取自定义背景图片：${error.message}');
      }
    }
    return data;
  }

  Future<void> importPortableData(Map<String, Object?> source) async {
    final data = (jsonDecode(jsonEncode(source)) as Map)
        .cast<String, Object?>();
    final background = (data.remove('backgroundImage') as Map?)
        ?.cast<String, Object?>();
    String? restoredBackgroundPath;
    if (background?['encoding'] == 'base64' && background?['bytes'] is String) {
      final platform = _platform;
      if (platform == null) throw StateError('当前平台无法恢复背景图片');
      restoredBackgroundPath = await platform.saveBackgroundImage(
        base64Decode(background!['bytes']! as String),
      );
      if (restoredBackgroundPath == null) {
        throw StateError('背景图片恢复失败');
      }
    }
    data['backgroundImagePath'] = restoredBackgroundPath;
    data['timer'] = {
      'phase': TimerPhase.idle.name,
      'remainingSeconds': 25 * 60,
      'sessionStartedAt': null,
      'targetEndAt': null,
      'currentCycle': 1,
      'currentGroup': 1,
    };
    _ticker?.cancel();
    await _platform?.cancelTimer();
    await _storage.write(data);
    await load();
  }

  void _schedulePersist() {
    _pendingPersist = _pendingPersist.then(
      (_) async {
        await _persist();
        webDav?.markLocalChanged();
      },
      onError: (_, _) async {
        await _persist();
        webDav?.markLocalChanged();
      },
    );
    unawaited(_pendingPersist.catchError((Object _) {}));
  }

  String _newId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    _lastGeneratedId = timestamp > _lastGeneratedId
        ? timestamp
        : _lastGeneratedId + 1;
    return _lastGeneratedId.toString();
  }

  void _rememberExistingIds() {
    final ids = [
      ..._categories.map((category) => category.id),
      ..._logs.map((log) => log.id),
      ..._plans.map((plan) => plan.id),
    ];
    for (final id in ids) {
      final value = int.tryParse(id);
      if (value != null && value > _lastGeneratedId) {
        _lastGeneratedId = value;
      }
    }
  }

  void _loadDefaults() {
    _ticker?.cancel();
    _categories
      ..clear()
      ..addAll(_defaultCategories);
    _logs.clear();
    _plans.clear();
    _phase = TimerPhase.idle;
    _plannedMinutes = 25;
    _timerPresets
      ..clear()
      ..addAll(_defaultTimerPresets);
    _remainingSeconds = plannedMinutes * 60;
    _cycleCount = 4;
    _groupCount = 1;
    _intervalMinutes = 5;
    _longIntervalMinutes = 0;
    _recordIntervals = false;
    _activeTimerPresetIndex = null;
    _currentCycle = 1;
    _currentGroup = 1;
    _selectedCategoryId = _categories.first.id;
    _sessionStartedAt = null;
    _targetEndAt = null;
    _themePreference = AppThemePreference.system;
    _accentColorValue = defaultAccentColorValue;
    _backgroundImagePath = null;
    _floatingTimerEnabled = false;
  }

  static int _validPlannedMinutes(Object? value) {
    return value is int && value > 0 && value <= timerDialMinutes ? value : 25;
  }

  static List<TimerPreset> _parseTimerPresets(Object? value) {
    if (value is! List || value.length != 3) return _defaultTimerPresets;
    final presets = <TimerPreset>[];
    for (final item in value) {
      if (item is! Map) return _defaultTimerPresets;
      final name = item['name'];
      final minutes = item['minutes'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.trim().length > 8 ||
          minutes is! int ||
          minutes <= 0 ||
          minutes > timerDialMinutes) {
        return _defaultTimerPresets;
      }
      final cycleCount = _validCycleCount(item['cycleCount']);
      final groupCount = _validGroupCount(item['groupCount']);
      presets.add(
        TimerPreset(
          name: name.trim(),
          minutes: minutes,
          groupCount: groupCount,
          cycleCount: cycleCount,
          intervalMinutes: cycleCount == 1
              ? 0
              : _validIntervalMinutes(item['intervalMinutes']),
          longIntervalMinutes: groupCount == 1
              ? 0
              : _validLongIntervalMinutes(item['longIntervalMinutes']),
          recordIntervals: item['recordIntervals'] == true,
        ),
      );
    }
    return presets;
  }

  static const _defaultTimerPresets = [
    TimerPreset(name: '短时', minutes: 15),
    TimerPreset(name: '标准', minutes: 25),
    TimerPreset(name: '长时', minutes: 45),
  ];

  static int _validCycleCount(Object? value) {
    return value is int && value > 0 && value <= maxCycleCount ? value : 4;
  }

  static int _validGroupCount(Object? value) {
    return value is int && value > 0 && value <= maxGroupCount ? value : 1;
  }

  static int _validIntervalMinutes(Object? value) {
    return value is int && value > 0 && value <= maxIntervalMinutes ? value : 5;
  }

  static int _validLongIntervalMinutes(Object? value) {
    return value is int && value > 0 && value <= maxIntervalMinutes
        ? value
        : 15;
  }

  static TimerPhase _parseTimerPhase(Object? value) {
    if (value == TimerPhase.longInterval.name) return TimerPhase.longInterval;
    if (value == TimerPhase.interval.name) return TimerPhase.interval;
    return value == 'running' || value == 'paused'
        ? TimerPhase.running
        : TimerPhase.idle;
  }

  static String? _breakLogNote(TimerPhase phase) => switch (phase) {
    TimerPhase.interval => '组内休息',
    TimerPhase.longInterval => '长休息',
    _ => null,
  };

  static AppThemePreference _parseThemePreference(Object? value) {
    for (final preference in AppThemePreference.values) {
      if (preference.name == value) return preference;
    }
    return AppThemePreference.system;
  }

  void _showTimerNotification() {
    final category = selectedCategory;
    if (category == null || phase == TimerPhase.idle) return;
    unawaited(
      _platform?.showTimer(
        categoryName: categoryPath(category),
        iconKey: category.iconKey,
        colorValue: category.colorValue,
        remainingSeconds: remainingSeconds,
        totalSeconds: currentPhaseSeconds,
        phase: phase.name,
        currentCycle: currentCycle,
        cycleCount: cycleCount,
        currentGroup: currentGroup,
        groupCount: groupCount,
        focusSeconds: plannedMinutes * 60,
        intervalSeconds: intervalMinutes * 60,
        longIntervalSeconds: longIntervalMinutes * 60,
      ),
    );
    _showFloatingTimer();
  }

  void _showFloatingTimer() {
    final category = selectedCategory;
    if (_appInForeground ||
        !floatingTimerEnabled ||
        category == null ||
        phase == TimerPhase.idle) {
      return;
    }
    unawaited(
      _platform?.showFloatingTimer(
        categoryName: switch (phase) {
          TimerPhase.interval => '休息',
          TimerPhase.longInterval => '长休息',
          _ => categoryPath(category),
        },
        iconKey: category.iconKey,
        colorValue: category.colorValue,
        remainingSeconds: remainingSeconds,
      ),
    );
  }

  static const _defaultCategories = [
    FocusCategory(
      id: 'work',
      name: '工作',
      colorValue: 0xFFE85D4A,
      iconKey: 'work',
    ),
    FocusCategory(
      id: 'study',
      name: '学习',
      colorValue: 0xFF4D7CFE,
      iconKey: 'study',
    ),
    FocusCategory(
      id: 'reading',
      name: '阅读',
      colorValue: 0xFF8B5CF6,
      iconKey: 'reading',
    ),
    FocusCategory(
      id: 'exercise',
      name: '运动',
      colorValue: 0xFF19A974,
      iconKey: 'exercise',
    ),
  ];

  @override
  void dispose() {
    _ticker?.cancel();
    _midnightRefresh?.cancel();
    webDav?.dispose();
    super.dispose();
  }
}
