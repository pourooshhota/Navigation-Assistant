import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'services/ble_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

// Must be a top-level function, outside any class
@pragma('vm:entry-point')
void _notificationCallback(NotificationEvent event) {
  final send = IsolateNameServer.lookupPortByName("nav_assistant_notif");
  send?.send(event);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationsListener.initialize(callbackHandle: _notificationCallback);
  runApp(const NavAssistantApp());
}

class NavAssistantApp extends StatelessWidget {
  const NavAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        title: 'Nav Assistant',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A1A2E),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          fontFamily: 'monospace',
        ),
        home: const HomeScreen(),
      ),
    );
  }
}