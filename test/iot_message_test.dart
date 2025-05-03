import 'package:flutter_test/flutter_test.dart';
import 'package:iot_sms_listener/main.dart'; // Adjust import to match your project structure

void main() {
  group('IotMessage', () {
    test('should create an IotMessage with default status and retry count', () {
      final message = IotMessage(
        body: 'Test message',
        address: '+123456789',
        date: DateTime(2025, 5, 3),
      );
      
      expect(message.body, equals('Test message'));
      expect(message.address, equals('+123456789'));
      expect(message.date, equals(DateTime(2025, 5, 3)));
      expect(message.status, equals(MessageStatus.pending));
      expect(message.retryCount, equals(0));
    });
    
    test('should accept custom status and retry count', () {
      final message = IotMessage(
        body: 'Test message',
        address: '+123456789',
        date: DateTime(2025, 5, 3),
        status: MessageStatus.failed,
        retryCount: 2,
      );
      
      expect(message.status, equals(MessageStatus.failed));
      expect(message.retryCount, equals(2));
    });
  });
}