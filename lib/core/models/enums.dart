/// 场景枚举：每条待办 / 笔记 / 账单只属于学习、工作、生活之一
enum Scene {
  study('学习', 'study'),
  work('工作', 'work'),
  life('生活', 'life');

  const Scene(this.label, this.code);

  /// 中文显示名
  final String label;

  /// 存库用的稳定字符串
  final String code;

  static Scene fromCode(String? code) {
    return Scene.values.firstWhere(
      (e) => e.code == code,
      orElse: () => Scene.life,
    );
  }
}

/// 待办优先级：0 低 / 1 中 / 2 高
enum TodoPriority {
  low(0, '低'),
  medium(1, '中'),
  high(2, '高');

  const TodoPriority(this.value, this.label);

  final int value;
  final String label;

  static TodoPriority fromValue(int? value) {
    return TodoPriority.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TodoPriority.medium,
    );
  }
}

/// 收支类型
enum LedgerType {
  income('收入', 'income'),
  expense('支出', 'expense');

  const LedgerType(this.label, this.code);

  final String label;
  final String code;

  static LedgerType fromCode(String code) {
    return LedgerType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => LedgerType.expense,
    );
  }
}

/// 书籍阅读状态
enum BookStatus {
  reading('在读', 'reading'),
  finished('读完', 'finished'),
  paused('搁置', 'paused');

  const BookStatus(this.label, this.code);

  final String label;
  final String code;

  static BookStatus fromCode(String? code) {
    return BookStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => BookStatus.reading,
    );
  }
}

/// 课程 / 项目通用状态
enum ProgressStatus {
  ongoing('进行中', 'ongoing'),
  completed('已完成', 'completed'),
  paused('搁置', 'paused');

  const ProgressStatus(this.label, this.code);

  final String label;
  final String code;

  static ProgressStatus fromCode(String? code) {
    return ProgressStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => ProgressStatus.ongoing,
    );
  }
}

/// 学习目标类型
enum StudyGoalType {
  reading('读书', 'reading'),
  course('课程', 'course'),
  review('复习', 'review'),
  other('其他', 'other');

  const StudyGoalType(this.label, this.code);

  final String label;
  final String code;

  static StudyGoalType fromCode(String? code) {
    return StudyGoalType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StudyGoalType.other,
    );
  }
}

/// 习惯频率
enum HabitFrequency {
  daily('每天', 'daily'),
  weekly('每周', 'weekly');

  const HabitFrequency(this.label, this.code);

  final String label;
  final String code;

  static HabitFrequency fromCode(String? code) {
    return HabitFrequency.values.firstWhere(
      (e) => e.code == code,
      orElse: () => HabitFrequency.daily,
    );
  }
}
