import 'package:flutter_test/flutter_test.dart';
import 'package:tomruk_olcum_ai/main.dart';

void main() {
  testWidgets('TomrukOlcumApp acilis testi', (WidgetTester tester) async {
    await tester.pumpWidget(const TomrukOlcumApp());
    expect(find.text('TomrukOlcumAI (MVP)'), findsOneWidget);
  });
}
