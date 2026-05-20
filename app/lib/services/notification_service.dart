import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'ble_service.dart';

class NavInstruction {
  final String direction;
  final int distance;
  final int eta;
  final String street;
  final String rawText;

  const NavInstruction({
    required this.direction,
    required this.distance,
    this.eta = 0,
    this.street = "",
    required this.rawText,
  });
}

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  BleService? _ble;
  bool _listenerRunning = false;
  NavInstruction? _lastInstruction;
  String _lastRawNotif = "";
  bool _hasPermission = false;
  ReceivePort? _port;

  bool get listenerRunning => _listenerRunning;
  NavInstruction? get lastInstruction => _lastInstruction;
  String get lastRawNotif => _lastRawNotif;
  bool get hasPermission => _hasPermission;

  void attachBle(BleService ble) {
    _ble = ble;
  }

  Future<void> startListening() async {
    bool? granted = await NotificationsListener.hasPermission;
    _hasPermission = granted ?? false;

    if (!_hasPermission) {
      await NotificationsListener.openPermissionSettings();
      return;
    }

    _port?.close();
    _port = ReceivePort();
    IsolateNameServer.removePortNameMapping("nav_assistant_notif");
    IsolateNameServer.registerPortWithName(
        _port!.sendPort, "nav_assistant_notif");
    _port!.listen((dynamic data) {
      if (data is NotificationEvent) _onNotification(data);
    });

    await NotificationsListener.startService(
      foreground: false,
      title: "Nav Assistant",
      description: "Listening for navigation updates",
    );

    _listenerRunning = true;
    notifyListeners();
  }

  Future<void> stopListening() async {
    await NotificationsListener.stopService();
    _port?.close();
    _port = null;
    IsolateNameServer.removePortNameMapping("nav_assistant_notif");
    _listenerRunning = false;
    notifyListeners();
  }

  void _onNotification(NotificationEvent event) {
    // DEBUG — log everything so we can see what fields are available
    debugPrint("=== NOTIF ===");
    debugPrint("pkg: ${event.packageName}");
    debugPrint("title: ${event.title}");
    debugPrint("text: ${event.text}");
    debugPrint("=============");

    final pkg   = event.packageName ?? "";
    final title = event.title       ?? "";
    final body  = event.text        ?? "";

    if (!_isNavApp(pkg)) return;

    _lastRawNotif = "[$pkg] $title | $body";
    notifyListeners();

    final instruction = _parse(title, body);
    if (instruction == null) return;

    _lastInstruction = instruction;
    notifyListeners();

    _ble?.sendNav(
      direction:      instruction.direction,
      distanceMeters: instruction.distance,
      etaMinutes:     instruction.eta,
      street:         instruction.street,
    );
  }

  bool _isNavApp(String pkg) {
    return pkg.contains("google.android.apps.maps") ||
           pkg.contains("waze")                     ||
           pkg.contains("here.maps")                ||
           pkg.contains("osmand");
}

  NavInstruction? _parse(String title, String body) {
    final t        = title.toLowerCase();
    final b        = body.toLowerCase();
    final combined = "$t $b";

    String direction = _parseDirection(t);
    if (direction.isEmpty) return null;

    return NavInstruction(
      direction: direction,
      distance:  _parseDistance(b.isNotEmpty ? b : t),
      eta:       _parseEta(combined),
      street:    _parseStreet(title),
      rawText:   "$title | $body",
    );
  }

  String _parseDirection(String text) {
    if (text.contains("u-turn") || text.contains("u turn") ||
        text.contains("uturn")) return "U_TURN";
    if (text.contains("arrive") || text.contains("destination") ||
        text.contains("reached")) return "ARRIVE";
    if (text.contains("roundabout"))
      return text.contains("right") ? "ROUNDABOUT_RIGHT" : "ROUNDABOUT_LEFT";
    if (text.contains("turn left")  || text.contains("keep left") ||
        text.contains("exit left"))  return "TURN_LEFT";
    if (text.contains("turn right") || text.contains("keep right") ||
        text.contains("exit right")) return "TURN_RIGHT";
    if (text.contains("straight") || text.contains("continue") ||
        text.contains("head ")    || text.contains("merge"))
      return "STRAIGHT";
    return "";
  }

  int _parseDistance(String text) {
    final kmMatch = RegExp(r'(\d+\.?\d*)\s*km').firstMatch(text);
    if (kmMatch != null)
      return (double.parse(kmMatch.group(1)!) * 1000).round();
    final mMatch = RegExp(r'(\d+\.?\d*)\s*m\b').firstMatch(text);
    if (mMatch != null) return double.parse(mMatch.group(1)!).round();
    return 0;
  }

  int _parseEta(String text) {
    int minutes = 0;
    final hrM  = RegExp(r'(\d+)\s*hr').firstMatch(text);
    final minM = RegExp(r'(\d+)\s*min').firstMatch(text);
    if (hrM  != null) minutes += int.parse(hrM.group(1)!)  * 60;
    if (minM != null) minutes += int.parse(minM.group(1)!);
    return minutes;
  }

  String _parseStreet(String title) {
    final prefixes = [
      "turn left onto ",  "turn right onto ",
      "turn left on ",    "turn right on ",
      "turn left",        "turn right",
      "keep left onto ",  "keep right onto ",
      "head north on ",   "head south on ",
      "head east on ",    "head west on ",
      "continue on ",     "continue onto ",
      "take the ",        "merge onto ",
      "head toward ",     "head towards ",
    ];
    String s = title;
    for (final p in prefixes) {
      if (s.toLowerCase().startsWith(p)) {
        s = s.substring(p.length);
        break;
      }
    }
    if (s.length > 20) s = s.substring(0, 20);
    return s.trim();
  }

  @override
  void dispose() {
    _port?.close();
    super.dispose();
  }
}