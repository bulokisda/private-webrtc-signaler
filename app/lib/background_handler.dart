import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String signalingServerUrl = "wss://family-video-signaler.onrender.com";

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackgroundEngine,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'call_engine_channel',
      initialNotificationTitle: 'System Engine Active',
      initialNotificationContent: 'Awaiting incoming visual requests...',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStartBackgroundEngine,
    ),
  );
}

@pragma('vm:entry-point')
void notificationTapBackgroundHandler(NotificationResponse response) {
  if (response.actionId == 'accept_call') {
    FlutterBackgroundService().invoke("notificationAction", {"action": "accept"});
  } else if (response.actionId == 'decline_call') {
    FlutterBackgroundService().invoke("notificationAction", {"action": "decline"});
  }
}

@pragma('vm:entry-point')
void onStartBackgroundEngine(ServiceInstance service) {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  WebSocketChannel? backgroundSocket;
  Timer? backgroundHeartbeat;
  Map<String, dynamic>? currentOffer;
  String? registeredId;

  void connectSocket() {
    backgroundHeartbeat?.cancel();
    try {
      backgroundSocket = WebSocketChannel.connect(Uri.parse(signalingServerUrl));
      
      backgroundSocket!.sink.add(json.encode({
        'type': 'register-tablet',
      }));
      
      backgroundHeartbeat = Timer.periodic(const Duration(seconds: 20), (timer) {
        backgroundSocket?.sink.add(json.encode({'type': 'ping'}));
      });

      backgroundSocket!.stream.listen(
        (message) {
          debugPrint("!! BACKGROUND ISOLATE RECEIVED SIGNALLING ENVELOPE: $message");
          
          var data = json.decode(message);
          
          if (data['type'] == 'registered') {
            registeredId = data['id'];
            debugPrint("Background engine assigned mesh identity node: $registeredId");
          }
          
          if (data['type'] == 'offer') {
            currentOffer = data;
            String displaySender = data['senderId'] ?? 'browser_node';
            
            flutterLocalNotificationsPlugin.show(
              100,
              'Incoming Visual Request',
              'User ($displaySender) is calling...',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'incoming_call_channel',
                  'Incoming Video Calls',
                  importance: Importance.max,
                  priority: Priority.high,
                  fullScreenIntent: true,
                  category: AndroidNotificationCategory.call,
                  actions: [
                    AndroidNotificationAction(
                      'accept_call',
                      'Answer',
                      cancelNotification: true,
                      showsUserInterface: true,
                    ),
                    AndroidNotificationAction(
                      'decline_call',
                      'Decline',
                      cancelNotification: true,
                    ),
                  ],
                ),
              ),
            );
          }
          
          if (data['type'] == 'hangup') {
            if (data['senderId'] == null || data['senderId'] == currentOffer?['senderId']) {
              currentOffer = null;
            }
          }
          
          service.invoke("onSignalReceived", {"data": message});
        },
        onError: (err) {
          backgroundSocket?.sink.close();
          Future.delayed(const Duration(seconds: 5), connectSocket);
        },
        onDone: () {
          Future.delayed(const Duration(seconds: 5), connectSocket);
        },
        cancelOnError: true,
      );
    } catch (e) {
      Future.delayed(const Duration(seconds: 5), connectSocket);
    }
  }

  service.on('notificationAction').listen((event) {
    if (event == null) return;
    if (event['action'] == 'accept' && currentOffer != null) {
      service.invoke("onSignalReceived", {
        "data": json.encode({
          'type': 'accept-from-notification',
          'sdp': currentOffer!['sdp'],
          'senderId': currentOffer!['senderId'] ?? 'browser_node',
        }),
      });
    } else if (event['action'] == 'decline') {
      if (currentOffer != null) {
        backgroundSocket?.sink.add(json.encode({
          'type': 'hangup',
          'targetId': currentOffer!['senderId']
        }));
        currentOffer = null;
      } else {
        backgroundSocket?.sink.add(json.encode({'type': 'hangup'}));
      }
      service.invoke("onSignalReceived", {
        "data": json.encode({'type': 'hangup'}),
      });
    }
  });

  service.on('checkStatus').listen((event) {
    if (currentOffer != null) {
      service.invoke("onSignalReceived", {"data": json.encode(currentOffer)});
    }
    if (registeredId != null) {
      service.invoke("onSignalReceived", {
        "data": json.encode({
          'type': 'registered',
          'id': registeredId,
        })
      });
    }
  });

  service.on('stopService').listen((event) {
    backgroundHeartbeat?.cancel();
    backgroundSocket?.sink.close();
    service.stopSelf();
  });

  service.on('sendSignal').listen((event) {
    if (backgroundSocket != null && event != null) {
      backgroundSocket!.sink.add(event['payload']);
    }
  });

  Timer.run(() {
    connectSocket();
  });
}
