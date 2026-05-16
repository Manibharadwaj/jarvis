import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_app/main.dart';

void main() {
  testWidgets('App shows call button', (tester) async {
    await tester.pumpWidget(const JarvisApp());
    expect(find.text('JARVIS'), findsOneWidget);
  });
}
