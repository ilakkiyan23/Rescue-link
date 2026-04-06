import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class RescueBleService {
  RescueBleService._();

  static Future<bool> isSupported() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  static BluetoothAdapterState adapterStateNow() {
    try {
      return FlutterBluePlus.adapterStateNow;
    } catch (_) {
      return BluetoothAdapterState.unknown;
    }
  }

  static Stream<BluetoothAdapterState> adapterStateStream() {
    try {
      return FlutterBluePlus.adapterState;
    } catch (_) {
      return const Stream<BluetoothAdapterState>.empty();
    }
  }

  static Stream<List<ScanResult>> scanResultsStream() {
    try {
      return FlutterBluePlus.scanResults;
    } catch (_) {
      return const Stream<List<ScanResult>>.empty();
    }
  }

  /// Android 12+ runtime permissions for BLE scan/connect.
  static Future<bool> requestAndroidBlePermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    return scan.isGranted && connect.isGranted;
  }

  static Future<void> startDiscoveryScan() async {
    if (!await isSupported()) {
      return;
    }
    if (adapterStateNow() != BluetoothAdapterState.on) {
      return;
    }
    if (_isScanningNow()) {
      return;
    }
    try {
      await FlutterBluePlus.startScan(androidUsesFineLocation: true);
    } catch (_) {}
  }

  static Future<void> stopDiscoveryScan() async {
    if (_isScanningNow()) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  /// Android: triggers the system Bluetooth-enable flow immediately (no in-app
  /// confirmation step from us). The OS may still show its own sheet; Apple
  /// does not allow apps to turn Bluetooth on programmatically.
  static Future<void> requestAdapterOnForEmergency() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (!await isSupported()) {
      return;
    }
    try {
      await FlutterBluePlus.turnOn(timeout: 60);
    } catch (_) {}
  }

  static bool _isScanningNow() {
    try {
      return FlutterBluePlus.isScanningNow;
    } catch (_) {
      return false;
    }
  }
}
