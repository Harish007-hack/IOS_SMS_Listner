import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Convert to map for storage
  Map<String, dynamic> toJson() {
    return {
      'body': body,
      'address': address,
      'date': date.millisecondsSinceEpoch,
      'status': status.index,
      'retryCount': retryCount,
    };
  }

  // Create from stored map
  factory IotMessage.fromJson(Map<String, dynamic> json) {
    return IotMessage(
      body: json['body'],
      address: json['address'],
      date: DateTime.fromMillisecondsSinceEpoch(json['date']),
      status: MessageStatus.values[json['status']],
      retryCount: json['retryCount'],
    );
  }
}

// Static variable to store centralized SIM number across app lifecycle
String centralizedSimNumber = "+123456789";

// Background handler for SMS messages
// This runs in a separate isolate when app is terminated
@pragma('vm:entry-point')
void onBackgroundMessage(SmsMessage message) async {
  // Process the SMS in the background
  try {
    // Load stored messages
    final prefs = await SharedPreferences.getInstance();
    final String? storedMessages = prefs.getString('iot_messages');
    List<IotMessage> messages = [];
    
    if (storedMessages != null) {
      final List<dynamic> decoded = jsonDecode(storedMessages);
      messages = decoded.map((item) => IotMessage.fromJson(item)).toList();
    }
    
    // Add new message
    final newMessage = IotMessage(
      body: message.body ?? "No content",
      address: message.address ?? "Unknown",
      date: DateTime.fromMillisecondsSinceEpoch(message.date ?? DateTime.now().millisecondsSinceEpoch),
    );
    
    messages.insert(0, newMessage);
    
    // Store back
    final jsonMessages = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString('iot_messages', jsonMessages);
    
    // Send to listener gateway (in background)
    await _sendToListenerGatewayBackground(newMessage, prefs);
  } catch (e) {
    print("Error in background processing: $e");
  }
}

// Helper function for background processing
Future<void> _sendToListenerGatewayBackground(IotMessage message, SharedPreferences prefs) async {
  // Simulate API call 
  await Future.delayed(const Duration(seconds: 1));
  final bool success = DateTime.now().millisecond % 10 < 8; // 80% chance
  
  if (success) {
    message.status = MessageStatus.success;
  } else {
    message.retryCount++;
    if (message.retryCount < 2) {
      // Try again
      await Future.delayed(const Duration(seconds: 1));
      final bool retrySuccess = DateTime.now().millisecond % 10 < 8;
      if (retrySuccess) {
        message.status = MessageStatus.success;
      } else {
        message.retryCount++;
        message.status = MessageStatus.failed;
      }
    } else {
      message.status = MessageStatus.failed;
    }
  }
  
  // Update the message in storage
  final String? storedMessages = prefs.getString('iot_messages');
  if (storedMessages != null) {
    final List<dynamic> decoded = jsonDecode(storedMessages);
    List<IotMessage> messages = decoded.map((item) => IotMessage.fromJson(item)).toList();
    
    // Find and update the message
    final index = messages.indexWhere((m) => 
        m.body == message.body && 
        m.address == message.address && 
        m.date.millisecondsSinceEpoch == message.date.millisecondsSinceEpoch);
    
    if (index >= 0) {
      messages[index].status = message.status;
      messages[index].retryCount = message.retryCount;
      
      // Store back
      final jsonMessages = jsonEncode(messages.map((m) => m.toJson()).toList());
      await prefs.setString('iot_messages', jsonMessages);
    }
  }
}

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize telephony early
  final telephony = Telephony.instance;
  await telephony.requestPhoneAndSmsPermissions;
  
  // Register callback for background messages
  telephony.listenIncomingSms(
    onNewMessage: (SmsMessage message) {}, // Will be overridden in app
    onBackgroundMessage: onBackgroundMessage,
    listenInBackground: true, // Enable background listening
  );
  
  // Load centralized SIM number from storage
  final prefs = await SharedPreferences.getInstance();
  centralizedSimNumber = prefs.getString('centralized_sim') ?? "+123456789";
  
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

class _IotSmsListenerPageState extends State<IotSmsListenerPage> with WidgetsBindingObserver {
  List<IotMessage> _messages = [];
  final telephony = Telephony.instance;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Listen for app lifecycle changes
    _initializeSmsListener();
    _loadMessages(); // Load previously stored messages
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground, refresh messages
      _loadMessages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Load messages from persistent storage
  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storedMessages = prefs.getString('iot_messages');
      
      if (storedMessages != null) {
        final List<dynamic> decoded = jsonDecode(storedMessages);
        setState(() {
          _messages = decoded.map((item) => IotMessage.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print("Error loading messages: $e");
    }
  }
  
  // Save messages to persistent storage
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMessages = jsonEncode(_messages.map((m) => m.toJson()).toList());
      await prefs.setString('iot_messages', jsonMessages);
    } catch (e) {
      print("Error saving messages: $e");
    }
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
    _saveMessages(); // Save messages when new one is received
  }

  Future<void> _initializeSmsListener() async {
    if (_isInitialized) return;

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
    await Future.delayed(const Duration(seconds: 1));
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
    
    // Save updated message status
    _saveMessages();
  }

  Future<void> _retryMessage(IotMessage message) async {
    setState(() {
      message.status = MessageStatus.pending;
      message.retryCount = 0;
    });
    await _sendToListenerGateway(message);
  }
  
  // Update centralized SIM number
  Future<void> _updateCentralizedNumber(String newNumber) async {
    setState(() {
      centralizedSimNumber = newNumber;
    });
    
    // Save to persistent storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('centralized_sim', newNumber);
  }
  
  void _showSettingsDialog() {
    final TextEditingController controller = TextEditingController(
      text: centralizedSimNumber
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
                            centralizedSimNumber,
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