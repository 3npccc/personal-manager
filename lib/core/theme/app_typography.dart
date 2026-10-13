import 'dart:io';

import 'package:flutter/material.dart';

/// 全局字体层级：**唯一**的字重来源。
///
/// ## 为什么要有这个文件
///
/// 之前的代码把 `copyWith(fontWeight: ...)` 散落在 56 处（w600 × 50、
/// w700 × 3、w500 × 1、normal × 2），结果是**同级别的标题在不同页面粗细不一样**，
/// 视觉上"加粗与正常混用"。
///
/// 根因不只是"不统一"，还有**中文字体的字重现实**：
/// 微软雅黑（Windows 默认中文字体，`msyh.ttc`）只提供三档真实字重 ——
/// `Light`（msyhl）/ `Regular`（msyh）/ `Bold`（msyhbd），**没有 Medium**。
/// 因此：
///   - `w500` → 被 Flutter **合成**（假粗），边缘发虚、看起来"糊"
///   - `w600` / `w700` → 都落到 `Bold`，**两者视觉完全相同**，纯属重复
///
/// ## 本项目色字重铁律（两级制）
///
/// - **标题类**：一律 [titleWeight]（`w600`，渲染为雅黑 Bold）
/// - **正文类**：一律 [bodyWeight]（`w400`，渲染为雅黑 Regular）
///
/// **不再使用** `w500` / `w700` / `w300`。需要强调时，用**字号、颜色、
/// 或 [emphasis] helper** 来表达，而不是调字重。
///
/// ## 用法
///
/// ```dart
/// // 直接取语义样式
/// Text('收藏夹', style: AppTypography.sectionTitle)
///
/// // 在已有 textTheme 基础上加标题粗细（推荐，跟随主题字号）
/// Text('收藏夹', style: AppTypography.title(context))
///
/// // 表单字段标签（统一角色，见 AppTextStyles）
/// Text('优先级', style: AppTextStyles.fieldLabel(context))
/// ```
class AppTypography {
  AppTypography._();

  /// 标题字重 —— **全项目唯一允许的"加粗"**。
  ///
  /// 选 `w600` 而非 `w700` 的原因：在微软雅黑上二者都映射到 Bold，
  /// 视觉无差异；统一用 w600 可以杜绝"有人写 w700、有人写 w600"的分裂。
  static const FontWeight titleWeight = FontWeight.w600;

  /// 正文字重 —— 全项目唯一允许的"正常"。
  static const FontWeight bodyWeight = FontWeight.w400;

  /// Windows 上的首选中文字体族。
  ///
  /// `Microsoft YaHei UI` 是 Windows 7+ 的界面版雅黑，比 `Microsoft YaHei`
  /// 在小字号下更清晰。**不需要打包字体文件**（系统自带），启动快、体积零增加。
  ///
  /// 非 Windows 平台返回 null —— 让系统自己选（Android 会用 Noto Sans CJK）。
  ///
  /// 【为什么是 getter 不是 const】`Platform.isWindows` 是运行期判断，
  /// 不能用于 `const` 初始化。
  static String? get fontFamily =>
      Platform.isWindows ? 'Microsoft YaHei UI' : null;

  /// 用主题字号 + 标题字重，得到"标题样式"。
  ///
  /// 比 `theme.textTheme.titleMedium?.copyWith(fontWeight: ...)` 更好读，
  /// 也把字重收口到一处（将来要改全局加粗程度，只改 [titleWeight]）。
  static TextStyle? title(BuildContext context, {TextStyle? base}) {
    final t = base ?? Theme.of(context).textTheme.titleMedium;
    return t?.copyWith(fontWeight: titleWeight);
  }

  /// 标题样式：区块标题（如「今日待办」）
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: titleWeight,
    height: 1.35,
  );

  /// 标题样式：卡片内的小标题（如待办标题）
  static const TextStyle itemTitle = TextStyle(
    fontSize: 15,
    fontWeight: titleWeight,
    height: 1.35,
  );

  /// 正文样式：描述、摘要
  static const TextStyle body = TextStyle(
    fontSize: 13,
    fontWeight: bodyWeight,
    height: 1.45,
  );

  /// 标签样式：小号说明文字（如日期、场景）
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: bodyWeight,
    height: 1.3,
  );

  /// 数值样式：统计卡的大数字（等宽数字，避免跳动）
  static const TextStyle statValue = TextStyle(
    fontWeight: titleWeight,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    height: 1.15,
  );

  /// 把 [style] 的字重强制为标题字重（保留其余属性）。
  ///
  /// 用于"我已有一个来自 textTheme 的样式，只想让它变成标题"的场景。
  static TextStyle? asTitle(TextStyle? style) =>
      style?.copyWith(fontWeight: titleWeight);

  /// 把 [style] 的字重强制为正常字重（保留其余属性）。
  static TextStyle? asBody(TextStyle? style) =>
      style?.copyWith(fontWeight: bodyWeight);

  /// 生成挂到 `ThemeData.textTheme` 的完整排版方案。
  ///
  /// 思路：以 Material 3 默认的 [Typography] 为底（保留其字号阶梯），
  /// 只**统一收紧字重** —— 所有 `title*` / `headline*` 用 [titleWeight]，
  /// 所有 `body*` / `label*` 用 [bodyWeight]。这样即使某处直接用了
  /// `theme.textTheme.titleSmall`，粗细也是对的，不会再出现分裂。
  static TextTheme applyTo(TextTheme base) {
    TextStyle? t(TextStyle? s) => s?.copyWith(fontWeight: titleWeight);
    TextStyle? b(TextStyle? s) => s?.copyWith(fontWeight: bodyWeight);

    return base.copyWith(
      // 标题族：加粗
      displayLarge: t(base.displayLarge),
      displayMedium: t(base.displayMedium),
      displaySmall: t(base.displaySmall),
      headlineLarge: t(base.headlineLarge),
      headlineMedium: t(base.headlineMedium),
      headlineSmall: t(base.headlineSmall),
      titleLarge: t(base.titleLarge),
      titleMedium: t(base.titleMedium),
      titleSmall: t(base.titleSmall),
      // 正文 / 标签族：正常
      bodyLarge: b(base.bodyLarge),
      bodyMedium: b(base.bodyMedium),
      bodySmall: b(base.bodySmall),
      labelLarge: b(base.labelLarge),
      labelMedium: b(base.labelMedium),
      labelSmall: b(base.labelSmall),
    );
  }
}

/// 语义化文字角色：**同一个角色在哪儿都长一样**。
///
/// ## 为什么还需要这一层
///
/// [AppTypography] 解决了"字重两级制"，但还有一个更深的问题：
/// 同一屏里混用了**多套风格**。典型是表单页 ——
///
/// - 字段标签：`labelLarge`(14px) + 粗 + **主色蓝**
/// - 输入内容：`bodyLarge`(16px) + 正常 + 黑
/// - 辅助说明：`bodySmall`(12px) + 正常 + 灰
///
/// 三套字号、两种粗细、三种颜色挤在同一屏 → 视觉杂乱，
/// 这正是用户反馈的"加粗与正常混用"。
///
/// 本类把常用的文字角色**固定下来**，用 [fromTheme] 取角色的样式，
/// 让同一角色处处一致。新增 UI 时**优先从这里取**，不要临时 `copyWith`。
///
/// ## 字号阶梯（单一体系）
///
/// ```
/// 22  页面大标题      pageTitle
/// 16  区块标题        sectionTitle
/// 15  列表项标题      itemTitle
/// 13  正文 / 字段标签 body / fieldLabel
/// 12  辅助说明        caption
/// 11  极小标签        micro
/// ```
///
/// 注意 **字段标签(13) 与正文(13) 同号** —— 标签不靠"加大字号"取胜，
/// 而是靠**加粗 + 中性灰**和正文区分，这样一屏内只有一个字号主干。
class AppTextStyles {
  AppTextStyles._();

  /// 页面大标题（AppBar 标题 / 页面顶部）
  static TextStyle pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: AppTypography.titleWeight,
            height: 1.25,
          );

  /// 区块标题（如「今日待办」）
  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
            fontWeight: AppTypography.titleWeight,
            height: 1.3,
          );

  /// 列表项 / 卡片标题
  static TextStyle itemTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
            fontWeight: AppTypography.titleWeight,
            height: 1.35,
          );

  /// 正文（描述、摘要）
  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontWeight: AppTypography.bodyWeight,
            height: 1.45,
          );

  /// 表单字段标签 —— **全项目统一**。
  ///
  /// 关键：用**中性灰 + 略小字号**，不用主色、不用更大字号。
  /// 之前各表单页用的是 `labelLarge`(14) + 主色蓝 + w600，太抢眼，
  /// 与内容区打架。改成 `13px + onSurfaceVariant + w600` 后，
  /// 标签安静地待在上方，视线自然落到输入内容上。
  static TextStyle fieldLabel(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      fontWeight: AppTypography.titleWeight,
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.3,
    );
  }

  /// 辅助说明 / 次要信息（日期、场景、提示）
  static TextStyle caption(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall!.copyWith(
      fontWeight: AppTypography.bodyWeight,
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
  }

  /// 极小标签（标签芯、角标）
  static TextStyle micro(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
            fontWeight: AppTypography.bodyWeight,
            height: 1.3,
          );

  /// 统计数值（大数字，等宽避免跳动）
  static TextStyle statValue(BuildContext context, {bool dense = false}) {
    final theme = Theme.of(context);
    final base =
        dense ? theme.textTheme.titleLarge! : theme.textTheme.headlineMedium!;
    return base.copyWith(
      fontWeight: AppTypography.titleWeight,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      height: 1.15,
    );
  }
}
