import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:weather_watcher/utils/ble_utils.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final status = await Permission.locationWhenInUse.request();
  print('🔐 Initial location permission request: $status');

  runApp(const BleTestApp());
}

class BleTestApp extends StatelessWidget {
  const BleTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Tester',
      home: const BleTestScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({super.key});

  @override
  State<BleTestScreen> createState() => _BleTestScreenState();
}

class _BleTestScreenState extends State<BleTestScreen> {
  final Map<String, DiscoveredDevice> _displayedDeviceMap = {};
  bool _scanning = false;
  bool _scanningSupported = false;
  DateTime? _lastScan;

  Future<void> _scan() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _lastScan = DateTime.now();
    });

    try {
      await BleUtils.startBleScan();
    } catch (e) {
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      return;
    }

    final subscription = BleUtils.devicesStream.listen((devices) {
      for (final device in devices) {
        _displayedDeviceMap[device.id] = device;
        setState(() {});
      }
    });

    try {
      await Future.delayed(const Duration(seconds: 1));
    } finally {
      await subscription.cancel();
      BleUtils.stopBleScan();

      setState(() {
        _scanning = false;
      });
    }
  }

  Future<void> _scanSupportedSensors() async {
    if (_scanningSupported) return;

    setState(() {
      _scanningSupported = true;
      _displayedDeviceMap.clear();
    });

    final devices = await BleUtils.scanForSupportedSensors();

    setState(() {
      for (final device in devices) {
        _displayedDeviceMap[device.id] = device;
      }
      _scanningSupported = false;
    });
  }

  @override
  void dispose() {
    BleUtils.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedDeviceMap = _displayedDeviceMap.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(title: const Text('BLE Scanner')),
      body: Column(
        children: [
          const SizedBox(height: 16),
          if (_lastScan != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Last scanned: ${_lastScan!.toLocal()}'),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              ElevatedButton(
                onPressed: _scanning ? null : _scan,
                child: _scanning
                    ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Scanning...')
                  ],
                )
                    : const Text('Start BLE Scan'),
              ),
              ElevatedButton(
                onPressed: _scanningSupported ? null : _scanSupportedSensors,
                child: _scanningSupported
                    ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Searching...')
                  ],
                )
                    : const Text('Supported Sensors'),
              ),
            ],
          ),
          const Divider(height: 32),
          Expanded(
            child: ListView.builder(
              itemCount: displayedDeviceMap.length,
              itemBuilder: (_, i) {
                final d = displayedDeviceMap[i];
                return ListTile(
                  title: Text(
                    'Name: ${d.name.isNotEmpty ? d.name : '(Unnamed)'}\nID: ${d.id}\nRSSI: ${d.rssi}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}