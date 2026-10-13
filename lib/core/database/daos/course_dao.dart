import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'course_dao.g.dart';

/// 课程数据访问对象
@DriftAccessor(tables: [Courses])
class CourseDao extends DatabaseAccessor<AppDatabase> with _$CourseDaoMixin {
  CourseDao(super.db);

  Stream<List<Course>> watchAll({String? status}) {
    final query = select(courses);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<Course?> findById(int id) {
    return (select(courses)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 一次性查询（测试用，见 book_dao.dart 里 findAll 的说明）
  Future<List<Course>> findAll({String? status}) {
    final query = select(courses);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Future<int> insertCourse(CoursesCompanion entry) {
    return into(courses).insert(entry);
  }

  Future<bool> updateCourse(Course entry) {
    return update(courses).replace(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(courses)..where((t) => t.id.equals(id))).go();
  }

  /// 更新已完成章节数，并在全部完成时自动标记为已完成
  Future<void> updateProgress(int id, int completedChapters) async {
    final course = await findById(id);
    if (course == null) return;
    final done = completedChapters >= course.totalChapters &&
        course.totalChapters > 0;
    await (update(courses)..where((t) => t.id.equals(id))).write(
      CoursesCompanion(
        completedChapters: Value(completedChapters),
        status: done ? const Value('completed') : const Value.absent(),
      ),
    );
  }

  Future<int> countAll() async => courses.count().getSingle();
}
