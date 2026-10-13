import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/update_service.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('recognizes a newer patch version', () {
      expect(UpdateService.isNewerVersion('1.5.8', '1.5.9'), isTrue);
    });

    test('does not treat the same version as new', () {
      expect(UpdateService.isNewerVersion('1.5.8', '1.5.8'), isFalse);
    });

    test('compares numeric segments instead of text', () {
      expect(UpdateService.isNewerVersion('1.5.10', '1.5.9'), isFalse);
    });

    test('supports a remote version with fewer segments', () {
      expect(UpdateService.isNewerVersion('1.5.9', '1.6'), isTrue);
    });
  });
}
