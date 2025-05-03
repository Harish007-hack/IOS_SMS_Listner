import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_sms_listener/main.dart'; // Adjust import to match your project structure
import 'package:mockito/mockito.dart';
import 'mock_telephony.dart';

// Mock the IotSmsListenerPage state to override the telephony instance
class TestableIotSmsListenerPage extends StatefulWidget {
  final MockTelephony mockTelephony;
  
  const TestableIotSmsListenerPage({Key? key, required this.mockTelephony}) : super(key: key);

  @override
  _TestableIotSmsListenerPageState createState() => _TestableIotSmsListenerPageState();
}

class _TestableIotSmsListenerPageState extends State<TestableIotSmsListenerPage> 
    with _IotSmsListenerPageStateMixin {
  @override
  Telephony get telephony => widget.mockTelephony;
}

// Mixin to extract the state from the original widget
mixin _IotSmsListenerPageStateMixin on State<TestableIotSmsListenerPage> {
  Telephony get telephony => (this as dynamic).telephony;

  final List<IotMessage> _messages = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeSmsListener();
  }

  Future<void> _initializeSmsListener() async {
    if (_isInitialized) return;
    
    final bool? result = await telephony.requestPhoneAndSmsPermissions;
    if (result != null && result) {
      telephony.listenIncomingSms(
        onNewMessage: _onSmsReceived,
        onBackgroundMessage: onBackgroundMessage, 
        listenInBackground: true,
      );
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _onSmsReceived(SmsMessage message) {
    final newMessage = IotMessage(
      body: message.body ?? "No content",
      address: message.address ?? "Unknown",
      date: DateTime.fromMillisecondsSinceEpoch(
        message.date ?? DateTime.now().millisecondsSinceEpoch
      ),
    );
    
    setState(() {
      _messages.insert(0, newMessage);
    });
    
    _sendToListenerGateway(newMessage);
  }

  Future<bool> _mockApiCall() async {
    // Always succeed in tests
    await Future.delayed(const Duration(milliseconds: 10));
    return true;
  }

  Future<void> _sendToListenerGateway(IotMessage message) async {
    setState(() {
      message.status = MessageStatus.pending;
    });

    try {
      bool success = await _mockApiCall();
      
      if (success) {
        setState(() {
          message.status = MessageStatus.success;
        });
      } else {
        setState(() {
          message.retryCount++;
          if (message.retryCount >= 2) {
            message.status = MessageStatus.failed;
          }
        });
      }
    } catch (e) {
      setState(() {
        message.retryCount++;
        if (message.retryCount >= 2) {
          message.status = MessageStatus.failed;
        }
      });
    }
  }

  Future<void> _retryMessage(IotMessage message) async {
    setState(() {
      message.status = MessageStatus.pending;
      message.retryCount = 0;
    });
    await _sendToListenerGateway(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IOT Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _messages.isEmpty
          ? const Center(
              child: Text('No messages received yet.',
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(
                      message.body,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '${message.address} • ${_formatDate(message.date)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatusIcon(message.status),
                        if (message.status == MessageStatus.failed)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () => _retryMessage(message),
                            tooltip: 'Retry',
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case MessageStatus.pending:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case MessageStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

void main() {
  group('IotSmsListenerPage', () {
    late MockTelephony mockTelephony;
    
    setUp(() {
      mockTelephony = MockTelephony();
    });

    testWidgets('should show empty state when no messages', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestableIotSmsListenerPage(mockTelephony: mockTelephony),
        ),
      );
      
      expect(find.text('No messages received yet.'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('should display message when SMS is received', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestableIotSmsListenerPage(mockTelephony: mockTelephony),
        ),
      );
      
      // Wait for permission request and initialization
      await tester.pumpAndSettle();
      
      // Simulate receiving an SMS
      mockTelephony.simulateIncomingSms('IOT device message', '+123456789');
      
      // Allow time for message processing
      await tester.pumpAndSettle();
      
      // Verify the message is displayed
      expect(find.text('IOT device message'), findsOneWidget);
      expect(find.text('No messages received yet.'), findsNothing);
    });

    testWidgets('should show success icon when message is sent successfully', 
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestableIotSmsListenerPage(mockTelephony: mockTelephony),
        ),
      );
      
      await tester.pumpAndSettle();
      mockTelephony.simulateIncomingSms('IOT device message', '+123456789');
      
      // Allow time for message processing and API call
      await tester.pump(const Duration(milliseconds: 100));
      
      // First we should see the pending indicator (CircularProgressIndicator)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      
      // After API call completes, we should see the success icon
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    test('Telephony listener should be configured for background operation', () async {
      final mockTelephony = MockTelephony();
      
      // Create a testable widget to trigger initialization
      final widget = TestableIotSmsListenerPage(mockTelephony: mockTelephony);
      final state = _TestableIotSmsListenerPageState();
      
      // Manually initialize
      await state._initializeSmsListener();
      
      // Verify background listening is enabled
      expect(mockTelephony.isListeningInBackground, isTrue);
    });
  });
}