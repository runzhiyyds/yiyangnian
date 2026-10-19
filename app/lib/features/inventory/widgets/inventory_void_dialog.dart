import 'package:flutter/material.dart';

String formatInventoryAuditTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

Future<String?> showInventoryVoidDialog(
  BuildContext context, {
  required String title,
  required String impact,
}) async {
  final controller = TextEditingController();
  String? errorText;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(impact),
            const SizedBox(height: 12),
            const Text('原记录不会被删除，系统会记录撤销时间，并在库存时间线中增加一条反向变化。'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 100,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '撤销原因（必填）',
                hintText: '例如：录入数量错误、重复录入',
                errorText: errorText,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) {
                setDialogState(() => errorText = '请填写撤销原因');
                return;
              }
              Navigator.pop(dialogContext, reason);
            },
            child: const Text('确认撤销'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

Future<DateTime?> pickInventoryBusinessDate(
  BuildContext context, {
  required DateTime current,
  required bool warnAboutReordering,
}) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    locale: const Locale('zh', 'CN'),
  );
  if (picked == null || !context.mounted) return null;
  final changed =
      picked.year != current.year ||
      picked.month != current.month ||
      picked.day != current.day;
  if (!changed || !warnAboutReordering) return picked;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认修改业务日期'),
      content: const Text('修改后，这条记录在库存变化时间线中的展示顺序也会改变。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('确认修改'),
        ),
      ],
    ),
  );
  return confirmed == true ? picked : null;
}
