import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';

/// 农历日期选择器（中文界面）
class LunarDatePicker {
  static const List<String> _monthNames = [
    '正月', '二月', '三月', '四月', '五月', '六月',
    '七月', '八月', '九月', '十月', '冬月', '腊月',
  ];

  /// 显示农历日期选择器
  static Future<({int year, int month, int day, bool isLeap})?> show(
    BuildContext context, {
    int? initialYear,
    int? initialMonth,
    int? initialDay,
    bool initialIsLeap = false,
  }) async {
    int year = initialYear ?? DateTime.now().year;
    int month = initialMonth ?? 1;
    int day = initialDay ?? 1;
    bool isLeap = initialIsLeap;

    return showDialog<({int year, int month, int day, bool isLeap})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final lunarYear = LunarYear.fromYear(year);
            final leapMonth = lunarYear.getLeapMonth();
            final monthOptions = <String>[];
            final monthValues = <({int m, bool leap})>[];
            for (int m = 1; m <= 12; m++) {
              monthOptions.add(_monthNames[m - 1]);
              monthValues.add((m: m, leap: false));
              if (leapMonth == m) {
                monthOptions.add('闰${_monthNames[m - 1]}');
                monthValues.add((m: m, leap: true));
              }
            }
            int monthIdx = 0;
            for (int i = 0; i < monthValues.length; i++) {
              if (monthValues[i].m == month && monthValues[i].leap == isLeap) {
                monthIdx = i;
                break;
              }
            }
            if (monthIdx >= monthValues.length) {
              monthIdx = 0;
              month = monthValues[0].m;
              isLeap = monthValues[0].leap;
            }

            int dayCount = 29;
            try {
              final mm = monthValues[monthIdx].leap ? -monthValues[monthIdx].m : monthValues[monthIdx].m;
              final lm = lunarYear.getMonth(mm);
              if (lm != null) dayCount = lm.getDayCount();
            } catch (_) {}
            if (day > dayCount) day = dayCount;

            return AlertDialog(
              title: const Text('选择农历生日'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: year,
                            decoration: const InputDecoration(labelText: '年'),
                            items: List.generate(201, (i) {
                              final y = 1900 + i;
                              return DropdownMenuItem(
                                value: y,
                                child: Text('$y年', maxLines: 1, overflow: TextOverflow.ellipsis),
                              );
                            }),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  year = v;
                                  final ly = LunarYear.fromYear(year);
                                  final lm = ly.getLeapMonth();
                                  if (lm == 0 || month != lm) isLeap = false;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: monthIdx,
                            decoration: const InputDecoration(labelText: '月'),
                            items: List.generate(monthOptions.length, (i) {
                              return DropdownMenuItem(
                                value: i,
                                child: Text(
                                  monthOptions[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  monthIdx = v;
                                  month = monthValues[v].m;
                                  isLeap = monthValues[v].leap;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: day,
                            decoration: const InputDecoration(labelText: '日'),
                            items: List.generate(dayCount, (i) {
                              final d = i + 1;
                              return DropdownMenuItem(
                                value: d,
                                child: Text('$d日', maxLines: 1, overflow: TextOverflow.ellipsis),
                              );
                            }),
                            onChanged: (v) {
                              if (v != null) setState(() => day = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final m = monthValues[monthIdx];
                    Navigator.pop(ctx, (year: year, month: m.m, day: day, isLeap: m.leap));
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
