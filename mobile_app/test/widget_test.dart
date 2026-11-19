import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tomruk_olcum_ai/main.dart';

void main() {
  testWidgets('AcilisEkrani ve LisansServisi testi', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    expect(LisansServisi.yoneticiSifresiDogrula('Cihan2026!'), isTrue);
    expect(LisansServisi.yoneticiSifresiDogrula('yanlis'), isFalse);

    final anahtar = LisansServisi.lisansAnahtariUret('TALEP-TEST');
    expect(anahtar.startsWith('OGM-'), isTrue);

    await tester.pumpWidget(const TomrukOlcumApp());
    expect(find.text('Geliştirici CİHAN TÜRKMEN'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
