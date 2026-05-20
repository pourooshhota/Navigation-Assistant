import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Wire up BLE <-> NotificationService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble  = context.read<BleService>();
      final notif = context.read<NotificationService>();
      notif.attachBle(ble);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _Header(),
              SizedBox(height: 24),
              _BleCard(),
              SizedBox(height: 16),
              _NavCard(),
              SizedBox(height: 16),
              _NotifCard(),
              Spacer(),
              _DebugPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A4A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.navigation, color: Color(0xFF7B8CDE), size: 22),
      ),
      const SizedBox(width: 12),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Mochi Nav",
            style: TextStyle(color: Colors.white, fontSize: 20,
                fontWeight: FontWeight.bold, letterSpacing: 1)),
          Text("ESP32 Navigation Bridge",
            style: TextStyle(color: Color(0xFF666688), fontSize: 12)),
        ],
      ),
    ]);
  }
}

// ── BLE Card ──────────────────────────────────────────────────────────────────
class _BleCard extends StatelessWidget {
  const _BleCard();
  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();

    Color statusColor;
    IconData statusIcon;
    switch (ble.status) {
      case BleStatus.connected:
        statusColor = const Color(0xFF4CAF7D);
        statusIcon  = Icons.bluetooth_connected;
        break;
      case BleStatus.scanning:
      case BleStatus.connecting:
        statusColor = const Color(0xFFFFB74D);
        statusIcon  = Icons.bluetooth_searching;
        break;
      case BleStatus.error:
        statusColor = const Color(0xFFEF5350);
        statusIcon  = Icons.bluetooth_disabled;
        break;
      default:
        statusColor = const Color(0xFF666688);
        statusIcon  = Icons.bluetooth;
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(statusIcon, color: statusColor, size: 18),
            const SizedBox(width: 8),
            Text("Bluetooth", style: TextStyle(color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.4)),
              ),
              child: Text(ble.status.name.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10,
                    fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(ble.statusMsg,
            style: const TextStyle(color: Color(0xFF888899), fontSize: 13)),
          const SizedBox(height: 14),
          Row(children: [
            if (!ble.isConnected) ...[
              Expanded(child: _ActionButton(
                label: ble.status == BleStatus.scanning ? "Scanning..." : "Connect",
                icon: Icons.bluetooth_searching,
                onTap: ble.status == BleStatus.scanning
                    ? null
                    : () => context.read<BleService>().startScan(),
              )),
            ] else ...[
              Expanded(child: _ActionButton(
                label: "Disconnect",
                icon: Icons.bluetooth_disabled,
                color: const Color(0xFFEF5350),
                onTap: () => context.read<BleService>().disconnect(),
              )),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(
                label: "Ping",
                icon: Icons.sensors,
                onTap: () => context.read<BleService>().send("PING"),
              )),
            ],
          ]),
          if (ble.lastRx.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("← ${ble.lastRx}",
              style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

// ── Nav Preview Card ──────────────────────────────────────────────────────────
class _NavCard extends StatelessWidget {
  const _NavCard();

  static const _icons = {
    "TURN_LEFT":         Icons.turn_left,
    "TURN_RIGHT":        Icons.turn_right,
    "STRAIGHT":          Icons.straight,
    "U_TURN":            Icons.u_turn_left,
    "ARRIVE":            Icons.flag,
    "ROUNDABOUT_LEFT":   Icons.roundabout_left,
    "ROUNDABOUT_RIGHT":  Icons.roundabout_right,
  };

  @override
  Widget build(BuildContext context) {
    final nav  = context.watch<NotificationService>();
    final inst = nav.lastInstruction;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.map_outlined, color: Color(0xFF7B8CDE), size: 18),
            const SizedBox(width: 8),
            Text("Last Instruction",
              style: TextStyle(color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          if (inst == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text("Waiting for Google Maps navigation...",
                  style: TextStyle(color: Color(0xFF555566), fontSize: 13)),
              ),
            )
          else
            Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2040),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _icons[inst.direction] ?? Icons.navigation,
                  color: const Color(0xFF7B8CDE), size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inst.direction.replaceAll("_", " "),
                    style: const TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.bold)),
                  if (inst.street.isNotEmpty)
                    Text(inst.street,
                      style: const TextStyle(color: Color(0xFF7B8CDE), fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(children: [
                    _Chip(Icons.straighten, _formatDist(inst.distance)),
                    if (inst.eta > 0) ...[
                      const SizedBox(width: 8),
                      _Chip(Icons.schedule, "${inst.eta} min"),
                    ],
                  ]),
                ],
              )),
            ]),
        ],
      ),
    );
  }

  String _formatDist(int m) {
    if (m == 0) return "--";
    if (m < 1000) return "$m m";
    return "${(m / 1000).toStringAsFixed(1)} km";
  }
}

// ── Notification Listener Card ────────────────────────────────────────────────
class _NotifCard extends StatelessWidget {
  const _NotifCard();
  @override
  Widget build(BuildContext context) {
    final notif = context.watch<NotificationService>();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.notifications_outlined,
              color: notif.listenerRunning
                  ? const Color(0xFF4CAF7D)
                  : const Color(0xFF666688),
              size: 18),
            const SizedBox(width: 8),
            Text("Notification Listener",
              style: TextStyle(color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600)),
            const Spacer(),
            Switch(
              value: notif.listenerRunning,
              onChanged: (val) async {
                if (val) {
                  await context.read<NotificationService>().startListening();
                } else {
                  await context.read<NotificationService>().stopListening();
                }
              },
              activeColor: const Color(0xFF4CAF7D),
            ),
          ]),
          if (!notif.hasPermission && !notif.listenerRunning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "⚠ Tap the toggle to open Android Settings and grant Notification Access to Mochi Nav.",
                style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
              ),
            ),
          if (notif.lastRawNotif.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(notif.lastRawNotif,
                style: const TextStyle(color: Color(0xFF555566), fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

// ── Debug Panel ───────────────────────────────────────────────────────────────
class _DebugPanel extends StatelessWidget {
  const _DebugPanel();
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      collapsedIconColor: const Color(0xFF444466),
      iconColor: const Color(0xFF7B8CDE),
      title: const Text("Manual Test",
        style: TextStyle(color: Color(0xFF666688), fontSize: 13)),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final dir in [
            "TURN_LEFT", "TURN_RIGHT", "STRAIGHT",
            "U_TURN", "ARRIVE", "ROUNDABOUT_RIGHT"
          ])
            _TestButton(dir),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TestButton extends StatelessWidget {
  final String direction;
  const _TestButton(this.direction);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<BleService>().sendNav(
        direction:      direction,
        distanceMeters: 150,
        etaMinutes:     3,
        street:         "Test St",
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF333355)),
        ),
        child: Text(direction.replaceAll("_", " "),
          style: const TextStyle(color: Color(0xFF7B8CDE), fontSize: 11)),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13132A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color?   color;
  final VoidCallback? onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF7B8CDE);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.withOpacity(onTap == null ? 0.05 : 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: onTap == null ? c.withOpacity(0.4) : c, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: onTap == null ? c.withOpacity(0.4) : c,
              fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _Chip(this.icon, this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2040),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: const Color(0xFF7B8CDE)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xFF9999BB), fontSize: 11)),
      ]),
    );
  }
}
