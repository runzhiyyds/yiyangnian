import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/formula_helper.dart';

void main() {
  group('tryParseFormula', () {
    test('simple number', () {
      expect(tryParseFormula('100'), 100);
    });

    test('with equals sign', () {
      expect(tryParseFormula('100+200='), 300);
    });

    test('multiplication', () {
      expect(tryParseFormula('10*20='), 200);
    });

    test('empty returns null', () {
      expect(tryParseFormula(''), isNull);
      expect(tryParseFormula('   '), isNull);
    });

    test('invalid returns null', () {
      expect(tryParseFormula('abc'), isNull);
    });
  });
}
