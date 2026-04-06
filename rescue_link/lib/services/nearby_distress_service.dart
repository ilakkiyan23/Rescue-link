import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

class DistressPacket {
  final String id;
  final String sender;
  final double lat;
  final double lon;
  final int time;

  const DistressPacket({
    required this.id,
    required this.sender,
    required this.lat,
    required this.lon,
    required this.time,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'sender': sender,
    'lat': lat,
    'lon': lon,
    'time': time,
  };

  static DistressPacket? tryFromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) {
      return null;
    }
    return DistressPacket(
      id: id,
      sender: map['sender']?.toString() ?? 'unknown',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lon: (map['lon'] as num?)?.toDouble() ?? 0,
      time: (map['time'] as num?)?.toInt() ?? 0,
    );
  }

  static DistressPacket build({
    required double lat,
    required double lon,
    required String sender,
  }) {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    return DistressPacket(
      id: 'MSG_${sender}_${nowMillis}_${Random().nextInt(9999)}',
      sender: sender,
      lat: lat,
      lon: lon,
      time: nowMillis ~/ 1000,
    );
  }
}

class MeshStatus {
  final bool advertising;
  final bool discovering;
  final int discoveredPeers;
  final int connectedPeers;

  const MeshStatus({
    required this.advertising,
    required this.discovering,
    required this.discoveredPeers,
    required this.connectedPeers,
  });

  bool get running => advertising && discovering;
}

class NearbyDistressService {
  NearbyDistressService._();

  static final NearbyDistressService instance = NearbyDistressService._();

  static const String serviceId = 'com.example.rescue_link.mesh';
  static const Strategy strategy = Strategy.P2P_CLUSTER;
  static const Duration _maintenanceInterval = Duration(seconds: 3);
  static const int _maxStoredPackets = 200;

  final Nearby _nearby = Nearby();
  final Set<String> _connectedEndpoints = <String>{};
  final Set<String> _seenMessages = <String>{};
  final Map<String, String> _endpointNames = <String, String>{};
    final Map<String, DistressPacket> _activePacketsBySender =
      <String, DistressPacket>{};

  final StreamController<String> _logsController =
      StreamController<String>.broadcast();
  final StreamController<MeshStatus> _statusController =
      StreamController<MeshStatus>.broadcast();
  final StreamController<DistressPacket> _packetController =
      StreamController<DistressPacket>.broadcast();
    final StreamController<String> _clearController =
      StreamController<String>.broadcast();

  bool _isRunning = false;
  bool _advertising = false;
  bool _discovering = false;
  Timer? _maintenanceTimer;
  DistressPacket? _pendingPacket;
  String _deviceName = 'RescueLink';
  String _selfId = '';

  Stream<String> get logsStream => _logsController.stream;
  Stream<MeshStatus> get statusStream => _statusController.stream;
  Stream<DistressPacket> get packetStream => _packetController.stream;
  Stream<String> get clearStream => _clearController.stream;
  String get selfId => _selfId;
  bool get isRunning => _isRunning;
  List<DistressPacket> get storedPackets {
    final packets = _activePacketsBySender.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return List<DistressPacket>.unmodifiable(packets);
  }

  Future<bool> requestPermissions() async {
    final locationWhenInUse = await Permission.locationWhenInUse.request();
    if (!locationWhenInUse.isGranted) {
      return false;
    }

    if (!Platform.isAndroid) {
      return true;
    }

    final sdkInt = await _androidSdkInt();

    if (sdkInt <= 30) {
      final location = await Permission.location.request();
      if (!location.isGranted) {
        return false;
      }
    }

    if (sdkInt >= 31) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      final scan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final advertise =
          statuses[Permission.bluetoothAdvertise]?.isGranted ?? false;
      if (!scan || !connect || !advertise) {
        return false;
      }
    }

    if (sdkInt >= 33) {
      final wifi = await Permission.nearbyWifiDevices.request();
      if (!wifi.isGranted) {
        return false;
      }
    }

    return true;
  }

  Future<int> _androidSdkInt() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt;
  }

  Future<bool> start({required String deviceName}) async {
    await stop();

    _isRunning = true;
    _deviceName = deviceName;
    _selfId = _selfId.isNotEmpty
        ? _selfId
        : 'node_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    try {
      await _nearby.startAdvertising(
        _deviceName,
        strategy,
        onConnectionInitiated: (id, info) {
          _log('Incoming connection: ${info.endpointName} ($id)');
          unawaited(_accept(id));
        },
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );
      _advertising = true;
      _emitStatus();
    } catch (e) {
      _log('Advertising failed: $e');
      _advertising = false;
      _emitStatus();
      return false;
    }

    try {
      await _nearby.startDiscovery(
        _deviceName,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: serviceId,
      );
      _discovering = true;
      _emitStatus();
    } catch (e) {
      _log('Discovery failed: $e');
      _discovering = false;
      _emitStatus();
      return false;
    }

    _log('Mesh started ($_deviceName)');
    _startMaintenanceLoop();
    return true;
  }

  Future<bool> ensureRunning({required String deviceName}) async {
    if (_isRunning) {
      return true;
    }
    return start(deviceName: deviceName);
  }

  Future<void> stop() async {
    _isRunning = false;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    await _nearby.stopDiscovery();
    await _nearby.stopAdvertising();
    await _nearby.stopAllEndpoints();
    _connectedEndpoints.clear();
    _endpointNames.clear();
    _pendingPacket = null;
    _advertising = false;
    _discovering = false;
    _emitStatus();
  }

  Future<void> resolveOwnAlert() async {
    await _resolveAlertBySender(_deviceName, emitClear: true);
    await _resolveAlertBySender(_selfId, emitClear: false);
    if (_connectedEndpoints.isEmpty) {
      return;
    }
    final bytes = _encodeClearEnvelope(_deviceName);
    for (final endpointId in _connectedEndpoints) {
      try {
        await _nearby.sendBytesPayload(endpointId, bytes);
      } catch (_) {}
    }
  }

  Future<int> sendPacket(DistressPacket packet) async {
    _rememberPacket(packet, emitToStream: true);
    final bytes = _encodeDistressEnvelope(packet);

    var sent = 0;
    for (final endpointId in _connectedEndpoints) {
      try {
        await _nearby.sendBytesPayload(endpointId, bytes);
        sent += 1;
      } catch (e) {
        _log('Send failed to $endpointId: $e');
      }
    }

    _log('Distress ${packet.id} sent to $sent peer(s)');
    return sent;
  }

  Future<int> sendOrQueuePacket(DistressPacket packet) async {
    if (_connectedEndpoints.isNotEmpty) {
      _pendingPacket = null;
      return sendPacket(packet);
    }
    _pendingPacket = packet;
    _rememberPacket(packet, emitToStream: true);
    _log('No mesh peers yet. Queued ${packet.id} and waiting for app peers...');
    return 0;
  }

  void _onEndpointFound(String endpointId, String endpointName, String _) {
    if (!_isRunning) {
      return;
    }
    _endpointNames[endpointId] = endpointName;
    _emitStatus();
    _log('Discovered endpoint: $endpointName ($endpointId)');

    if (_shouldInitiateConnection(endpointId, endpointName)) {
      unawaited(_requestConnection(endpointId, endpointName));
    }
  }

  void _onEndpointLost(String? endpointId) {
    final safeId = (endpointId ?? '').trim();
    if (safeId.isEmpty) {
      return;
    }
    _endpointNames.remove(safeId);
    _connectedEndpoints.remove(safeId);
    _emitStatus();
    _log('Endpoint lost: $safeId');
  }

  bool _shouldInitiateConnection(String endpointId, String endpointName) {
    if (_connectedEndpoints.contains(endpointId)) {
      return false;
    }
    if (_deviceName == endpointName) {
      return _selfId.compareTo(endpointId) > 0;
    }
    return _deviceName.compareTo(endpointName) > 0;
  }

  Future<void> _requestConnection(String endpointId, String endpointName) async {
    try {
      await _nearby.requestConnection(
        _deviceName,
        endpointId,
        onConnectionInitiated: (id, info) {
          _log('Connection initiated to ${info.endpointName} ($id)');
          unawaited(_accept(id));
        },
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _log('Connection request failed to $endpointName: $e');
    }
  }

  Future<void> _accept(String endpointId) async {
    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (id, payload) {
          if (payload.type == PayloadType.BYTES && payload.bytes != null) {
            _handleIncomingBytes(id, payload.bytes!);
          }
        },
      );
    } catch (e) {
      _log('Accept failed for $endpointId: $e');
    }
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpoints.add(endpointId);
      _emitStatus();
      _log('Connected: $endpointId');
      unawaited(_sendHistoryToEndpoint(endpointId));
      final queued = _pendingPacket;
      if (queued != null) {
        _pendingPacket = null;
        unawaited(sendPacket(queued));
      }
      return;
    }

    if (status == Status.REJECTED || status == Status.ERROR) {
      _connectedEndpoints.remove(endpointId);
      _emitStatus();
      _log('Connection failed for $endpointId: $status');
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    _emitStatus();
    _log('Disconnected: $endpointId');
  }

  void _handleIncomingBytes(String fromEndpointId, Uint8List bytes) {
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (raw is! Map<String, dynamic>) {
        return;
      }

      final type = raw['type']?.toString();
      if (type == 'distress') {
        final packetMap = raw['packet'];
        if (packetMap is Map<String, dynamic>) {
          final packet = DistressPacket.tryFromMap(packetMap);
          if (packet != null) {
            _handleDistress(packet, sourceEndpointId: fromEndpointId);
          }
        }
        return;
      }

      if (type == 'distress_clear') {
        final sender = raw['sender']?.toString() ?? '';
        if (sender.isNotEmpty) {
          _resolveAlertBySender(sender, emitClear: true);
        }
        return;
      }

      final legacy = DistressPacket.tryFromMap(raw);
      if (legacy != null) {
        _handleDistress(legacy, sourceEndpointId: fromEndpointId);
      }
    } catch (e) {
      _log('Invalid payload from $fromEndpointId: $e');
    }
  }

  void _handleDistress(
    DistressPacket packet, {
    required String sourceEndpointId,
  }) {
    final inserted = _rememberPacket(packet, emitToStream: true);
    if (!inserted) {
      return;
    }
    _log('Received distress ${packet.id} from ${packet.sender}');
    unawaited(_relayDistress(packet, excludeEndpointId: sourceEndpointId));
  }

  Future<void> _relayDistress(
    DistressPacket packet, {
    required String excludeEndpointId,
  }) async {
    if (_connectedEndpoints.isEmpty) {
      return;
    }

    final bytes = _encodeDistressEnvelope(packet);

    var relayed = 0;
    for (final endpointId in _connectedEndpoints) {
      if (endpointId == excludeEndpointId) {
        continue;
      }
      try {
        await _nearby.sendBytesPayload(endpointId, bytes);
        relayed += 1;
      } catch (_) {}
    }
    if (relayed > 0) {
      _log('Relayed ${packet.id} to $relayed peer(s)');
    }
  }

  bool _rememberPacket(DistressPacket packet, {required bool emitToStream}) {
    final existing = _activePacketsBySender[packet.sender];
    if (existing != null) {
      final existingLat = existing.lat.toStringAsFixed(5);
      final existingLon = existing.lon.toStringAsFixed(5);
      final nextLat = packet.lat.toStringAsFixed(5);
      final nextLon = packet.lon.toStringAsFixed(5);
      if (existingLat == nextLat && existingLon == nextLon) {
        return false;
      }
    }

    _activePacketsBySender[packet.sender] = packet;
    _seenMessages.add(packet.id);

    if (_activePacketsBySender.length > _maxStoredPackets) {
      final oldestFirst = _activePacketsBySender.values.toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      final toDrop = oldestFirst.length - _maxStoredPackets;
      for (var i = 0; i < toDrop; i++) {
        final old = oldestFirst[i];
        _activePacketsBySender.remove(old.sender);
        _seenMessages.remove(old.id);
      }
    }

    if (emitToStream) {
      _packetController.add(packet);
    }
    return true;
  }

  Future<void> _resolveAlertBySender(String sender, {required bool emitClear}) async {
    final removed = _activePacketsBySender.remove(sender);
    if (removed == null) {
      return;
    }
    if (emitClear) {
      _clearController.add(sender);
    }
    _log('Cleared distress for $sender');
  }

  Uint8List _encodeDistressEnvelope(DistressPacket packet) {
    final envelope = <String, dynamic>{
      'type': 'distress',
      'packet': packet.toMap(),
      'from': _selfId,
      'name': _deviceName,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Uint8List _encodeClearEnvelope(String sender) {
    final envelope = <String, dynamic>{
      'type': 'distress_clear',
      'sender': sender,
      'from': _selfId,
      'name': _deviceName,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<void> _sendHistoryToEndpoint(String endpointId) async {
    if (_activePacketsBySender.isEmpty) {
      return;
    }

    final packets = _activePacketsBySender.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    var synced = 0;
    for (final packet in packets) {
      try {
        await _nearby.sendBytesPayload(endpointId, _encodeDistressEnvelope(packet));
        synced += 1;
      } catch (_) {}
    }
    if (synced > 0) {
      _log('Synced $synced stored distress packet(s) to $endpointId');
    }
  }

  void _emitStatus() {
    _statusController.add(
      MeshStatus(
        advertising: _advertising,
        discovering: _discovering,
        discoveredPeers: _endpointNames.length,
        connectedPeers: _connectedEndpoints.length,
      ),
    );
  }

  void _startMaintenanceLoop() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer.periodic(_maintenanceInterval, (_) {
      if (!_isRunning) {
        return;
      }
      for (final entry in _endpointNames.entries) {
        if (_connectedEndpoints.contains(entry.key)) {
          continue;
        }
        if (_shouldInitiateConnection(entry.key, entry.value)) {
          unawaited(_requestConnection(entry.key, entry.value));
        }
      }
    });
  }

  void _log(String message) {
    _logsController.add(message);
  }

  Future<void> dispose() async {
    await stop();
    await _logsController.close();
    await _statusController.close();
    await _packetController.close();
    await _clearController.close();
  }
}
