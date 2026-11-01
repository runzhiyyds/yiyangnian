class ConsumptionRecordModel {
  final int id;
  final String code;
  final DateTime consumptionDate;
  final int storageRecordId;

  /// 兼容字段：单个消费项目 ID（旧版本仅支持单选时使用）
  final int? consumptionProjectId;

  /// 多个消费项目 ID，新版本以此为主；若为空则回退到 [consumptionProjectId]
  final List<int> consumptionProjectIds;
  final String? signatureUrl;
  final String? remark;
  final DateTime? createdAt;
  final String? clientRequestId;

  ConsumptionRecordModel({
    required this.id,
    required this.code,
    required this.consumptionDate,
    required this.storageRecordId,
    this.consumptionProjectId,
    this.consumptionProjectIds = const [],
    this.signatureUrl,
    this.remark,
    this.createdAt,
    this.clientRequestId,
  });

  factory ConsumptionRecordModel.fromJson(Map<String, dynamic> json) {
    DateTime consumptionDate = DateTime.now();
    if (json['consumption_date'] != null) {
      consumptionDate = DateTime.parse(json['consumption_date'] as String);
    }
    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.parse(json['created_at'] as String);
    }
    // 多项目数组字段
    List<int> projectIds = [];
    if (json['consumption_project_ids'] != null) {
      final list = json['consumption_project_ids'] as List<dynamic>?;
      if (list != null) {
        projectIds = list
            .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList();
      }
    }
    final singleProjectId = json['consumption_project_id'] as int?;
    if (projectIds.isEmpty && singleProjectId != null && singleProjectId > 0) {
      projectIds = [singleProjectId];
    }
    return ConsumptionRecordModel(
      id: json['id'] as int,
      code: json['code'] as String,
      consumptionDate: consumptionDate,
      storageRecordId: json['storage_record_id'] as int,
      consumptionProjectId: singleProjectId,
      consumptionProjectIds: projectIds,
      signatureUrl: json['signature_url'] as String?,
      remark: json['remark'] as String?,
      createdAt: createdAt,
      clientRequestId: json['client_request_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final projIds = consumptionProjectIds;
    final firstId = projIds.isNotEmpty ? projIds.first : consumptionProjectId;
    return {
      'code': code,
      'consumption_date': consumptionDate.toIso8601String().split('T').first,
      'storage_record_id': storageRecordId,
      // 多项目主字段
      'consumption_project_ids': projIds,
      // 兼容旧字段：取第一个项目 ID
      'consumption_project_id': firstId,
      'signature_url': signatureUrl,
      'remark': remark,
      if (clientRequestId != null) 'client_request_id': clientRequestId,
    };
  }
}
