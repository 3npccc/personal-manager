import 'package:drift/drift.dart';

import '../models/enums.dart';

/// drift 类型转换器：在「枚举」与「数据库存储值」之间转换。
/// 存储值统一用枚举的 code 字符串，可读性好、便于导出 CSV 时人工核对。

class SceneConverter extends TypeConverter<Scene, String> {
  const SceneConverter();

  @override
  Scene fromSql(String fromDb) => Scene.fromCode(fromDb);

  @override
  String toSql(Scene value) => value.code;
}

class TodoPriorityConverter extends TypeConverter<TodoPriority, int> {
  const TodoPriorityConverter();

  @override
  TodoPriority fromSql(int fromDb) => TodoPriority.fromValue(fromDb);

  @override
  int toSql(TodoPriority value) => value.value;
}

class LedgerTypeConverter extends TypeConverter<LedgerType, String> {
  const LedgerTypeConverter();

  @override
  LedgerType fromSql(String fromDb) => LedgerType.fromCode(fromDb);

  @override
  String toSql(LedgerType value) => value.code;
}

class BookStatusConverter extends TypeConverter<BookStatus, String> {
  const BookStatusConverter();

  @override
  BookStatus fromSql(String fromDb) => BookStatus.fromCode(fromDb);

  @override
  String toSql(BookStatus value) => value.code;
}

class ProgressStatusConverter extends TypeConverter<ProgressStatus, String> {
  const ProgressStatusConverter();

  @override
  ProgressStatus fromSql(String fromDb) => ProgressStatus.fromCode(fromDb);

  @override
  String toSql(ProgressStatus value) => value.code;
}

class StudyGoalTypeConverter extends TypeConverter<StudyGoalType, String> {
  const StudyGoalTypeConverter();

  @override
  StudyGoalType fromSql(String fromDb) => StudyGoalType.fromCode(fromDb);

  @override
  String toSql(StudyGoalType value) => value.code;
}

class HabitFrequencyConverter extends TypeConverter<HabitFrequency, String> {
  const HabitFrequencyConverter();

  @override
  HabitFrequency fromSql(String fromDb) => HabitFrequency.fromCode(fromDb);

  @override
  String toSql(HabitFrequency value) => value.code;
}
