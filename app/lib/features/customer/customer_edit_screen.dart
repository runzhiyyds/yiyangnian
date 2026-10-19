import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../core/lunar_helper.dart';
import '../../widgets/lunar_date_picker.dart';
import 'customer_model.dart';
import 'customer_repository.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';

class CustomerEditScreen extends StatefulWidget {
  const CustomerEditScreen({
    super.key,
    this.customerName,
    this.templateName,
    this.initialName,
  });

  final String? customerName;
  final String? templateName;
  final String? initialName;

  @override
  State<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends State<CustomerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _basicExpanded = true;
  bool _birthdayExpanded = true;
  bool _otherExpanded = true;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _symptomsController;
  late TextEditingController _zodiacController;
  late TextEditingController _ageController;
  late TextEditingController _lifeNumberController;

  DateTime? _solarBirthday;
  String? _lunarBirthdayText;
  bool _loading = false;
  String? _error;
  List<StorageRecordModel> _templateStorages = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _symptomsController = TextEditingController();
    _zodiacController = TextEditingController();
    _ageController = TextEditingController();
    _lifeNumberController = TextEditingController();
    if (widget.customerName != null) {
      _loadCustomer();
    } else if (widget.templateName != null) {
      _loadTemplate();
    }
  }

  static String _cacheKeyCustomer(String name) => 'customer_$name';
  static String _cacheKeyTemplateStorages(String name) => 'storages_template_$name';

  Future<void> _loadCustomer() async {
    final name = widget.customerName!;
    final cache = context.read<DataCache>();
    final revision = cache.revision;
    var c = cache.get<CustomerModel>(_cacheKeyCustomer(name));
    if (c == null) {
      final repo = context.read<CustomerRepository>();
      c = await repo.getByName(name);
      if (!mounted || cache.revision != revision) return;
      if (c != null) cache.set(_cacheKeyCustomer(name), c);
    }
    if (c != null && mounted) {
      _nameController.text = c.name;
      _phoneController.text = c.phone ?? '';
      _addressController.text = c.address ?? '';
      _symptomsController.text = c.symptoms ?? '';
      _solarBirthday = c.solarBirthday;
      _lunarBirthdayText = c.lunarBirthday;
      _zodiacController.text = c.zodiac ?? '';
      _ageController.text = c.age?.toString() ?? '';
      _lifeNumberController.text = c.lifeNumber?.toString() ?? '';
      setState(() {});
    }
  }

  Future<void> _loadTemplate() async {
    final name = widget.templateName!;
    final cache = context.read<DataCache>();
    final revision = cache.revision;
    var storages = cache.get<List<StorageRecordModel>>(_cacheKeyTemplateStorages(name));
    if (storages == null) {
      final storageRepo = context.read<StorageRepository>();
      storages = await storageRepo.getByCustomer(name);
      if (!mounted || cache.revision != revision) return;
      cache.set(_cacheKeyTemplateStorages(name), storages);
    }
    if (mounted) {
      setState(() {
        _templateStorages = storages ?? [];
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _symptomsController.dispose();
    _zodiacController.dispose();
    _ageController.dispose();
    _lifeNumberController.dispose();
    super.dispose();
  }

  void _onSolarDatePicked(DateTime d) {
    setState(() {
      _solarBirthday = d;
      final lunar = LunarHelper.solarToLunar(d);
      if (lunar != null) {
        _lunarBirthdayText =
            '${lunar.year}年${lunar.month}月${lunar.day}日';
      }
      _zodiacController.text = LunarHelper.getZodiacFromSolar(d);
      _ageController.text = LunarHelper.getAgeInYears(d).toString();
      _lifeNumberController.text = LunarHelper.getLifeNumber(d).toString();
    });
  }

  Widget _buildCalculatedField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: hint,
        helperStyle: TextStyle(color: Colors.orange[800], fontSize: 12),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.orange.shade200),
        ),
      ),
      keyboardType: keyboardType,
    );
  }

  void _onLunarDatePicked(int year, int month, int day, bool isLeap) {
    setState(() {
      _lunarBirthdayText = isLeap
          ? '${year}年闰${month}月${day}日'
          : '${year}年${month}月${day}日';
      final solar = isLeap
          ? LunarHelper.lunarToSolarWithLeap(year, month, day, isLeapMonth: true)
          : LunarHelper.lunarToSolar(year, month, day);
      if (solar != null) {
        _solarBirthday = solar;
        _zodiacController.text = LunarHelper.getZodiacFromSolar(solar);
        _ageController.text = LunarHelper.getAgeInYears(solar).toString();
        _lifeNumberController.text = LunarHelper.getLifeNumber(solar).toString();
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('客户姓名不能为空')),
      );
      return;
    }

    final customerRepo = context.read<CustomerRepository>();
    final exists = await customerRepo.existsByName(name,
        excludeName: widget.customerName);
    if (exists) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('客户姓名已存在'),
            content: const Text(
              '客户姓名已存在，可加后缀区分，如：张三_1、张三_新店',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? zodiac;
      int? age;
      int? lifeNumber;
      if (_solarBirthday != null) {
        zodiac = _zodiacController.text.trim().isEmpty
            ? LunarHelper.getZodiacFromSolar(_solarBirthday!)
            : _zodiacController.text.trim();
        age = int.tryParse(_ageController.text.trim()) ??
            LunarHelper.getAgeInYears(_solarBirthday!);
        lifeNumber = int.tryParse(_lifeNumberController.text.trim()) ??
            LunarHelper.getLifeNumber(_solarBirthday!);
      }

      final customer = CustomerModel(
        name: name,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        lunarBirthday: _lunarBirthdayText,
        solarBirthday: _solarBirthday,
        zodiac: zodiac,
        age: age,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        lifeNumber: lifeNumber,
        symptoms: _symptomsController.text.trim().isEmpty
            ? null
            : _symptomsController.text.trim(),
      );

      if (widget.customerName != null) {
        await customerRepo.update(widget.customerName!, customer);
      } else {
        await customerRepo.create(customer);
        for (final s in _templateStorages) {
          await context.read<StorageRepository>().create(StorageRecordModel(
                id: 0,
                code: '',
                customerName: name,
                storageBigItems: s.storageBigItems,
                storageSmallItemIds: s.storageSmallItemIds,
                amount: s.amount,
                totalCount: s.totalCount,
                storageDate: s.storageDate,
                remark: s.remark,
              ));
        }
      }

      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateCustomerAndTree();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
        final nameChanged = widget.customerName != null && name != widget.customerName!;
        if (nameChanged) {
          context.go('/home/tree');
        } else {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customerName != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑客户' : '新建客户'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _basicExpanded,
                onExpansionChanged: (v) => setState(() => _basicExpanded = v),
                title: const Text('基本信息', style: TextStyle(fontWeight: FontWeight.w600)),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '客户姓名 *',
                      hintText: '请输入客户姓名',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入客户姓名' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      hintText: '请输入手机号',
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _birthdayExpanded,
                onExpansionChanged: (v) => setState(() => _birthdayExpanded = v),
                title: const Text('生日相关', style: TextStyle(fontWeight: FontWeight.w600)),
                children: [
                  ListTile(
                    title: const Text('公历生日'),
              subtitle: Text(
                _solarBirthday != null
                    ? '${_solarBirthday!.year}年${_solarBirthday!.month}月${_solarBirthday!.day}日'
                    : '请选择',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _solarBirthday ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  locale: const Locale('zh', 'CN'),
                );
                if (d != null) _onSolarDatePicked(d);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              key: ValueKey('lunar_$_lunarBirthdayText'),
              isThreeLine: (_lunarBirthdayText ?? '').isNotEmpty,
              title: const Text('农历生日'),
              subtitle: Text(
                _lunarBirthdayText ?? '请选择',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                int? y, m, d;
                bool isLeap = false;
                if (_lunarBirthdayText != null) {
                  final parts = _lunarBirthdayText!.split(RegExp(r'[年月日\s]+'));
                  if (parts.length >= 3) {
                    y = int.tryParse(parts[0]);
                    final mStr = parts[1].replaceFirst('闰', '');
                    isLeap = parts[1].startsWith('闰');
                    const cnMonths = ['正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月'];
                    m = int.tryParse(mStr);
                    if (m == null) {
                      final mi = cnMonths.indexWhere((x) => mStr == x || mStr.startsWith(x.substring(0, 1)));
                      if (mi >= 0) m = mi + 1;
                    }
                    d = int.tryParse(parts[2]);
                  }
                }
                final result = await LunarDatePicker.show(
                  context,
                  initialYear: y,
                  initialMonth: m,
                  initialDay: d,
                  initialIsLeap: isLeap,
                );
                if (result != null) {
                  _onLunarDatePicked(result.year, result.month, result.day, result.isLeap);
                }
              },
            ),
            const SizedBox(height: 16),
            _buildCalculatedField(
              label: '属相',
              controller: _zodiacController,
              hint: '由公历生日计算，谨慎修改',
            ),
            const SizedBox(height: 16),
            _buildCalculatedField(
              label: '年龄',
              controller: _ageController,
              hint: '由公历生日计算，谨慎修改',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildCalculatedField(
              label: '生命密码',
              controller: _lifeNumberController,
              hint: '由公历生日计算，谨慎修改',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _otherExpanded,
                onExpansionChanged: (v) => setState(() => _otherExpanded = v),
                title: const Text('其他信息', style: TextStyle(fontWeight: FontWeight.w600)),
                children: [
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: '住址',
                      hintText: '请输入住址',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _symptomsController,
                    decoration: const InputDecoration(
                      labelText: '症状',
                      hintText: '请输入症状',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
