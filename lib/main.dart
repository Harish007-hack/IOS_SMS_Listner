import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';

// Message status enum
enum MessageStatus {
  success,
  pending,
  failed,
}

// Message model to store SMS data and status
class IotMessage {
  final String body;
  final String address;
  final DateTime date;
  MessageStatus status;
  int retryCount;

  IotMessage({
    required this.body,
    required this.address,
    required this.date,
    this.status = MessageStatus.pending,
    this.retryCount = 0,
  });
}

// Background handler for SMS messages
@pragma('vm:entry-point')
void onBackgroundMessage(SmsMessage message) async {
  // Send a message to the main isolate to handle the SMS
  final SendPort? sendPort = IsolateNameServer.lookupPortByName('sms_isolate');
  if (sendPort != null) {
    sendPort.send({
      'body': message.body,
      'address': message.address,
      'date': message.date,
    });
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IOT Messages',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const IotSmsListenerPage(),
    );
  }
}

class IotSmsListenerPage extends StatefulWidget {
  const IotSmsListenerPage({super.key});

  @override
  State<IotSmsListenerPage> createState() => _IotSmsListenerPageState();
}

class _IotSmsListenerPageState extends State<IotSmsListenerPage> {
  final List<IotMessage> _messages = [];
  final telephony = Telephony.instance;
  final ReceivePort _receivePort = ReceivePort();
  bool _isInitialized = false;
  
  // Add the centralized SIM number as a class variable
  String _centralizedSimNumber = "+919952834280"; // Default value

  @override
  void initState() {
    super.initState();
    _loadSettings(); // Load settings including the centralized number
    _initializeSmsListener();
  }
  
  // Method to load settings (in a real app, this would load from SharedPreferences or similar)
  Future<void> _loadSettings() async {
    // In a real app, you would load from persistent storage
    // For example: _centralizedSimNumber = await _loadCentralizedNumberFromStorage();
    
    // For now, we'll just use the default value
    setState(() {
      // Using a default value, but this is where you'd set it from settings
      _centralizedSimNumber = "+919952834280"; 
    });
  }
  
  // Add a method to update the centralized number
  void _updateCentralizedNumber(String newNumber) {
    setState(() {
      _centralizedSimNumber = newNumber;
    });
    // In a real app, you'd also save this to persistent storage
    // _saveCentralizedNumberToStorage(newNumber);
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('sms_isolate');
    _receivePort.close();
    super.dispose();
  }

  void _onSmsReceived(SmsMessage message) {
    final newMessage = IotMessage(
      body: message.body ?? "No content",
      address: message.address ?? "Unknown",
      date: DateTime.fromMillisecondsSinceEpoch(message.date ?? DateTime.now().millisecondsSinceEpoch),
    );
    
    setState(() {
      _messages.insert(0, newMessage);
    });
    
    _sendToListenerGateway(newMessage);
  }

  Future<void> _initializeSmsListener() async {
    if (_isInitialized) return;

    // Register the receive port for background messages
    IsolateNameServer.registerPortWithName(_receivePort.sendPort, 'sms_isolate');
    _receivePort.listen((dynamic message) {
      if (message is Map) {
        final smsMessage = IotMessage(
          body: message['body'] ?? "No content",
          address: message['address'] ?? "Unknown",
          date: DateTime.fromMillisecondsSinceEpoch(message['date'] ?? DateTime.now().millisecondsSinceEpoch),
        );
        
        setState(() {
          _messages.insert(0, smsMessage);
        });
        
        _sendToListenerGateway(smsMessage);
      }
    });

    // Request permissions
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

  Future<bool> _mockApiCall() async {
    // Simulate API call with 80% success rate
    await Future.delayed(const Duration(seconds: 2));
    return DateTime.now().millisecond % 10 < 8; // 80% chance of success
  }

  Future<void> _sendToListenerGateway(IotMessage message) async {
    // Update status to pending
    setState(() {
      message.status = MessageStatus.pending;
    });

    bool success = false;
    
    // Try to send the message with retry logic
    while (message.retryCount < 2 && !success) {
      try {
        // Mock API call to send message to listener gateway
        success = await _mockApiCall();
        
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
  }

  Future<void> _retryMessage(IotMessage message) async {
    setState(() {
      message.status = MessageStatus.pending;
      message.retryCount = 0;
    });
    await _sendToListenerGateway(message);
  }
  
  // Add a dialog to configure the centralized number
  void _showSettingsDialog() {
    final TextEditingController controller = TextEditingController(
      text: _centralizedSimNumber
    );
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Centralized SIM Number',
                  hintText: 'Enter phone number with country code',
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _updateCentralizedNumber(controller.text);
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IOT Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Add a settings button to the AppBar
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _showSettingsDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Display the current centralized number
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(Icons.sim_card, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Centralized SIM',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _centralizedSimNumber,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Messages list
          Expanded(
            child: _messages.isEmpty
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
          ),
        ],
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