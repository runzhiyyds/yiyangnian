import 'package:math_expressions/math_expressions.dart';

/// 解析并计算数学公式，如 1000*0.8=、100+200 等
/// 支持 + - * / 及括号
double? tryParseFormula(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  // 去掉末尾的 =
  if (s.endsWith('=')) s = s.substring(0, s.length - 1).trim();
  if (s.isEmpty) return null;
  // 替换中文运算符
  s = s.replaceAll('×', '*').replaceAll('÷', '/');
  // 只允许数字、运算符、空格、括号
  if (!RegExp(r'^[\d\s+\-*/().]+$').hasMatch(s)) return null;
  try {
    final p = Parser();
    final exp = p.parse(s);
    final cm = ContextModel();
    final result = exp.evaluate(EvaluationType.REAL, cm);
    return result;
  } catch (_) {
    return null;
  }
}
