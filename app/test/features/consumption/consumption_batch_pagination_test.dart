import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/features/consumption/consumption_repository.dart';

void main() {
  test(
    'batch consumption reads all pages rather than truncating customer detail',
    () async {
      var reads = 0;
      final rows = List.generate(
        501,
        (i) => {
          'id': i + 1,
          'code': 'XF${i + 1}',
          'storage_record_id': 1,
          'consumption_date': '2026-10-13',
        },
      );
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          reads++;
          final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
          final limit = int.parse(r.url.queryParameters['limit'] ?? '500');
          final page = rows.skip(offset).take(limit).toList();
          return http.Response(
            jsonEncode(page),
            200,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        final records = await ConsumptionRepository(
          client,
        ).getByStorageIds([1]);
        expect(records.length, 501);
        expect(reads, 2);
        expect(records.map((r) => r.id).toSet().length, 501);
      } finally {
        await client.dispose();
      }
    },
  );
}
