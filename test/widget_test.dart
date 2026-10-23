import 'package:flutter_test/flutter_test.dart';
import 'package:live_money/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('converter shows rate lookup and opens quick calculator', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());

    expect(find.text('Currency Converter'), findsOneWidget);
    expect(find.text('CONVERT'), findsOneWidget);
    await tester.tap(find.byTooltip('Quick calculator').first);
    await tester.pump();

    expect(find.text('Quick calculator'), findsNWidgets(2));
    expect(find.text('Convert UGX to KES'), findsOneWidget);
  });
}
