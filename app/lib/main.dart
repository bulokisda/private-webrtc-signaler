import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_handler.dart';
import 'video_call_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize notification channels safely on the main UI Isolate thread
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
    'incoming_call_channel',
    'Incoming Video Calls',
    description: 'Displays full-screen incoming video call alerts.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // FIXED: Explicitly passing the type as a generic parameter prevents the platform lookup from panicking
  final androidImplementation = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  if (androidImplementation != null) {
    await androidImplementation.createNotificationChannel(callChannel);
  }

  const initializationSettingsAndroid = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
    onDidReceiveNotificationResponse: notificationTapBackgroundHandler,
    onDidReceiveBackgroundNotificationResponse:
        notificationTapBackgroundHandler,
  );

  // 2. Launch UI immediately so the user doesn't see a black splash screen
  runApp(const MyApp());

  // 3. Fire off the signaling worker service asynchronously
  scheduleMicrotask(() async {
    await initializeBackgroundService();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Call',
      theme: ThemeData(brightness: Brightness.dark),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/call': (context) => const VideoCallScreen(),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isOnline = false;
  dynamic _remoteSdpOffer;
  StreamSubscription? _serviceSubscription;

  @override
  void initState() {
    super.initState();
    _bindCommunicationChannel();
    Future.delayed(const Duration(milliseconds: 1000), () {
      FlutterBackgroundService().invoke('checkStatus');
    });
  }

  void _bindCommunicationChannel() {
    _serviceSubscription = FlutterBackgroundService()
        .on('onSignalReceived')
        .listen((event) {
          if (event == null || event['data'] == null) return;

          print("!! FOREGROUND UI ISOLATE RECEIVED PACKET: ${event['data']}");

          var data = jsonDecode(event['data']);

          if (!_isOnline) {
            setState(() => _isOnline = true);
          }

          if (data['type'] == 'offer') {
            setState(() => _remoteSdpOffer = data['sdp']);

            if (mounted) {
              // Wrap variables cleanly inside a dictionary so the WebRTC screen
              // can read both the unique sender string and the SDP parameters!
              Navigator.pushNamed(
                context,
                '/call',
                arguments: {
                  'sdp': data['sdp'],
                  'senderId': data['senderId'] ?? 'browser_node',
                },
              );
            }
          } else if (data['type'] == 'accept-from-notification') {
            if (mounted) {
              Navigator.pushNamed(
                context,
                '/call',
                arguments: {
                  'sdp': data['sdp'],
                  'senderId': data['senderId'] ?? 'browser_node',
                },
              );
            }
          }
        });
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.circle,
              color: _isOnline ? Colors.green : Colors.red,
              size: 24,
            ),
            const SizedBox(height: 10),
            Text(
              _isOnline
                  ? "Signaling Engine Connected"
                  : "Connecting to Engine...",
            ),
            if (_remoteSdpOffer != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  FlutterBackgroundService().invoke("notificationAction", {
                    "action": "accept",
                  });
                },
                child: const Text("Answer Call from UI"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
