import 'package:flutter_test/flutter_test.dart';
import 'package:convert2file/services/math_formula_service.dart';

void main() {
  group('MathFormulaService', () {
    test('keeps a simple ANOVA-style subscript equation as OMML', () {
      final result = MathFormulaService.parse(r'F_out = C(F_in, T)');

      expect(result, isNotNull);
      expect(result!.displayText, contains('Fₒᵤₜ'));
      expect(result.displayText, contains('Fᵢₙ'));
      expect(result.omml, contains('<m:sSub>'));
    });

    test('creates a native Word fraction and power', () {
      final result = MathFormulaService.parse(r'\frac{a}{b} + x^2');

      expect(result, isNotNull);
      expect(result!.omml, contains('<m:f>'));
      expect(result.omml, contains('<m:sSup>'));
      expect(result.displayText, contains('a⁄b'));
    });

    test('creates a square root and Greek symbols', () {
      final result = MathFormulaService.parse(r'\sqrt{\sigma^2 + \mu}');

      expect(result, isNotNull);
      expect(result!.omml, contains('<m:rad>'));
      expect(result.displayText, contains('σ'));
      expect(result.displayText, contains('μ'));
    });

    test('creates summation and integral operators with limits', () {
      final result = MathFormulaService.parse(
        r'\sum_{i=1}^{n} x_i + \int_a^b f(x)',
      );

      expect(result, isNotNull);
      expect(result!.omml, contains('<m:nary>'));
      expect(result.displayText, contains('∑'));
      expect(result.displayText, contains('∫'));
    });

    test('creates a piecewise equation matrix', () {
      final result = MathFormulaService.parse(
        r'F_out = \begin{cases} C(F_in,T) & V(C(F_in,T)) = 1 \\ Error & V(C(F_in,T)) = 0 \end{cases}',
      );

      expect(result, isNotNull);
      expect(result!.omml, contains('<m:m>'));
      expect(result.displayText, contains('Error'));
    });

    test('does not treat ordinary prose as a formula', () {
      expect(MathFormulaService.parse('This is an ANOVA discussion.'), isNull);
    });
  });
}
