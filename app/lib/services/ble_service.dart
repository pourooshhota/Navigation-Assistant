import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

// ── BLE UUIDs must match the firmware exactly ──
const _serviceUuid      = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const _charUuidWrite    = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
const _charUuidNotify   = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
const _deviceName       = "Nav_Assistant";

enum BleStatus { idle, scanning, connecting, connected, error }

class BleService extends ChangeNotifier {
  final _ble = FlutterReactiveBle();

  BleStatus _status    = BleStatus.idle;
  String    _statusMsg = "Not connected";
  String?   _deviceId;

  StreamSubscription? _scanSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _notifySub;

  QualifiedCharacteristic? _writeChar;
  QualifiedCharacteristic? _notifyChar;

  // Last message received from ESP32 (e.g. "PONG")
  String _lastRx = "";

  BleStatus get status    => _status;
  String    get statusMsg => _statusMsg;
  String    get lastRx    => _lastRx;
  bool      get isConnected => _status == BleStatus.connected;

  // ── Request Android BLE permissions ──
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ── Scan for Mochi_Nav and connect ──
  Future<void> startScan() async {
    if (_status == BleStatus.scanning || _status == BleStatus.connecting) return;

    bool granted = await requestPermissions();
    if (!granted) {
      _setStatus(BleStatus.error, "Permissions denied");
      return;
    }

    _setStatus(BleStatus.scanning, "Scanning for Nav_Assistant...");

    _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(withServices: [])
        .listen((device) {
      if (device.name == _deviceName) {
        _scanSub?.cancel();
        _connect(device.id);
      }
    }, onError: (e) {
      _setStatus(BleStatus.error, "Scan error: $e");
    });

    // Timeout after 15 s
    Future.delayed(const Duration(seconds: 15), () {
      if (_status == BleStatus.scanning) {
        _scanSub?.cancel();
        _setStatus(BleStatus.idle, "Device not found");
      }
    });
  }

  void _connect(String deviceId) {
    _deviceId = deviceId;
    _setStatus(BleStatus.connecting, "Connecting...");

    _connectSub?.cancel();
    _connectSub = _ble
        .connectToDevice(
          id: deviceId,
          servicesWithCharacteristicsToDiscover: {},
          connectionTimeout: const Duration(seconds: 30),
        )
        .listen((update) {
      switch (update.connectionState) {
        case DeviceConnectionState.connected:
          _onConnected(deviceId);
          break;
        case DeviceConnectionState.disconnected:
          _setStatus(BleStatus.idle, "Disconnected");
          _writeChar  = null;
          _notifyChar = null;
          break;
        default:
          break;
      }
    }, onError: (e) {
      _setStatus(BleStatus.error, "Connection error: $e");
    });
  }

  void _onConnected(String deviceId) async{
    await Future.delayed(const Duration(seconds: 2));
    _writeChar = QualifiedCharacteristic(
      serviceId:        Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_charUuidWrite),
      deviceId:         deviceId,
    );
    _notifyChar = QualifiedCharacteristic(
      serviceId:        Uuid.parse(_serviceUuid),
      characteristicId: Uuid.parse(_charUuidNotify),
      deviceId:         deviceId,
    );

    // Subscribe to TX notifications from ESP32
    _notifySub?.cancel();
    _notifySub = _ble.subscribeToCharacteristic(_notifyChar!).listen((data) {
      _lastRx = utf8.decode(data);
      notifyListeners();
    });

    _setStatus(BleStatus.connected, "Connected to Nav_Assistant");

    // Send a ping to verify two-way communication
    Future.delayed(const Duration(milliseconds: 500), () => send("PING"));
  }

  // ── Send a string to the ESP32 ──
  Future<void> send(String message) async {
  debugPrint("BLE send called: $message");
  debugPrint("Status: $_status, writeChar: $_writeChar");
  if (_writeChar == null || _status != BleStatus.connected) {
    debugPrint("BLE send skipped — not ready");
    return;
  }
  try {
    debugPrint("BLE sending: $message");
    await _ble.writeCharacteristicWithoutResponse(
      _writeChar!,
      value: utf8.encode(message),
    );
    debugPrint("BLE sent OK");
  } catch (e) {
    debugPrint("BLE send error: $e");
  }
}

  // ── Send navigation data ──
  // Format: NAV,<direction>,<distance_m>,<eta_min>,<street>
  Future<void> sendNav({
    required String direction,
    required int    distanceMeters,
    int             etaMinutes = 0,
    String          street     = "",
  }) async {
    final msg = "NAV,$direction,$distanceMeters,$etaMinutes,$street";
    await send(msg);
  }

  // ── Disconnect ──
  void disconnect() {
    _scanSub?.cancel();
    _connectSub?.cancel();
    _notifySub?.cancel();
    _deviceId   = null;
    _writeChar  = null;
    _notifyChar = null;
    _setStatus(BleStatus.idle, "Disconnected");
  }

  void _setStatus(BleStatus s, String msg) {
    _status    = s;
    _statusMsg = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectSub?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }
}
