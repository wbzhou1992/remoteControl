import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control_client/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RemoteControlApp());
    expect(find.text('远程桌面控制'), findsOneWidget);
  });
}
