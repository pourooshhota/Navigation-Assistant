# Navigation Assistant

A compact navigation system built with an ESP32-C3 and a custom Android app. Displays real-time Google Maps turn-by-turn directions on an OLED screen over Bluetooth Low Energy.

![Status](https://img.shields.io/badge/status-active-brightgreen)
![Platform](https://img.shields.io/badge/platform-ESP32--C3-blue)
![App](https://img.shields.io/badge/app-Flutter%20Android-blue)

---

## How It Works

```
Google Maps → Android Notification → Flutter App → BLE → ESP32-C3 → OLED Display
```

1. Google Maps posts a navigation notification for every turn instruction
2. The Android app reads it using Android's NotificationListenerService
3. The app parses the direction, distance, street name, and ETA
4. It sends the parsed data to the ESP32-C3 over Bluetooth Low Energy
5. The ESP32 displays the direction arrow and info on the OLED screen

---

## Hardware

| Component | Details |
|-----------|---------|
| Microcontroller | ESP32-C3 Dev Module |
| Display | SSD1306 128×64 OLED (I2C) |
| Button | Tactile push button |
| Speaker | Passive buzzer (optional) |
| Power | USB or LiPo battery |

### Wiring

| OLED | ESP32-C3 |
|------|----------|
| SDA  | GPIO 4   |
| SCL  | GPIO 5   |
| VCC  | 3.3V     |
| GND  | GND      |

| Component | ESP32-C3 |
|-----------|----------|
| Button    | GPIO 2   |
| Speaker + | GPIO 3   |

---

## Firmware Setup

### Requirements
- Arduino IDE 2.x
- ESP32 board package by Espressif (v3.x)
- U8g2 library by oliver

### Install
1. Open `firmware/nav_assistant.ino` in Arduino IDE
2. Select board: **ESP32C3 Dev Module**
3. Enable: Tools → USB CDC On Boot → **Enabled**
4. Upload

---

## Android App Setup

### Requirements
- Flutter SDK 3.x
- Android Studio (for Android SDK)

### Build & Install
```bash
cd app
flutter pub get
flutter run
```

### Permissions Required
- Bluetooth (Nearby devices)
- Notification Access (for reading Google Maps notifications)

---

## BLE Protocol

```
Phone → ESP32:
  NAV,<direction>,<distance_m>,<eta_min>,<street>
  PING

ESP32 → Phone:
  PONG
```

**Direction values:**
`TURN_LEFT` · `TURN_RIGHT` · `STRAIGHT` · `U_TURN` · `ARRIVE` · `ROUNDABOUT_LEFT` · `ROUNDABOUT_RIGHT`

---

## Features

- Real-time turn-by-turn direction arrows on OLED
- Street name display (scrolling if long)
- ETA display
- Idle face animation when not navigating
- Night mode (long press button)
- Audio toggle (short press button)
- Auto-reconnect BLE
- Works with Google Maps and Waze

---

## Project Structure

```
nav-assistant/
├── firmware/
│   └── nav_assistant.ino      # ESP32-C3 firmware
└── app/
    ├── lib/
    │   ├── main.dart
    │   ├── services/
    │   │   ├── ble_service.dart
    │   │   └── notification_service.dart
    │   └── screens/
    │       └── home_screen.dart
    ├── android/
    │   └── app/src/main/
    │       └── AndroidManifest.xml
    └── pubspec.yaml
```

---

## Built With

- [ESP32 Arduino Core](https://github.com/espressif/arduino-esp32)
- [U8g2](https://github.com/olikraus/u8g2)
- [Flutter](https://flutter.dev)
- [flutter_reactive_ble](https://pub.dev/packages/flutter_reactive_ble)
- [flutter_notification_listener](https://pub.dev/packages/flutter_notification_listener)
