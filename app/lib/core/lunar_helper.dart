import 'package:lunar/lunar.dart';

/// 农历/公历转换、生肖、年龄、生命密码计算
class LunarHelper {
  /// 储值大项固定选项
  static const List<String> storageBigItems = ['藏红方', '御至宝', '元气植'];

  /// 公历日期 -> 农历日期 (DateTime)
  static DateTime? solarToLunar(DateTime solar) {
    try {
      final lunar = Solar.fromDate(solar).getLunar();
      return DateTime(lunar.getYear(), lunar.getMonth(), lunar.getDay());
    } catch (_) {
      return null;
    }
  }

  /// 农历日期 -> 公历日期 (DateTime)
  static DateTime? lunarToSolar(int lunarYear, int lunarMonth, int lunarDay) {
    try {
      final lunar = Lunar.fromYmd(lunarYear, lunarMonth, lunarDay);
      final solar = lunar.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } catch (_) {
      return null;
    }
  }

  /// 农历闰月：月份用负数表示，如 -4 表示闰四月
  static DateTime? lunarToSolarWithLeap(
      int lunarYear, int lunarMonth, int lunarDay, {bool isLeapMonth = false}) {
    try {
      final m = isLeapMonth ? -lunarMonth : lunarMonth;
      final lunar = Lunar.fromYmd(lunarYear, m, lunarDay);
      final solar = lunar.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } catch (_) {
      return null;
    }
  }

  /// 根据公历日期获取生肖
  static String getZodiacFromSolar(DateTime solar) {
    try {
      return Solar.fromDate(solar).getLunar().getYearShengXiao();
    } catch (_) {
      return '';
    }
  }

  /// 根据农历年月日获取生肖
  static String getZodiacFromLunar(int lunarYear, int lunarMonth, int lunarDay) {
    try {
      final lunar = Lunar.fromYmd(lunarYear, lunarMonth, lunarDay);
      return lunar.getYearShengXiao();
    } catch (_) {
      return '';
    }
  }

  /// 周岁：根据公历生日计算（今年生日已过则 +1 岁）
  static int getAgeInYears(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  /// 生命密码：公历生日各位数字反复求和直到 1 位数
  /// 公式：YYYYMMDD 拼接后逐位相加，重复直到 < 10
  static int getLifeNumber(DateTime solarBirth) {
    String s = '${solarBirth.year}'
        '${solarBirth.month.toString().padLeft(2, '0')}'
        '${solarBirth.day.toString().padLeft(2, '0')}';
    int n = _digitSum(s);
    while (n >= 10) {
      n = _digitSum(n.toString());
    }
    return n;
  }

  static int _digitSum(String s) {
    int sum = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) {
        sum += int.parse(c);
      }
    }
    return sum;
  }

  /// 农历日期格式化显示
  static String formatLunarDate(DateTime lunar) {
    return '${lunar.year}年${lunar.month}月${lunar.day}日';
  }

  /// 公历日期格式化
  static String formatSolarDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
