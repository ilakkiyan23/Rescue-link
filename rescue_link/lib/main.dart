import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:flutter/services.dart';
import 'package:rescue_link/services/bluetooth_service.dart';
import 'package:rescue_link/services/location_service.dart';
import 'package:rescue_link/services/nearby_distress_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.load();
  await FMTCObjectBoxBackend().initialise();
  try {
    await FMTCStore('rescue_map').manage.create();
  } catch (_) {}
  runApp(const RescueLinkApp());
}

const Color kBackgroundColor = Color(0xFF0D0D0D);
const Color kSurfaceColor = Color(0xFF1A1A1A);
const Color kPrimaryColor = Color(0xFFFF3B30);
const Color kSecondaryColor = Color(0xFF3A86FF);
const Color kSuccessColor = Color(0xFF2ECC71);
const Color kTextPrimaryColor = Color(0xFFFFFFFF);
const Color kTextSecondaryColor = Color(0xFFB0B0B0);

const MethodChannel _smsChannel = MethodChannel('rescue_link/direct_sms');

class EmergencyContact {
  const EmergencyContact({required this.name, required this.number});

  final String name;
  final String number;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'number': number,
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: (json['name'] as String? ?? '').trim(),
      number: (json['number'] as String? ?? '').trim(),
    );
  }
}

class DownloadedMapEntry {
  const DownloadedMapEntry({
    required this.label,
    required this.downloadedAtIso,
    required this.sizeKiB,
    required this.tileCount,
    this.centerLat,
    this.centerLon,
  });

  final String label;
  final String downloadedAtIso;
  final double sizeKiB;
  final int tileCount;
    final double? centerLat;
    final double? centerLon;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'downloadedAtIso': downloadedAtIso,
        'sizeKiB': sizeKiB,
        'tileCount': tileCount,
      'centerLat': centerLat,
      'centerLon': centerLon,
      };

  factory DownloadedMapEntry.fromJson(Map<String, dynamic> json) {
    return DownloadedMapEntry(
      label: (json['label'] as String? ?? 'Downloaded map').trim(),
      downloadedAtIso: (json['downloadedAtIso'] as String? ?? '').trim(),
      sizeKiB: (json['sizeKiB'] as num?)?.toDouble() ?? 0,
      tileCount: (json['tileCount'] as num?)?.toInt() ?? 0,
      centerLat: (json['centerLat'] as num?)?.toDouble(),
      centerLon: (json['centerLon'] as num?)?.toDouble(),
    );
  }
}

Future<bool> sendDirectSmsMessage({
  required String recipient,
  required String message,
}) async {
  if (!Platform.isAndroid) {
    return false;
  }
  final permission = await Permission.sms.status;
  if (!permission.isGranted) {
    return false;
  }
  try {
    final sent = await _smsChannel.invokeMethod<bool>(
      'sendDirectSms',
      <String, String>{
        'recipient': recipient,
        'message': message,
      },
    );
    return sent ?? false;
  } catch (_) {
    return false;
  }
}

class AppPreferences {
  AppPreferences._();

  static const String _deviceNameKey = 'device_name';
  static const String _emergencyContactNameKey = 'emergency_contact_name';
  static const String _emergencyContactNumberKey = 'emergency_contact_number';
  static const String _emergencyContactsKey = 'emergency_contacts_json';
  static const String _downloadedMapsKey = 'downloaded_maps_json';

  static final ValueNotifier<String> deviceName =
      ValueNotifier<String>('RescueLink User');
  static final ValueNotifier<String> emergencyContactName =
    ValueNotifier<String>('');
  static final ValueNotifier<String> emergencyContactNumber =
    ValueNotifier<String>('');
  static final ValueNotifier<List<EmergencyContact>> emergencyContacts =
      ValueNotifier<List<EmergencyContact>>(<EmergencyContact>[]);
  static final ValueNotifier<List<DownloadedMapEntry>> downloadedMaps =
      ValueNotifier<List<DownloadedMapEntry>>(<DownloadedMapEntry>[]);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    deviceName.value =
        (prefs.getString(_deviceNameKey) ?? 'RescueLink User').trim();
    emergencyContactName.value =
        (prefs.getString(_emergencyContactNameKey) ?? '').trim();
    emergencyContactNumber.value =
        (prefs.getString(_emergencyContactNumberKey) ?? '').trim();

    final storedContacts = prefs.getString(_emergencyContactsKey);
    final parsedContacts = <EmergencyContact>[];
    if (storedContacts != null && storedContacts.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedContacts);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final contact = EmergencyContact.fromJson(item);
              if (contact.name.isNotEmpty || contact.number.isNotEmpty) {
                parsedContacts.add(contact);
              }
            } else if (item is Map) {
              final contact = EmergencyContact.fromJson(
                item.cast<String, dynamic>(),
              );
              if (contact.name.isNotEmpty || contact.number.isNotEmpty) {
                parsedContacts.add(contact);
              }
            }
          }
        }
      } catch (_) {}
    }
    if (parsedContacts.isEmpty) {
      final legacyName = emergencyContactName.value.trim();
      final legacyNumber = emergencyContactNumber.value.trim();
      if (legacyName.isNotEmpty || legacyNumber.isNotEmpty) {
        parsedContacts.add(
          EmergencyContact(name: legacyName, number: legacyNumber),
        );
      }
    }
    emergencyContacts.value = parsedContacts;

    final storedMaps = prefs.getString(_downloadedMapsKey);
    final parsedMaps = <DownloadedMapEntry>[];
    if (storedMaps != null && storedMaps.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedMaps);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              parsedMaps.add(DownloadedMapEntry.fromJson(item));
            } else if (item is Map) {
              parsedMaps.add(
                DownloadedMapEntry.fromJson(item.cast<String, dynamic>()),
              );
            }
          }
        }
      } catch (_) {}
    }
    downloadedMaps.value = parsedMaps;
  }

  static Future<void> setDeviceName(String value) async {
    final cleaned = value.trim().isEmpty ? 'RescueLink User' : value.trim();
    deviceName.value = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceNameKey, cleaned);
  }

  static Future<void> setEmergencyContact({
    required String name,
    required String number,
  }) async {
    await setEmergencyContacts([
      EmergencyContact(name: name, number: number),
    ]);
  }

  static Future<void> setEmergencyContacts(
    List<EmergencyContact> contacts,
  ) async {
    final cleaned = contacts
        .map(
          (contact) => EmergencyContact(
            name: contact.name.trim(),
            number: contact.number.trim(),
          ),
        )
        .where((contact) => contact.name.isNotEmpty || contact.number.isNotEmpty)
        .toList(growable: false);
    emergencyContacts.value = cleaned;
    emergencyContactName.value = cleaned.isEmpty ? '' : cleaned.first.name;
    emergencyContactNumber.value = cleaned.isEmpty ? '' : cleaned.first.number;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _emergencyContactsKey,
      jsonEncode(cleaned.map((contact) => contact.toJson()).toList()),
    );
    await prefs.setString(_emergencyContactNameKey, emergencyContactName.value);
    await prefs.setString(
      _emergencyContactNumberKey,
      emergencyContactNumber.value,
    );
  }

  static Future<void> addEmergencyContact(EmergencyContact contact) async {
    final updated = List<EmergencyContact>.from(emergencyContacts.value)
      ..add(contact);
    await setEmergencyContacts(updated);
  }

  static Future<void> updateEmergencyContact(
    int index,
    EmergencyContact contact,
  ) async {
    final updated = List<EmergencyContact>.from(emergencyContacts.value);
    if (index < 0 || index >= updated.length) {
      return;
    }
    updated[index] = contact;
    await setEmergencyContacts(updated);
  }

  static Future<void> removeEmergencyContactAt(int index) async {
    final updated = List<EmergencyContact>.from(emergencyContacts.value);
    if (index < 0 || index >= updated.length) {
      return;
    }
    updated.removeAt(index);
    await setEmergencyContacts(updated);
  }

  static Future<void> addDownloadedMap(DownloadedMapEntry entry) async {
    final updated = List<DownloadedMapEntry>.from(downloadedMaps.value)
      ..insert(0, entry);
    downloadedMaps.value = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _downloadedMapsKey,
      jsonEncode(updated.map((mapEntry) => mapEntry.toJson()).toList()),
    );
  }

  static Future<void> setDownloadedMaps(List<DownloadedMapEntry> maps) async {
    downloadedMaps.value = List<DownloadedMapEntry>.unmodifiable(maps);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _downloadedMapsKey,
      jsonEncode(maps.map((entry) => entry.toJson()).toList()),
    );
  }

  static String meshDeviceName(String context) {
    final base = deviceName.value.trim().replaceAll(RegExp(r'\s+'), '-');
    final cleanedBase = base.isEmpty ? 'RescueLink-User' : base;
    return '$cleanedBase-$context';
  }
}

class AppSignals {
  AppSignals._();

  static final ValueNotifier<DistressPacket?> focusedPacket =
      ValueNotifier<DistressPacket?>(null);
  static final ValueNotifier<int?> targetTab = ValueNotifier<int?>(null);
  static final ValueNotifier<latlng.LatLng?> focusedMapCenter =
      ValueNotifier<latlng.LatLng?>(null);
}

class RescueLinkApp extends StatelessWidget {
  const RescueLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rescue Link',
      theme: ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.android,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBackgroundColor,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: kTextPrimaryColor,
          displayColor: kTextPrimaryColor,
        ),
        colorScheme: const ColorScheme.dark(
          primary: kPrimaryColor,
          secondary: kSecondaryColor,
          surface: kSurfaceColor,
          onPrimary: kTextPrimaryColor,
          onSecondary: kTextPrimaryColor,
          onSurface: kTextPrimaryColor,
        ),
        cardColor: kSurfaceColor,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: kSurfaceColor,
          selectedItemColor: kPrimaryColor,
          unselectedItemColor: kTextSecondaryColor,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kSurfaceColor,
          foregroundColor: kTextPrimaryColor,
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  OverlayEntry? _overlayEntry;
  late final NearbyDistressService _meshService;
  StreamSubscription<DistressPacket>? _packetSub;
  StreamSubscription<String>? _clearSub;
  final Set<String> _seenOverlayPacketIds = <String>{};
  String? _currentOverlaySender;

  @override
  void initState() {
    super.initState();
    _meshService = NearbyDistressService.instance;
    _packetSub = _meshService.packetStream.listen(_onGlobalPacket);
    _clearSub = _meshService.clearStream.listen(_onClearPacket);
    AppSignals.targetTab.addListener(_onTargetTabRequested);
    unawaited(_prepareDeviceOnStartup());
  }

  void _onTargetTabRequested() {
    final tab = AppSignals.targetTab.value;
    if (tab == null || !mounted) {
      return;
    }
    setState(() => _currentIndex = tab);
    AppSignals.targetTab.value = null;
  }

  void _showGlobalSignalOverlay(String locationText) {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _GlobalSignalOverlay(
          sender: _currentOverlaySender ?? 'Nearby alert',
          locationText: locationText,
          onDismiss: () {
            _overlayEntry?.remove();
            _overlayEntry = null;
            _currentOverlaySender = null;
          },
          onView: () {
            setState(() => _currentIndex = 1);
            _overlayEntry?.remove();
            _overlayEntry = null;
            _currentOverlaySender = null;
          },
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onGlobalPacket(DistressPacket packet) {
    if (!mounted) {
      return;
    }
    if (packet.sender == AppPreferences.deviceName.value) {
      return;
    }
    if (!_seenOverlayPacketIds.add(packet.id)) {
      return;
    }
    _currentOverlaySender = packet.sender;
    final locationText =
        '${packet.lat.toStringAsFixed(5)}, ${packet.lon.toStringAsFixed(5)}';
    _showGlobalSignalOverlay(locationText);
  }

  void _onClearPacket(String sender) {
    if (!mounted) {
      return;
    }
    if (_currentOverlaySender == sender) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _currentOverlaySender = null;
    }
  }

  Future<void> _prepareDeviceOnStartup() async {
    await _meshService.requestPermissions();
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final locationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!locationEnabled) {
      await Geolocator.openLocationSettings();
    }
    if (Platform.isAndroid) {
      await RescueBleService.requestAndroidBlePermissions();
    }
    await _meshService.ensureRunning(
      deviceName: AppPreferences.meshDeviceName('main'),
    );
  }

  @override
  void dispose() {
    AppSignals.targetTab.removeListener(_onTargetTabRequested);
    _packetSub?.cancel();
    _clearSub?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const MapScreen(),
      const ActivityScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isActive = false;
  bool _locationLoading = true;
  String _locationLabel = 'Fetching location...';
  String _bluetoothLabel = 'Nearby help: preparing...';
  int _meshDiscovered = 0;
  int _meshPeers = 0;
  StreamSubscription<BluetoothAdapterState>? _btAdapterSub;
  StreamSubscription<MeshStatus>? _meshStatusSub;
  late final AnimationController _pulseController;
  late final AnimationController _holdProgressController;
  late final AnimationController _rippleController;
  final NearbyDistressService _meshService = NearbyDistressService.instance;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 1.0,
      upperBound: 1.05,
    );
    _holdProgressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _refreshLocation();
    _initBluetooth();
  }

  @override
  void dispose() {
    _btAdapterSub?.cancel();
    _meshStatusSub?.cancel();
    unawaited(_meshService.stop());
    _pulseController.dispose();
    _holdProgressController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  void _toggleSos() {
    setState(() => _isActive = !_isActive);
    if (_isActive) {
      _pulseController.repeat(reverse: true);
      _rippleController.repeat();
      _refreshLocation();
      unawaited(_activateSosMeshFlow());
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
      _rippleController.stop();
      _rippleController.value = 0;
      _holdProgressController.value = 0;
      unawaited(_stopBleAfterSos());
    }
  }

  Future<void> _activateSosMeshFlow() async {
    await _activateBleForSos();
    if (!mounted || !_isActive) {
      return;
    }

    final meshGranted = await _meshService.requestPermissions();
    if (!mounted || !_isActive) {
      return;
    }

    if (!meshGranted) {
      setState(() {
        _bluetoothLabel = 'Nearby help: allow required permissions';
      });
      return;
    }

    final started = await _meshService.ensureRunning(
      deviceName: AppPreferences.meshDeviceName('sos'),
    );
    if (!mounted || !_isActive) {
      return;
    }

    if (!started) {
      setState(() {
        _bluetoothLabel = 'Nearby help: could not start';
      });
      return;
    }

    await _broadcastDistress();
  }

  Future<void> _broadcastDistress() async {
    final position = await LocationService.getCurrentPosition();
    if (!mounted || !_isActive || position == null) {
      return;
    }

    final locationText =
        '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';

    final packet = DistressPacket.build(
      lat: position.latitude,
      lon: position.longitude,
      sender: AppPreferences.deviceName.value,
    );
    final smsSent = await _sendEmergencySms(locationText);
    final sent = await _meshService.sendOrQueuePacket(packet);
    if (!mounted || !_isActive) {
      return;
    }
    setState(() {
      final smsNote = smsSent ? '' : ' Direct SMS is off in Settings.';
      if (sent == 0) {
        _bluetoothLabel = 'Alert saved. Waiting for nearby users.$smsNote';
      } else {
        _bluetoothLabel =
            'Alert shared with $sent nearby user${sent == 1 ? '' : 's'}.$smsNote';
      }
    });
  }

  Future<bool> _sendEmergencySms(String locationText) async {
    final contacts = AppPreferences.emergencyContacts.value;
    if (contacts.isEmpty) {
      return false;
    }

    final senderName = AppPreferences.deviceName.value.trim();
    var sent = false;
    for (final contact in contacts) {
      final targetLine = contact.name.isEmpty
          ? contact.number
          : '${contact.name} (${contact.number})';
      final message =
          'Emergency alert from $senderName to $targetLine. Current location: $locationText';
      final delivered = await sendDirectSmsMessage(
        recipient: contact.number,
        message: message,
      );
      sent = sent || delivered;
    }
    return sent;
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _locationLoading = true;
      _locationLabel = 'Fetching location...';
    });

    final Position? position = await LocationService.getCurrentPosition();
    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() {
        _locationLoading = false;
        _locationLabel = 'Location unavailable';
      });
      return;
    }

    setState(() {
      _locationLoading = false;
      _locationLabel =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    });
  }

  Future<void> _initBluetooth() async {
    final supported = await RescueBleService.isSupported();
    if (!mounted) {
      return;
    }
    if (!supported) {
      setState(() => _bluetoothLabel = 'Bluetooth: Not supported');
      return;
    }

    _btAdapterSub =
        RescueBleService.adapterStateStream().listen(_onBluetoothAdapter);
    _meshStatusSub = _meshService.statusStream.listen((status) {
      if (!mounted) {
        return;
      }
      setState(() {
        _meshDiscovered = status.discoveredPeers;
        _meshPeers = status.connectedPeers;
        if (_isActive && status.running) {
          _bluetoothLabel =
              'Nearby help: $_meshPeers connected, $_meshDiscovered nearby';
        }
      });
    });
    await _applyBluetoothAdapter(RescueBleService.adapterStateNow());
  }

  Future<void> _onBluetoothAdapter(BluetoothAdapterState state) async {
    if (!mounted) {
      return;
    }
    await _applyBluetoothAdapter(state);
  }

  Future<void> _activateBleForSos() async {
    if (!await RescueBleService.isSupported()) {
      return;
    }
    if (!mounted || !_isActive) {
      return;
    }

    if (Platform.isAndroid) {
      final granted = await RescueBleService.requestAndroidBlePermissions();
      if (!mounted || !_isActive) {
        return;
      }
      if (!granted) {
        if (mounted) {
          setState(
            () => _bluetoothLabel =
                'Nearby help: allow nearby devices',
          );
        }
        return;
      }
    }

    if (RescueBleService.adapterStateNow() != BluetoothAdapterState.on) {
      if (mounted) {
        setState(() => _bluetoothLabel = 'Nearby help: turning on...');
      }
      if (Platform.isAndroid) {
        try {
          await RescueBleService.requestAdapterOnForEmergency();
        } catch (_) {
          if (mounted) {
            setState(() => _bluetoothLabel = 'Nearby help: bluetooth enable canceled');
          }
          return;
        }
      }
    }

    if (!mounted || !_isActive) {
      return;
    }

    if (RescueBleService.adapterStateNow() != BluetoothAdapterState.on) {
      if (mounted) {
        setState(
          () => _bluetoothLabel = Platform.isIOS
              ? 'Nearby help: turn on Bluetooth in Control Center'
              : 'Nearby help: Bluetooth is still off. Try SOS again.',
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _bluetoothLabel = _formatBluetoothLine(
            BluetoothAdapterState.on,
          ));
    }
  }

  Future<void> _stopBleAfterSos() async {
    await _meshService.resolveOwnAlert();
    await _meshService.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _meshDiscovered = 0;
      _meshPeers = 0;
      _bluetoothLabel = _formatBluetoothLine(RescueBleService.adapterStateNow());
    });
  }

  Future<void> _applyBluetoothAdapter(BluetoothAdapterState state) async {
    switch (state) {
      case BluetoothAdapterState.on:
        if (mounted) {
          setState(() {
            if (!_isActive) {
              _meshDiscovered = 0;
              _meshPeers = 0;
            }
            _bluetoothLabel = _formatBluetoothLine(BluetoothAdapterState.on);
          });
        }
      case BluetoothAdapterState.off:
        if (mounted) {
          setState(() {
            _meshDiscovered = 0;
            _meshPeers = 0;
            _bluetoothLabel = 'Nearby help: off';
          });
        }
      case BluetoothAdapterState.turningOn:
      case BluetoothAdapterState.turningOff:
        if (mounted) {
          setState(() => _bluetoothLabel = 'Nearby help: ${state.name}');
        }
      case BluetoothAdapterState.unauthorized:
        if (mounted) {
          setState(() => _bluetoothLabel = 'Nearby help: permission needed');
        }
      case BluetoothAdapterState.unavailable:
        if (mounted) {
          setState(() => _bluetoothLabel = 'Nearby help: unavailable');
        }
      case BluetoothAdapterState.unknown:
        if (mounted) {
          setState(() => _bluetoothLabel = 'Nearby help: preparing...');
        }
    }
  }

  String _formatBluetoothLine(BluetoothAdapterState state) {
    if (state != BluetoothAdapterState.on) {
      return 'Nearby help: off';
    }
    if (!_isActive) {
      return 'Nearby help is ready. Hold SOS to send alert.';
    }
    if (_meshDiscovered == 0) {
      return 'Searching for nearby users...';
    }
    if (_meshPeers == 0) {
      return '$_meshDiscovered users found, connecting...';
    }
    return 'Connected to $_meshPeers users ($_meshDiscovered nearby)';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Emergency Help',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _isActive ? 'Alert is ON' : 'Ready to send alert',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: Center(
                child: SOSButton(
                  isActive: _isActive,
                  pulseAnimation: _pulseController,
                  rippleAnimation: _rippleController,
                  holdProgressAnimation: _holdProgressController,
                  onLongPressStart: (_) {
                    _holdProgressController.forward(from: 0);
                  },
                  onLongPressEnd: (_) {
                    if (!_isActive) {
                      _holdProgressController.reset();
                    }
                  },
                  onLongPress: _toggleSos,
                ),
              ),
            ),
            const SizedBox(height: 18),
            StatusCard(
              isActive: _isActive,
              locationLabel: _locationLabel,
              isLocationLoading: _locationLoading,
              onRefreshLocation: _refreshLocation,
              bluetoothLabel: _bluetoothLabel,
              onTurnOffAlert: _isActive ? _toggleSos : null,
            ),
          ],
        ),
      ),
    );
  }
}

class SOSButton extends StatelessWidget {
  const SOSButton({
    super.key,
    required this.isActive,
    required this.pulseAnimation,
    required this.rippleAnimation,
    required this.holdProgressAnimation,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onLongPress,
  });

  final bool isActive;
  final Animation<double> pulseAnimation;
  final Animation<double> rippleAnimation;
  final Animation<double> holdProgressAnimation;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressEndCallback onLongPressEnd;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      onLongPress: onLongPress,
      child: ScaleTransition(
        scale: pulseAnimation,
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([rippleAnimation, holdProgressAnimation]),
                builder: (context, child) {
                  final waveProgress = isActive
                      ? rippleAnimation.value
                      : holdProgressAnimation.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final offset in const [0.0, 0.33, 0.66])
                        _RippleWave(
                          progress: isActive
                              ? (waveProgress + offset) % 1.0
                              : (waveProgress * 0.7) + offset,
                          visible: isActive || holdProgressAnimation.value > 0,
                        ),
                    ],
                  );
                },
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFF5A52), kPrimaryColor],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: isActive ? 0.85 : 0.45),
                      blurRadius: isActive ? 32 : 24,
                      spreadRadius: isActive ? 4 : 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isActive ? 'ACTIVE' : 'SOS',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: kTextPrimaryColor,
                            ),
                      ),
                      const SizedBox(height: 6),
                          const Text(
                            'Hold to send',
                            style: TextStyle(
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RippleWave extends StatelessWidget {
  const _RippleWave({
    required this.progress,
    required this.visible,
  });

  final double progress;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    final normalized = progress.clamp(0.0, 1.0);
    final scale = 0.72 + (normalized * 0.75);
    final opacity = (1.0 - normalized).clamp(0.0, 1.0) * 0.5;

    return IgnorePointer(
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 174,
          height: 174,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: kSecondaryColor.withValues(alpha: opacity),
              width: 2.2,
            ),
          ),
        ),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.isActive,
    required this.locationLabel,
    required this.isLocationLoading,
    required this.onRefreshLocation,
    required this.bluetoothLabel,
    required this.onTurnOffAlert,
  });

  final bool isActive;
  final String locationLabel;
  final bool isLocationLoading;
  final VoidCallback onRefreshLocation;
  final String bluetoothLabel;
  final VoidCallback? onTurnOffAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusRow(
            icon: Icons.location_on,
            iconColor: kSecondaryColor,
            label: 'Location: $locationLabel',
            trailing: IconButton(
              tooltip: 'Refresh location',
              onPressed: isLocationLoading ? null : onRefreshLocation,
              icon: isLocationLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          _StatusRow(
            icon: Icons.wifi_rounded,
            iconColor: Colors.blueAccent,
            label: bluetoothLabel,
          ),
          if (isActive) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onTurnOffAlert,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Turn Off Alert'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static final latlng.LatLng _defaultCenter = latlng.LatLng(11.0168, 76.9558);
  static const String _mapStoreName = 'rescue_map';

  final MapController _mapController = MapController();
  latlng.LatLng? _currentLocation;
  final NearbyDistressService _meshService = NearbyDistressService.instance;
  final Map<String, DistressPacket> _distressBySender =
      <String, DistressPacket>{};
  StreamSubscription<DistressPacket>? _packetSub;
  StreamSubscription<String>? _clearSub;
  late final FMTCTileProvider _tileProvider;
  bool _downloadInProgress = false;
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _tileProvider = FMTCTileProvider(
      stores: const {_mapStoreName: BrowseStoreStrategy.readUpdateCreate},
      loadingStrategy: BrowseLoadingStrategy.cacheOnly,
    );
    _seedDistressHistory();
    _packetSub = _meshService.packetStream.listen(_onDistressPacket);
    _clearSub = _meshService.clearStream.listen(_onClearPacket);
    AppSignals.focusedPacket.addListener(_onFocusPacket);
    AppSignals.focusedMapCenter.addListener(_onFocusMapCenter);
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    AppSignals.focusedPacket.removeListener(_onFocusPacket);
    AppSignals.focusedMapCenter.removeListener(_onFocusMapCenter);
    _packetSub?.cancel();
    _clearSub?.cancel();
    unawaited(_tileProvider.dispose());
    super.dispose();
  }

  void _onFocusPacket() {
    final packet = AppSignals.focusedPacket.value;
    if (packet == null || !mounted) {
      return;
    }
    _mapController.move(latlng.LatLng(packet.lat, packet.lon), 16);
    _showSignalSheet(context, packet);
    AppSignals.focusedPacket.value = null;
  }

  void _onFocusMapCenter() {
    final center = AppSignals.focusedMapCenter.value;
    if (center == null || !mounted) {
      return;
    }
    _mapController.move(center, 14);
    AppSignals.focusedMapCenter.value = null;
  }

  void _seedDistressHistory() {
    final packets = _meshService.storedPackets;
    for (final packet in packets) {
      _distressBySender[packet.sender] = packet;
    }
  }

  void _onDistressPacket(DistressPacket packet) {
    if (!mounted) {
      return;
    }
    setState(() {
      _distressBySender[packet.sender] = packet;
    });
  }

  void _onClearPacket(String sender) {
    if (!mounted) {
      return;
    }
    setState(() {
      _distressBySender.remove(sender);
    });
  }

  Future<void> _startReceiverMode() async {
    final granted = await _meshService.requestPermissions();
    if (!granted) {
      return;
    }

    await _meshService.ensureRunning(
      deviceName: AppPreferences.meshDeviceName('map'),
    );
  }

  Future<void> _loadCurrentLocation() async {
    setState(() => _loadingLocation = true);
    final position = await LocationService.getCurrentPosition();
    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => _loadingLocation = false);
      return;
    }

    final current = latlng.LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = current;
      _loadingLocation = false;
    });
    _mapController.move(current, 16);
  }

  String _formatTime(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final hh = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $suffix';
  }

  String _distanceFromSelfText(DistressPacket packet) {
    if (_currentLocation == null) {
      return 'Distance unavailable';
    }
    final meters = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      packet.lat,
      packet.lon,
    );
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m away';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km away';
  }

  void _markResponding(DistressPacket packet) {
    final distance = _distanceFromSelfText(packet);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Responding to alert (${packet.sender}) • $distance')),
    );
  }

  void _showSignalSheet(BuildContext context, DistressPacket packet) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location: ${packet.lat.toStringAsFixed(5)}, ${packet.lon.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Time: ${_formatTime(packet.time)}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Sender: ${packet.sender}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                _distanceFromSelfText(packet),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: kTextPrimaryColor,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _mapController.move(latlng.LatLng(packet.lat, packet.lon), 16);
                      },
                      child: const Text('Center'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: kTextPrimaryColor,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _markResponding(packet);
                      },
                      child: const Text('Respond'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  TileLayer _buildTileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.rescue_link',
      tileProvider: _tileProvider,
    );
  }

  Future<void> _downloadVisibleArea() async {
    if (_downloadInProgress) {
      return;
    }
    final center = _currentLocation ?? _defaultCenter;
    setState(() => _downloadInProgress = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading map area for offline use...')),
    );
    try {
      final region = CircleRegion(center, 2.5).toDownloadable(
        minZoom: 10,
        maxZoom: 17,
        options: _buildTileLayer(),
      );
      final downloadSession = FMTCStore(_mapStoreName).download.startForeground(
        region: region,
      );
      await downloadSession.downloadProgress.last;
      final stats = await FMTCStore(_mapStoreName).stats.all;
      final mapLabel = _currentLocation == null
          ? 'Offline map area'
          : 'Offline map area (${center.latitude.toStringAsFixed(3)}, ${center.longitude.toStringAsFixed(3)})';
      await AppPreferences.addDownloadedMap(
        DownloadedMapEntry(
          label: mapLabel,
          downloadedAtIso: DateTime.now().toIso8601String(),
          sizeKiB: stats.size,
          tileCount: stats.length,
          centerLat: center.latitude,
          centerLon: center.longitude,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map area downloaded for offline use')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offline map download failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _downloadInProgress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentLocation ?? _defaultCenter;
    final markers = <Marker>[
      Marker(
        point: current,
        width: 44,
        height: 44,
        child: const Icon(Icons.my_location_rounded, color: kSecondaryColor),
      ),
    ];

    for (final packet in _distressBySender.values.take(40)) {
      markers.add(
        Marker(
          point: latlng.LatLng(packet.lat, packet.lon),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showSignalSheet(context, packet),
            child: const Icon(Icons.warning_rounded, color: kPrimaryColor),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: current, initialZoom: 15),
            children: [
              _buildTileLayer(),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'download_map',
                  onPressed: _downloadInProgress ? null : _downloadVisibleArea,
                  child: _downloadInProgress
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'center_map',
                  onPressed: _loadCurrentLocation,
                  child: const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),
          if (_loadingLocation)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final StreamSubscription<DistressPacket> _packetSub;
  late final StreamSubscription<String> _clearSub;
  final NearbyDistressService _meshService = NearbyDistressService.instance;
  final Map<String, DistressPacket> _eventsBySender = <String, DistressPacket>{};
  late final List<DistressPacket> _events;

  @override
  void initState() {
    super.initState();
    _seedEventsFromHistory();
    _events = _sortedEvents();
    _packetSub = _meshService.packetStream.listen((packet) {
      if (!mounted) {
        return;
      }
      setState(() {
        _applyPacket(packet);
      });
    });
    _clearSub = _meshService.clearStream.listen((sender) {
      if (!mounted) {
        return;
      }
      setState(() {
        _eventsBySender.remove(sender);
        _events
          ..clear()
          ..addAll(_sortedEvents());
      });
    });
  }

  void _seedEventsFromHistory() {
    for (final packet in _meshService.storedPackets) {
      _eventsBySender[packet.sender] = packet;
    }
  }

  List<DistressPacket> _sortedEvents() {
    final list = _eventsBySender.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  bool _sameLocation(DistressPacket a, DistressPacket b) {
    return a.lat.toStringAsFixed(5) == b.lat.toStringAsFixed(5) &&
        a.lon.toStringAsFixed(5) == b.lon.toStringAsFixed(5);
  }

  void _applyPacket(DistressPacket packet) {
    final existing = _eventsBySender[packet.sender];
    if (existing != null && _sameLocation(existing, packet)) {
      return;
    }
    _eventsBySender[packet.sender] = packet;
    _events
      ..clear()
      ..addAll(_sortedEvents());
  }

  @override
  void dispose() {
    _packetSub.cancel();
    _clearSub.cancel();
    super.dispose();
  }

  String _formatTime(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final hh = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $suffix';
  }

  void _focusOnMap(DistressPacket packet) {
    AppSignals.focusedPacket.value = packet;
    AppSignals.targetTab.value = 1;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening map and focusing alert...')),
    );
  }

  void _showEventDetails(DistressPacket packet) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Distress Alert', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Location: ${packet.lat.toStringAsFixed(5)}, ${packet.lon.toStringAsFixed(5)}'),
              Text('Device: ${_displayDeviceName(packet.sender)}'),
              Text('Time: ${_formatTime(packet.time)}'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _focusOnMap(packet);
                  },
                  child: const Text('Open In Map'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _displayDeviceName(String sender) {
    final cleaned = sender.trim();
    if (cleaned.startsWith('node_')) {
      return 'Unknown device';
    }
    return cleaned;
  }

  Widget _buildTimelineItem(DistressPacket packet, int index) {
    final isLast = index == _events.length - 1;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: kPrimaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.white12),
                  ),
              ],
            ),
          ),
          Expanded(
            child: EventCard(
              location: '${packet.lat.toStringAsFixed(5)}, ${packet.lon.toStringAsFixed(5)}',
              time: _formatTime(packet.time),
              delivery: 'Nearby network',
              sender: _displayDeviceName(packet.sender),
              onView: () => _showEventDetails(packet),
              onRespond: () => _focusOnMap(packet),
              isNew: index == 0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _events.isEmpty
                  ? const Center(
                      child: Text('No live distress packets yet.'),
                    )
                  : ListView.builder(
                      itemCount: _events.length,
                      itemBuilder: (context, index) {
                        final packet = _events[index];
                        return _buildTimelineItem(packet, index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.location,
    required this.time,
    required this.delivery,
    required this.sender,
    required this.onView,
    required this.onRespond,
    required this.isNew,
  });

  final String location;
  final String time;
  final String delivery;
  final String sender;
  final VoidCallback onView;
  final VoidCallback onRespond;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNew ? const Color(0xFF221A1A) : kSurfaceColor,
        border: Border.all(color: isNew ? kPrimaryColor.withValues(alpha: 0.25) : Colors.white10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'DISTRESS SIGNAL',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const Spacer(),
              Text(
                delivery,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: kTextSecondaryColor,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            location,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '$sender • $time',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: kTextSecondaryColor,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    foregroundColor: kTextPrimaryColor,
                  ),
                  onPressed: onView,
                  child: const Text('View'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: kTextPrimaryColor,
                  ),
                  onPressed: onRespond,
                  child: const Text('Respond'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _contactNameController;
  late final TextEditingController _contactNumberController;
  bool _smsPermissionGranted = false;
  bool _smsPermissionLoading = true;
  LocationPermission _locationPermission = LocationPermission.unableToDetermine;
  bool _locationServiceEnabled = false;
  final ScrollController _scrollController = ScrollController();
  int? _editingContactIndex;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: AppPreferences.deviceName.value);
    _contactNameController = TextEditingController();
    _contactNumberController = TextEditingController();
    unawaited(_refreshSmsPermissionStatus());
    unawaited(_refreshLocationPermissionStatus());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactNameController.dispose();
    _contactNumberController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _bluetoothSettingsSubtitle(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return 'On';
      case BluetoothAdapterState.off:
        return 'Off';
      case BluetoothAdapterState.turningOn:
      case BluetoothAdapterState.turningOff:
        return 'Please wait…';
      case BluetoothAdapterState.unauthorized:
        return 'Permission needed';
      case BluetoothAdapterState.unavailable:
        return 'Unavailable';
      case BluetoothAdapterState.unknown:
        return 'Checking…';
    }
  }

  Future<void> _refreshSmsPermissionStatus() async {
    final status = await Permission.sms.status;
    if (!mounted) {
      return;
    }
    setState(() {
      _smsPermissionGranted = status.isGranted;
      _smsPermissionLoading = false;
    });
  }

  Future<void> _refreshLocationPermissionStatus() async {
    final permission = await Geolocator.checkPermission();
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _locationPermission = permission;
      _locationServiceEnabled = enabled;
    });
  }

  Future<void> _promptLocationPermission() async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Allow location access'),
          content: const Text(
            'Rescue Link needs location to attach your live coordinates to SOS alerts.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
    if (allow != true) {
      return;
    }

    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await Geolocator.openLocationSettings();
    }
    await _refreshLocationPermissionStatus();
  }

  Future<void> _requestSmsPermission() async {
    if (!Platform.isAndroid) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Direct SMS is only available on Android.')),
      );
      return;
    }
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Allow direct SMS permission'),
          content: const Text(
            'Rescue Link sends SOS alerts by SMS directly from the app. Allow SMS permission?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
    if (allow != true) {
      return;
    }

    final status = await Permission.sms.request();
    if (!mounted) {
      return;
    }
    setState(() {
      _smsPermissionGranted = status.isGranted;
      _smsPermissionLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status.isGranted
              ? 'Direct SMS enabled. SOS will send without opening the SMS app.'
              : 'Direct SMS permission not granted.',
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final cleaned = _nameController.text.trim();
    if (cleaned.isEmpty || cleaned.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid display name')),
      );
      return;
    }
    await AppPreferences.setDeviceName(cleaned);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved profile name')),
    );
  }

  Future<void> _saveContact() async {
    final name = _contactNameController.text.trim();
    final number = _contactNumberController.text.trim();
    final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter contact name')),
      );
      return;
    }
    if (digits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }

    final isEditing = _editingContactIndex != null;
    final editingIndex = _editingContactIndex;
    final contact = EmergencyContact(
      name: name,
      number: number,
    );
    if (editingIndex == null) {
      await AppPreferences.addEmergencyContact(contact);
    } else {
      await AppPreferences.updateEmergencyContact(editingIndex, contact);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _editingContactIndex = null;
      _contactNameController.clear();
      _contactNumberController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEditing ? 'Updated emergency contact' : 'Saved emergency contact',
        ),
      ),
    );
  }

  void _editContact(int index, EmergencyContact contact) {
    setState(() {
      _editingContactIndex = index;
      _contactNameController.text = contact.name;
      _contactNumberController.text = contact.number;
    });
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _deleteContact(int index) async {
    await AppPreferences.removeEmergencyContactAt(index);
    if (!mounted) {
      return;
    }
    if (_editingContactIndex == index) {
      setState(() {
        _editingContactIndex = null;
        _contactNameController.clear();
        _contactNumberController.clear();
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted emergency contact')),
    );
  }

  String _formatBytes(double sizeKiB) {
    if (sizeKiB < 1024) {
      return '${sizeKiB.toStringAsFixed(1)} KiB';
    }
    final sizeMiB = sizeKiB / 1024;
    return '${sizeMiB.toStringAsFixed(1)} MiB';
  }

  String _formatDownloadedAt(String iso) {
    if (iso.isEmpty) {
      return 'Recently';
    }
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final suffix = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    } catch (_) {
      return 'Recently';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: (notification) {
          notification.disallowIndicator();
          return true;
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF242424), Color(0xFF141414)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.tune_rounded, color: kPrimaryColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Safety and permissions',
            child: Column(
              children: [
                StreamBuilder<BluetoothAdapterState>(
                  stream: RescueBleService.adapterStateStream(),
                  initialData: RescueBleService.adapterStateNow(),
                  builder: (context, snapshot) {
                    final state =
                        snapshot.data ?? BluetoothAdapterState.unknown;
                    final isOn = state == BluetoothAdapterState.on;
                    final busy = state == BluetoothAdapterState.turningOn ||
                        state == BluetoothAdapterState.turningOff;
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bluetooth'),
                      subtitle: Text(_bluetoothSettingsSubtitle(state)),
                      value: isOn,
                      onChanged: busy
                          ? null
                          : (wantOn) async {
                              if (wantOn) {
                                if (Platform.isAndroid) {
                                  await RescueBleService
                                      .requestAndroidBlePermissions();
                                }
                                try {
                                  await FlutterBluePlus.turnOn();
                                } catch (_) {}
                              } else {
                                try {
                                  // ignore: deprecated_member_use
                                  await FlutterBluePlus.turnOff();
                                } catch (_) {}
                              }
                            },
                    );
                  },
                ),
                const SizedBox(height: 4),
                FutureBuilder<bool>(
                  future: Future.value(true),
                  builder: (context, snapshot) {
                    final granted = _locationPermission == LocationPermission.whileInUse ||
                        _locationPermission == LocationPermission.always;
                    final subtitle = granted && _locationServiceEnabled
                        ? 'Granted'
                        : 'Needs permission';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Location'),
                      subtitle: Text(subtitle),
                      trailing: TextButton(
                        onPressed: _promptLocationPermission,
                        child: const Text('Allow'),
                      ),
                    );
                  },
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Direct SMS'),
                  subtitle: Text(
                    _smsPermissionLoading
                    ? 'Checking...'
                        : _smsPermissionGranted
                      ? 'Enabled'
                      : 'Needs permission',
                  ),
                  trailing: _smsPermissionGranted
                      ? const Icon(Icons.verified_rounded, color: kSuccessColor)
                      : TextButton(
                          onPressed: _requestSmsPermission,
                          child: const Text('Enable'),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Emergency contacts',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_outline),
                            labelText: 'Display Name',
                            hintText: 'Ex: Ilakkiyan',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _editingContactIndex == null
                                    ? 'Add emergency contact'
                                    : 'Edit emergency contact',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (_editingContactIndex != null)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _editingContactIndex = null;
                                    _contactNameController.clear();
                                    _contactNumberController.clear();
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                          ],
                        ),
                        TextFormField(
                          controller: _contactNameController,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.contact_page_outlined),
                            labelText: 'Contact Name',
                            hintText: 'Ex: Father / Asha / Manager',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _contactNumberController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 16),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
                          ],
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.phone_outlined),
                            labelText: 'Contact Number',
                            hintText: 'Ex: +919876543210',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kSecondaryColor,
                              foregroundColor: kTextPrimaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _saveContact,
                            child: Text(
                              _editingContactIndex == null ? 'Add Contact' : 'Update Contact',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<List<EmergencyContact>>(
                    valueListenable: AppPreferences.emergencyContacts,
                    builder: (context, contacts, _) {
                      if (contacts.isEmpty) {
                        return Text(
                          'No saved contacts yet.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: kTextSecondaryColor,
                              ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saved contacts',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 10),
                          ...contacts.asMap().entries.map((entry) {
                            final index = entry.key;
                            final contact = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: kBackgroundColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: kPrimaryColor.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.person_pin_circle_outlined, color: kPrimaryColor, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          contact.name,
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          contact.number,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: kTextSecondaryColor,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit contact',
                                    onPressed: () => _editContact(index, contact),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete contact',
                                    onPressed: () => _deleteContact(index),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Downloaded maps',
            child: ValueListenableBuilder<List<DownloadedMapEntry>>(
              valueListenable: AppPreferences.downloadedMaps,
              builder: (context, maps, _) {
                if (maps.isEmpty) {
                  return Text(
                    'No map downloads yet. Use the Map tab to save an area for offline use.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: kTextSecondaryColor,
                        ),
                  );
                }
                final totalSizeKiB = maps.fold<double>(0, (sum, entry) => sum + entry.sizeKiB);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total cache size: ${_formatBytes(totalSizeKiB)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: kTextSecondaryColor,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ...maps.map((entry) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          AppSignals.targetTab.value = 1;
                          if (entry.centerLat != null && entry.centerLon != null) {
                            AppSignals.focusedMapCenter.value =
                                latlng.LatLng(entry.centerLat!, entry.centerLon!);
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: kSurfaceColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: kSecondaryColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.map_rounded, color: kSecondaryColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.label,
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_formatDownloadedAt(entry.downloadedAtIso)} • ${entry.tileCount} tiles • ${_formatBytes(entry.sizeKiB)}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: kTextSecondaryColor,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: kTextSecondaryColor),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
  });

  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext context, A first, B second, Widget? child)
      builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, firstValue, child) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, secondValue, _) {
            return builder(context, firstValue, secondValue, child);
          },
        );
      },
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _GlobalSignalOverlay extends StatefulWidget {
  const _GlobalSignalOverlay({
    required this.sender,
    required this.locationText,
    required this.onView,
    required this.onDismiss,
  });

  final String sender;
  final String locationText;
  final VoidCallback onView;
  final VoidCallback onDismiss;

  @override
  State<_GlobalSignalOverlay> createState() => _GlobalSignalOverlayState();
}

class _GlobalSignalOverlayState extends State<_GlobalSignalOverlay> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration.zero, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          offset: _visible ? Offset.zero : const Offset(0, -1),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kPrimaryColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DISTRESS SIGNAL FROM ${widget.sender}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Location: ${widget.locationText}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
                ),
                const SizedBox(height: 6),
                Text(
                  'New distress alert nearby',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kTextSecondaryColor,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: widget.onView,
                      child: const Text('VIEW'),
                    ),
                    TextButton(
                      onPressed: widget.onDismiss,
                      child: const Text('DISMISS'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
