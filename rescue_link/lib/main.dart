import 'package:flutter/material.dart';

void main() {
  runApp(const RescueLinkApp());
}

const Color kBackgroundColor = Color(0xFF0D0D0D);
const Color kSurfaceColor = Color(0xFF1A1A1A);
const Color kPrimaryColor = Color(0xFFFF3B30);
const Color kSecondaryColor = Color(0xFF3A86FF);
const Color kSuccessColor = Color(0xFF2ECC71);
const Color kTextPrimaryColor = Color(0xFFFFFFFF);
const Color kTextSecondaryColor = Color(0xFFB0B0B0);

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

  void _showGlobalSignalOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _GlobalSignalOverlay(
          onDismiss: () {
            _overlayEntry?.remove();
            _overlayEntry = null;
          },
          onView: () {
            setState(() => _currentIndex = 1);
            _overlayEntry?.remove();
            _overlayEntry = null;
          },
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onShowGlobalOverlay: _showGlobalSignalOverlay),
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
  const HomeScreen({super.key, required this.onShowGlobalOverlay});

  final VoidCallback onShowGlobalOverlay;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isActive = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 1.0,
      upperBound: 1.05,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleSos() {
    setState(() => _isActive = !_isActive);
    if (_isActive) {
      _pulseController.repeat(reverse: true);
      widget.onShowGlobalOverlay();
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Emergency SOS',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Center(
                child: SOSButton(
                  isActive: _isActive,
                  pulseAnimation: _pulseController,
                  onLongPress: _toggleSos,
                ),
              ),
            ),
            const SizedBox(height: 20),
            StatusCard(isActive: _isActive),
            const SizedBox(height: 10),
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
    required this.onLongPress,
  });

  final bool isActive;
  final Animation<double> pulseAnimation;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ScaleTransition(
        scale: pulseAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kPrimaryColor,
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withValues(alpha: isActive ? 0.8 : 0.4),
                blurRadius: isActive ? 28 : 20,
                spreadRadius: isActive ? 2 : 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              isActive ? 'ACTIVE' : 'SOS',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: kTextPrimaryColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StatusRow(
            icon: Icons.location_on,
            iconColor: kSecondaryColor,
            label: 'Location: 11.0168, 76.9558',
          ),
          const SizedBox(height: 10),
          const _StatusRow(
            icon: Icons.bluetooth,
            iconColor: kSecondaryColor,
            label: 'Bluetooth: Scanning',
          ),
          const SizedBox(height: 10),
          _StatusRow(
            icon: Icons.warning_rounded,
            iconColor: isActive ? kPrimaryColor : kSuccessColor,
            label: 'Status: ${isActive ? 'Active' : 'Safe'}',
          ),
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
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  void _showSignalSheet(BuildContext context) {
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
                'Location: 11.0180, 76.9562',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Time: 10:42 PM',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Hops: 4',
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
                        backgroundColor: kSecondaryColor,
                        foregroundColor: kTextPrimaryColor,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('View Details'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSuccessColor,
                        foregroundColor: kTextPrimaryColor,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: kBackgroundColor),
          Positioned.fill(
            child: Stack(
              children: [
                Positioned(
                  top: 180,
                  left: 80,
                  child: DistressMarker(onTap: () => _showSignalSheet(context)),
                ),
                const Positioned(top: 320, right: 130, child: UserMarker()),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  onPressed: () {},
                  child: const Icon(Icons.my_location_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  mini: true,
                  onPressed: () {},
                  child: const Icon(Icons.explore_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DistressMarker extends StatefulWidget {
  const DistressMarker({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<DistressMarker> createState() => _DistressMarkerState();
}

class _DistressMarkerState extends State<DistressMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 20,
      upperBound: 30,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _controller.value,
            height: _controller.value,
            decoration: BoxDecoration(
              color: kPrimaryColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withValues(alpha: 0.7),
                  blurRadius: 18,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class UserMarker extends StatelessWidget {
  const UserMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: kSecondaryColor,
        shape: BoxShape.circle,
        border: Border.all(color: kTextPrimaryColor, width: 2),
      ),
    );
  }
}

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  static const List<Map<String, String>> _events = [
    {'location': '11.0168, 76.9558', 'time': '10:21 PM', 'hops': '3'},
    {'location': '11.0180, 76.9562', 'time': '10:42 PM', 'hops': '4'},
    {'location': '11.0159, 76.9531', 'time': '11:05 PM', 'hops': '2'},
  ];

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
              child: ListView.builder(
                itemCount: _events.length,
                itemBuilder: (context, index) => EventCard(
                  location: _events[index]['location']!,
                  time: _events[index]['time']!,
                  hops: _events[index]['hops']!,
                ),
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
    required this.hops,
  });

  final String location;
  final String time;
  final String hops;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DISTRESS SIGNAL',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('📍 Location: $location'),
          Text('🕒 Time: $time'),
          Text('🔁 Hops: $hops'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kSecondaryColor),
                    foregroundColor: kSecondaryColor,
                  ),
                  onPressed: () {},
                  child: const Text('View'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSuccessColor,
                    foregroundColor: kTextPrimaryColor,
                  ),
                  onPressed: () {},
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
  bool _bluetoothEnabled = true;
  bool _locationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Permissions',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bluetooth'),
                  value: _bluetoothEnabled,
                  onChanged: (value) =>
                      setState(() => _bluetoothEnabled = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Location'),
                  value: _locationEnabled,
                  onChanged: (value) =>
                      setState(() => _locationEnabled = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Contacts',
            child: Column(
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person),
                  title: Text('Emergency Contact'),
                  subtitle: Text('+91 98765 43210'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kSecondaryColor,
                      foregroundColor: kTextPrimaryColor,
                    ),
                    onPressed: () {},
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionCard(
            title: 'Device Info',
            child: Text('Device ID: RL-DEV-2026-001'),
          ),
        ],
      ),
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
  const _GlobalSignalOverlay({required this.onView, required this.onDismiss});

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
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DISTRESS SIGNAL',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Location: 11.0180, 76.9562',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: kTextSecondaryColor),
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
