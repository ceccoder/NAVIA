import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Service managing Bluetooth Low Energy communication with the ESP32-C3 wearable.
class BleService {
  // Singleton pattern
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // UUIDs matching the ESP32-C3 GATT Server
  static const String naviaDeviceName = 'NAVIA-Wearable';
  static final Guid serviceUuid = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final Guid rxCharUuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8'); // Write to ESP32
  static final Guid txCharUuid = Guid('beb5483f-36e1-4688-b7f5-ea07361b26a8'); // Notify to Mobile

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  // State notifiers
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> connectedDeviceNameNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String> lastCommandSentNotifier = ValueNotifier<String>('-');
  final ValueNotifier<String?> obstacleWarningNotifier = ValueNotifier<String?>(null);

  final List<ScanResult> discoveredDevices = [];
  final StreamController<String> _hazardController = StreamController<String>.broadcast();
  Stream<String> get onHazardAlert => _hazardController.stream;

  bool get isConnected => isConnectedNotifier.value;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Starts scanning for nearby BLE peripherals.
  Future<void> startScan({Duration timeout = const Duration(seconds: 8)}) async {
    discoveredDevices.clear();
    isScanningNotifier.value = true;

    try {
      // Check if Bluetooth is turned on
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        debugPrint('[BLE] Bluetooth adapter is off. Requesting enable...');
        await FlutterBluePlus.turnOn();
      }

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final index = discoveredDevices.indexWhere((d) => d.device.remoteId == r.device.remoteId);
          if (index != -1) {
            discoveredDevices[index] = r;
          } else {
            discoveredDevices.add(r);
          }

          // Auto-connect if target device name is found
          if (r.device.platformName == naviaDeviceName && !isConnected) {
            debugPrint('[BLE] Found target device ${r.device.platformName}, auto-connecting...');
            connectToDevice(r.device);
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      debugPrint('[BLE] Scan exception: $e');
    } finally {
      Future.delayed(timeout, () {
        isScanningNotifier.value = false;
      });
    }
  }

  /// Cancels active BLE scanning.
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      isScanningNotifier.value = false;
    } catch (e) {
      debugPrint('[BLE] Stop scan exception: $e');
    }
  }

  /// Connects to a specific BLE device and discovers GATT services.
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await stopScan();
      debugPrint('[BLE] Connecting to ${device.platformName} (${device.remoteId})...');

      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
      _connectedDevice = device;

      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        final connected = (state == BluetoothConnectionState.connected);
        isConnectedNotifier.value = connected;
        connectedDeviceNameNotifier.value = connected ? (device.platformName.isEmpty ? 'NAVIA-Wearable' : device.platformName) : null;

        if (!connected) {
          _rxCharacteristic = null;
          _txCharacteristic = null;
          debugPrint('[BLE] Disconnected from wearable');
        }
      });

      // Discover GATT services
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid == serviceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid == rxCharUuid) {
              _rxCharacteristic = char;
              debugPrint('[BLE] Found RX Characteristic for Haptics');
            }
            if (char.uuid == txCharUuid) {
              _txCharacteristic = char;
              await _subscribeToProximityNotifications(char);
              debugPrint('[BLE] Found TX Characteristic for ToF Proximity Alerts');
            }
          }
        }
      }

      isConnectedNotifier.value = true;
      connectedDeviceNameNotifier.value = device.platformName.isEmpty ? 'NAVIA-Wearable' : device.platformName;
      return true;
    } catch (e) {
      debugPrint('[BLE] Connection failed: $e');
      disconnect();
      return false;
    }
  }

  /// Subscribes to notification stream sent from the ESP32-C3 VL53L0X sensor.
  Future<void> _subscribeToProximityNotifications(BluetoothCharacteristic char) async {
    try {
      await char.setNotifyValue(true);
      _notifySubscription?.cancel();
      _notifySubscription = char.onValueReceived.listen((data) {
        if (data.isNotEmpty) {
          final message = utf8.decode(data, allowMalformed: true).trim();
          debugPrint('[BLE NOTIFY] ESP32 Proximity Alert: $message');

          if (message.startsWith('S') || message.contains('OBSTACLE')) {
            obstacleWarningNotifier.value = 'Obstacle Detected Ahead (< 70cm)!';
            _hazardController.add(message);

            // Clear obstacle alert banner after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              obstacleWarningNotifier.value = null;
            });
          }
        }
      });
    } catch (e) {
      debugPrint('[BLE] Failed to subscribe to notifications: $e');
    }
  }

  /// Sends a single vibration guidance byte to the wearable:
  /// 'L' = Left Motor Pulse, 'R' = Right Motor Pulse, 'S' = Stop / Both Motors Pulse
  Future<bool> sendCommand(String command) async {
    lastCommandSentNotifier.value = command;

    if (_rxCharacteristic != null && isConnected) {
      try {
        final bytes = utf8.encode(command);
        await _rxCharacteristic!.write(bytes, withoutResponse: false);
        debugPrint('[BLE TX] Dispatched command to ESP32: "$command"');
        return true;
      } catch (e) {
        debugPrint('[BLE TX] Error writing characteristic: $e');
        return false;
      }
    } else {
      // Hardware emulation logging when testing app without physical ESP32
      debugPrint('[BLE EMULATION] Dispatched virtual command: "$command" (Wearable offline)');
      return false;
    }
  }

  /// Disconnects from current wearable.
  Future<void> disconnect() async {
    try {
      await _notifySubscription?.cancel();
      await _connectionSubscription?.cancel();
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('[BLE] Disconnect error: $e');
    } finally {
      _connectedDevice = null;
      _rxCharacteristic = null;
      _txCharacteristic = null;
      isConnectedNotifier.value = false;
      connectedDeviceNameNotifier.value = null;
    }
  }

  void dispose() {
    disconnect();
    _scanSubscription?.cancel();
    _hazardController.close();
  }
}
