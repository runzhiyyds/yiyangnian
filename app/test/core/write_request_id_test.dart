import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/write_request_id.dart';

void main() {
  test('write request ids are stable-format and collision resistant', () {
    final ids = List.generate(200, (_) => newWriteRequestId());
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    }
  });

  test('child request ids are deterministic per parent and index', () {
    const parent = '0123456789abcdef0123456789abcdef';
    expect(childWriteRequestId(parent, 0), '$parent:0');
    expect(childWriteRequestId(parent, 1), '$parent:1');
    expect(childWriteRequestId(parent, 0), childWriteRequestId(parent, 0));
  });
}
