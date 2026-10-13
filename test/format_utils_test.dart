import 'package:flutter_test/flutter_test.dart';
import 'package:personal_manager/core/models/enums.dart';
import 'package:personal_manager/core/utils/format_utils.dart';

/// 格式化工具测试（金额分/元转换是验收明确要求的项）
void main() {
  group('金额：分 → 元', () {
    test('基本转换', () {
      expect(FormatUtils.centsToYuan(1250), '12.50');
      expect(FormatUtils.centsToYuan(0), '0.00');
      expect(FormatUtils.centsToYuan(5), '0.05');
      expect(FormatUtils.centsToYuan(100), '1.00');
      expect(FormatUtils.centsToYuan(99999), '999.99');
    });

    test('带货币符号', () {
      expect(FormatUtils.centsToYuan(1250, withSymbol: true), '¥12.50');
      expect(
        FormatUtils.centsToYuan(1250, withSymbol: true, symbol: r'$'),
        r'$12.50',
      );
    });

    test('大额不丢精度', () {
      // 100 万元，整数分无误差
      expect(FormatUtils.centsToYuan(100000000), '1000000.00');
    });
  });

  group('金额：元 → 分', () {
    test('基本解析', () {
      expect(FormatUtils.yuanToCents('12.50'), 1250);
      expect(FormatUtils.yuanToCents('0.05'), 5);
      expect(FormatUtils.yuanToCents('100'), 10000);
      expect(FormatUtils.yuanToCents(' 12.50 '), 1250);
    });

    test('严格模式拒绝超过两位小数（用户输入场景）', () {
      // 金额最小单位是分，三位小数属于非法输入，应明确拒绝而非悄悄改数
      expect(FormatUtils.yuanToCents('12.505'), isNull);
      expect(FormatUtils.yuanToCents('0.004'), isNull);
    });

    test('宽容模式按四舍五入到分（导入外部数据场景）', () {
      expect(FormatUtils.yuanToCentsRounded('12.505'), 1251);
      expect(FormatUtils.yuanToCentsRounded('0.004'), 0);
      expect(FormatUtils.yuanToCentsRounded('12.494'), 1249);
      expect(FormatUtils.yuanToCentsRounded('12.50'), 1250);
      expect(FormatUtils.yuanToCentsRounded('12'), 1200);
      // 负数采用"远离零舍入"（half away from zero），与财务惯例一致：
      // -1.005 → -1.01，而不是截断成 -1.00
      expect(FormatUtils.yuanToCentsRounded('-1.005'), -101);
      expect(FormatUtils.yuanToCentsRounded('-1.004'), -100);
      expect(FormatUtils.yuanToCentsRounded('abc'), isNull);
    });

    test('非法输入返回 null', () {
      expect(FormatUtils.yuanToCents(''), isNull);
      expect(FormatUtils.yuanToCents('abc'), isNull);
      expect(FormatUtils.yuanToCents('12.3.4'), isNull);
      expect(FormatUtils.yuanToCents('   '), isNull);
      // 科学计数法不被接受（旧 double 实现会接受 1e3）
      expect(FormatUtils.yuanToCents('1e3'), isNull);
    });

    test('往返转换保持一致（这是金额零误差的关键）', () {
      for (final cents in [0, 1, 5, 99, 100, 1250, 99999, 100000000]) {
        final yuan = FormatUtils.centsToYuan(cents);
        expect(FormatUtils.yuanToCents(yuan), cents,
            reason: '分 $cents → 元 $yuan → 分应还原');
      }
    });
  });

  group('时长格式化', () {
    test('分钟 / 小时', () {
      expect(FormatUtils.minutes(0), '0分钟');
      expect(FormatUtils.minutes(45), '45分钟');
      expect(FormatUtils.minutes(60), '1小时');
      expect(FormatUtils.minutes(90), '1小时30分');
      expect(FormatUtils.minutes(125), '2小时5分');
    });
  });

  group('百分比与安全除法', () {
    test('百分比', () {
      expect(FormatUtils.percent(0), '0%');
      expect(FormatUtils.percent(0.5), '50%');
      expect(FormatUtils.percent(1), '100%');
      expect(FormatUtils.percent(0.756), '76%');
    });

    test('超界被裁剪', () {
      expect(FormatUtils.percent(1.5), '100%');
      expect(FormatUtils.percent(-0.5), '0%');
    });

    test('除零返回 0，不抛异常', () {
      expect(FormatUtils.safeRatio(5, 0), 0);
      expect(FormatUtils.safeRatio(0, 0), 0);
      expect(FormatUtils.safeRatio(3, 10), 0.3);
      // 超过总量时裁剪到 1
      expect(FormatUtils.safeRatio(15, 10), 1.0);
    });
  });

  group('日期格式化', () {
    test('日期与时间', () {
      expect(FormatUtils.date(DateTime(2026, 10, 10)), '2026-10-10');
      expect(FormatUtils.dateTime(DateTime(2026, 10, 10, 21, 30)),
          '2026-10-10 21:30');
      expect(FormatUtils.month(DateTime(2026, 10, 10)), '2026-10');
      expect(FormatUtils.time(DateTime(2026, 10, 10, 9, 5)), '09:05');
    });

    test('空值安全', () {
      expect(FormatUtils.date(null), '');
      expect(FormatUtils.dateTime(null), '');
    });
  });

  group('枚举转换（存库 code 与解析）', () {
    test('Scene', () {
      expect(Scene.study.code, 'study');
      expect(Scene.fromCode('work'), Scene.work);
      expect(Scene.fromCode(null), Scene.life); // 兜底
      expect(Scene.fromCode('不存在的值'), Scene.life);
    });

    test('TodoPriority', () {
      expect(TodoPriority.high.value, 2);
      expect(TodoPriority.fromValue(0), TodoPriority.low);
      expect(TodoPriority.fromValue(99), TodoPriority.medium); // 兜底
    });

    test('LedgerType', () {
      expect(LedgerType.income.code, 'income');
      expect(LedgerType.fromCode('expense'), LedgerType.expense);
      expect(LedgerType.fromCode('xxx'), LedgerType.expense); // 兜底
    });

    test('各枚举 label 为中文且非空', () {
      for (final s in Scene.values) {
        expect(s.label.isNotEmpty, isTrue);
      }
      for (final p in TodoPriority.values) {
        expect(p.label.isNotEmpty, isTrue);
      }
      for (final t in LedgerType.values) {
        expect(t.label.isNotEmpty, isTrue);
      }
      for (final b in BookStatus.values) {
        expect(b.label.isNotEmpty, isTrue);
      }
      for (final s in ProgressStatus.values) {
        expect(s.label.isNotEmpty, isTrue);
      }
      for (final g in StudyGoalType.values) {
        expect(g.label.isNotEmpty, isTrue);
      }
      for (final h in HabitFrequency.values) {
        expect(h.label.isNotEmpty, isTrue);
      }
    });
  });
}
