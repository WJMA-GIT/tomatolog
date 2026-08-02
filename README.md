# 时间日志

一款使用 Flutter 编写的分类番茄钟与时间日志 App。

## 已实现

- 15、25、45 分钟专注计时
- 计时暂停、继续、中断记录
- 按真实结束时间计算剩余时间，应用回到前台后不会漂移
- 新建、编辑、归档和恢复分类
- 分类颜色与图标
- 自动时间日志与手动补记
- 起止日期内每日循环的计划，可设置每天的开始和结束时间
- 今日总时长和分类用时
- 日历与日、周、月统计，包含分类占比环形图
- Android 原生分类倒计时通知；支持 Android 16 实况通知与首次启动授权
- 浅色、纯黑暗色主题和自定义背景图
- 本地持久化及未完成计时恢复

## 本地运行

1. 安装 Flutter stable、Android Studio 和 Android SDK。
2. 在 VS Code 安装 `Flutter` 扩展（会同时安装 `Dart` 扩展）。
3. 确认 `flutter --version` 可正常执行，然后在项目目录运行：

```powershell
flutter pub get
flutter run
```

验证代码：

```powershell
flutter analyze
flutter test
```

> `.dart_tool/`、`build/`、`.idea/`、`*.iml` 和 `android/local.properties`
> 均为本机生成内容，不应提交到项目。

## 项目结构

```text
lib/
  controllers/  业务状态、计时与持久化协调
  models/       分类、计划和时间日志数据模型
  screens/      今天、计时、日志、统计、分类、设置
  services/     本地存储与原生平台桥接
  ui/           通用显示工具
```
