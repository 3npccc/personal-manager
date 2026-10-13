// 数据表定义（drift）
//
// 【重要约定】
// 1. 金额一律用整数「分」存储（¥12.50 → 1250），禁止用 double，避免浮点误差。
// 2. 场景 scene 用 TEXT 存枚举的 code（study/work/life），不存中文。
// 3. 所有时间用 DateTime（drift 内部存为 Unix 时间戳）。
// 4. 改本文件后必须执行：
//      dart run build_runner build --delete-conflicting-outputs
//
// 【表清单】共 15 张
//   通用 4：Todos / Notes / LedgerRecords / Categories
//   学习 4：Books / Courses / StudyCheckins / StudyGoals
//   工作 3：Projects / WorkLogs / WorkJournals
//   生活 4：Habits / HabitCheckins / HealthRecords / LifeMemos

import 'package:drift/drift.dart';

// ============================================================
// 通用表（4 张）
// ============================================================

/// 待办表
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 标题（必填）
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// 详细说明（可选）
  TextColumn get description => text().nullable()();

  /// 优先级：0 低 / 1 中 / 2 高
  IntColumn get priority => integer().withDefault(const Constant(1))();

  /// 所属场景：study / work / life
  TextColumn get scene => text().withLength(max: 16)();

  /// 截止时间（可选）
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// 是否完成
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime()();

  /// 完成时间（可选）
  DateTimeColumn get completedAt => dateTime().nullable()();
}

/// 笔记表（第一版纯文本）
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 标题
  TextColumn get title => text().withLength(max: 200)();

  /// 正文（纯文本多行）
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 所属场景：study / work / life
  TextColumn get scene => text().withLength(max: 16)();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// 记账表
class LedgerRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 类型：income / expense
  TextColumn get type => text().withLength(max: 16)();

  /// 金额（单位：分，必须为整数且 >= 0）
  IntColumn get amountCents => integer()();

  /// 关联分类 id
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// 场景（可选）：study / work / life
  TextColumn get scene => text().withLength(max: 16).nullable()();

  /// 记账日期
  DateTimeColumn get recordDate => dateTime()();

  /// 备注（可选）
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

/// 分类表（固定分类 + 用户自定义）
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 类型：income / expense
  TextColumn get type => text().withLength(max: 16)();

  /// 分类名称
  TextColumn get name => text().withLength(min: 1, max: 50)();

  /// 是否用户自定义（内置分类为 false，不可删除）
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  /// 排序序号，越小越靠前
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

// ============================================================
// 学习管理（4 张）
// ============================================================

/// 读书笔记
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get author => text().nullable()();

  /// 当前页数
  IntColumn get currentPage => integer().withDefault(const Constant(0))();

  /// 总页数
  IntColumn get totalPages => integer().withDefault(const Constant(0))();

  /// 状态：reading / finished / paused
  TextColumn get status => text().withLength(max: 16)();

  /// 评分 1-5（读完才评分，可空）
  IntColumn get rating => integer().nullable()();

  /// 读书笔记内容
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

/// 课程
class Courses extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// 学习平台（如 B站 / 慕课）
  TextColumn get platform => text().nullable()();

  /// 总章节数
  IntColumn get totalChapters => integer().withDefault(const Constant(0))();

  /// 已完成章节数
  IntColumn get completedChapters => integer().withDefault(const Constant(0))();

  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// 状态：ongoing / completed / paused
  TextColumn get status => text().withLength(max: 16)();
}

/// 学习打卡
class StudyCheckins extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 打卡日期
  DateTimeColumn get date => dateTime()();

  /// 学习内容
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 学习时长（分钟）
  IntColumn get minutes => integer().withDefault(const Constant(0))();

  /// 是否完成当日目标
  BoolColumn get goalMet => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
}

/// 学习目标
class StudyGoals extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// 目标类型：reading / course / review / other
  TextColumn get type => text().withLength(max: 16)();

  DateTimeColumn get dueDate => dateTime().nullable()();

  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
}

// ============================================================
// 工作管理（3 张）
// ============================================================

/// 项目
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// 状态：ongoing / completed / paused
  TextColumn get status => text().withLength(max: 16)();

  /// 进度 0-100
  IntColumn get progress => integer().withDefault(const Constant(0))();

  /// 优先级：0 低 / 1 中 / 2 高
  IntColumn get priority => integer().withDefault(const Constant(1))();

  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// 项目笔记
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

/// 工时记录
class WorkLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联项目
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();

  /// 工作日期
  DateTimeColumn get date => dateTime()();

  /// 时长（分钟）
  IntColumn get minutes => integer()();

  /// 工作内容摘要
  TextColumn get summary => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime()();
}

/// 工作日志（每天一条）
class WorkJournals extends Table {
  IntColumn get id => integer().autoIncrement()();

  DateTimeColumn get date => dateTime()();

  /// 关联项目（可空）
  IntColumn get projectId => integer()
      .nullable()
      .references(Projects, #id, onDelete: KeyAction.setNull)();

  /// 工作内容
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 成果
  TextColumn get achievement => text().nullable()();

  /// 遇到的问题
  TextColumn get problem => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

// ============================================================
// 生活管理（4 张）
// ============================================================

/// 习惯
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// 频率：daily / weekly
  TextColumn get frequency => text().withLength(max: 16)();

  DateTimeColumn get createdAt => dateTime()();
}

/// 习惯打卡记录
class HabitCheckins extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联习惯
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// 打卡日期
  DateTimeColumn get date => dateTime()();

  /// 备注（可选）
  TextColumn get note => text().nullable()();
}

/// 健康记录
class HealthRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  DateTimeColumn get date => dateTime()();

  /// 睡眠时长（小时，可空，支持小数如 7.5）
  RealColumn get sleepHours => real().nullable()();

  /// 运动时长（分钟，可空）
  IntColumn get exerciseMinutes => integer().nullable()();

  /// 体重（公斤，可空，支持小数如 65.5）
  RealColumn get weightKg => real().nullable()();
}

/// 生活备忘
class LifeMemos extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 200)();

  TextColumn get content => text().withDefault(const Constant(''))();

  /// 提醒时间（第一版仅展示，不做系统通知）
  DateTimeColumn get remindAt => dateTime().nullable()();

  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
}
