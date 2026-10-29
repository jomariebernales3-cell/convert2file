import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:convert2file/main.dart';
import 'package:convert2file/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows local workspace on launch', (WidgetTester tester) async {
    final authService = AuthService();

    await tester.pumpWidget(SmartTemplateApp(authService: authService));
    await tester.pump();

    expect(find.text('Convert2File'), findsOneWidget);
    expect(find.text('Preparing your workspace'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
