/// 分析看板用：本周 / 本月 / 本季度 / 本年的起止日期（仅日期部分，不含时分秒）
class DateRangeHelper {
  /// 本周：周一 00:00 ～ 周日 23:59 的日期范围
  static (DateTime start, DateTime end) thisWeek() {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return (weekStart, weekEnd);
  }

  /// 本月：本月 1 日 ～ 本月最后一天
  static (DateTime start, DateTime end) thisMonth() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    return (monthStart, monthEnd);
  }

  /// 本季度：Q1 1/1–3/31, Q2 4/1–6/30, Q3 7/1–9/30, Q4 10/1–12/31
  static (DateTime start, DateTime end) thisQuarter() {
    final now = DateTime.now();
    final month = now.month;
    final startMonth = ((month - 1) ~/ 3) * 3 + 1;
    final monthStart = DateTime(now.year, startMonth, 1);
    final monthEnd = DateTime(now.year, startMonth + 3, 0);
    return (monthStart, monthEnd);
  }

  /// 本年：1/1 ～ 12/31
  static (DateTime start, DateTime end) thisYear() {
    final now = DateTime.now();
    return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
  }
}
