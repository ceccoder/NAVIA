import 'package:flutter/material.dart';
import '../services/ble_service.dart';

/// Screen managing Bluetooth Low Energy pairing with the ESP32-C3 wearable device.
class BleSetupScreen extends StatefulWidget {
  const BleSetupScreen({super.key});

  @override
  State<BleSetupScreen> createState() => _BleSetupScreenState();
}

class _BleSetupScreenState extends State<BleSetupScreen> {
  final BleService _ble = BleService();

  @override
  void initState() {
    super.initState();
    _ble.startScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Wearable Haptic Setup'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _ble.isScanningNotifier,
            builder: (context, scanning, _) {
              return IconButton(
                icon: Icon(scanning ? Icons.stop_circle_outlined : Icons.refresh_rounded),
                onPressed: () {
                  if (scanning) {
                    _ble.stopScan();
                  } else {
                    _ble.startScan();
                  }
                },
                tooltip: scanning ? 'Stop Scan' : 'Scan for Devices',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status Card
              ValueListenableBuilder<bool>(
                valueListenable: _ble.isConnectedNotifier,
                builder: (context, connected, _) {
                  return ValueListenableBuilder<String?>(
                    valueListenable: _ble.connectedDeviceNameNotifier,
                    builder: (context, devName, _) {
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: connected ? const Color(0xFF064E3B) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: connected ? const Color(0xFF10B981) : const Color(0xFF334155),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                              color: connected ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                              size: 32,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    connected ? 'Connected: ${devName ?? "NAVIA-Wearable"}' : 'Wearable Disconnected',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    connected
                                        ? 'ESP32-C3 Ready (GPIO 0 & 1 Haptics + VL53L0X Active)'
                                        : 'Looking for "NAVIA-Wearable"...',
                                    style: TextStyle(
                                      color: connected ? const Color(0xFFA7F3D0) : const Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (connected)
                              ElevatedButton(
                                onPressed: () => _ble.disconnect(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Disconnect'),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 20),

              // Hardware Haptic Pulse Diagnostics
              const Text(
                'TEST HAPTIC ACTUATION',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _ble.sendCommand('L'),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Left Motor (GPIO 0)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _ble.sendCommand('R'),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Right Motor (GPIO 1)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _ble.sendCommand('S'),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Hazard Pulse - Both Motors (CMD: S)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Discovered Peripherals List
              const Text(
                'DISCOVERED BLUETOOTH DEVICES',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_ble.isScanningNotifier, _ble.isConnectedNotifier]),
                  builder: (context, _) {
                    final devices = _ble.discoveredDevices;
                    if (devices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFF38BDF8)),
                            const SizedBox(height: 14),
                            Text(
                              _ble.isScanningNotifier.value
                                  ? 'Scanning for NAVIA-Wearable...'
                                  : 'No Bluetooth devices found. Tap Refresh to scan.',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final item = devices[index];
                        final name = item.device.platformName.isNotEmpty
                            ? item.device.platformName
                            : 'Unknown Peripheral';
                        final isTarget = name.contains('NAVIA');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isTarget ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isTarget ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                              width: isTarget ? 1.5 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              isTarget ? Icons.watch_rounded : Icons.bluetooth,
                              color: isTarget ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'ID: ${item.device.remoteId}  •  RSSI: ${item.rssi} dBm',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _ble.connectToDevice(item.device),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isTarget ? const Color(0xFF0284C7) : const Color(0xFF334155),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Connect'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
