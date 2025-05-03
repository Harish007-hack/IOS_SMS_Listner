import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iot_sms_listener/main.dart';
import 'mock_telephony.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-end test', () {
    testWidgets('App should start and show correct title', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      
      // Verify the app title is displayed
      expect(find.text('IOT Messages'), findsOneWidget);
      
      // Verify empty state message is shown
      expect(find.text('No messages received yet.'), findsOneWidget);
    });
    
    // Note: We can't properly test actual SMS functionality in integration tests
    // as it requires device capabilities and permissions that are not available
    // in the test environment. For that, manual testing on a physical device would be needed.
  });
}