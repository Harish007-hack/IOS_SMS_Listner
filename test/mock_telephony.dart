import 'package:another_telephony/telephony.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

class MockTelephony extends Mock implements Telephony {
  Function(SmsMessage)? _onNewMessage;
  Function(SmsMessage)? _onBackgroundMessage;
  bool _listenInBackground = false;

  @override
  Future<bool?> get requestPhoneAndSmsPermissions async => true;

  @override
  void listenIncomingSms({
    required Function(SmsMessage) onNewMessage,
    Function(SmsMessage)? onBackgroundMessage,
    bool listenInBackground = false,
  }) {
    _onNewMessage = onNewMessage;
    _onBackgroundMessage = onBackgroundMessage;
    _listenInBackground = listenInBackground;
  }

  void simulateIncomingSms(String body, String address) {
    final smsMessage = SmsMessage.fromMap({
      'body': body,
      'address': address,
      'date': DateTime.now().millisecondsSinceEpoch,
      'dateSent': DateTime.now().millisecondsSinceEpoch,
      'subject': 'Test SMS',
      'serviceCenterAddress': '+123456789',
      'isRead': false,
      'status': -1,
      'type': -1,
      'subscriptionId': 1,
    }, []); // Provide a suitable value for the second argument if needed
    
    if (_onNewMessage != null) {
      _onNewMessage!(smsMessage);
    }
  }

  bool get isListeningInBackground => _listenInBackground;
}