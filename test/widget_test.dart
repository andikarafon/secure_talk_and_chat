import 'package:flutter_test/flutter_test.dart';
import 'package:secure_talk_chat/main.dart';

void main() {
  testWidgets('Secure Talk app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const SecureTalkApp());

    expect(find.text('Secure Talk\nand Chat'), findsOneWidget);
    expect(find.text('Mulai Demo'), findsOneWidget);
  });
}
