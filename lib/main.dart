import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:weather_watcher/models/ble_characteristic.dart';
import 'package:weather_watcher/sensors/sensorpush.dart';
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
  String? _sensorOutput;

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

  Future<void> _testSensorPushRead() async {
    const deviceId = '2037602C-1C15-BEE5-B4E7-8D6025F45DF1';
    final sensorPush = SensorPush.defaultConfig();

    setState(() => _sensorOutput = '🔄 Reading...');

    try {
      final result = await sensorPush.getTempAndHumidity(deviceId: deviceId);
      setState(() => _sensorOutput = '🌡️ Temp: ${result['temperature_C']} °C\n'
          '💧 Humidity: ${result['humidity_percent']} % \n🔋 Voltage: ${result['voltage_mV']} mV\n');
    } catch (e) {
      setState(() => _sensorOutput = '❌ Error: $e');
    }
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
              ElevatedButton(
                onPressed: _testSensorPushRead,
                child: const Text('Test SensorPush'),
              ),
            ],
          ),
          if (_sensorOutput != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_sensorOutput!, style: const TextStyle(fontSize: 16)),
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SensorDetailPage(device: d),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class SensorDetailPage extends StatefulWidget {
  final DiscoveredDevice device;

  const SensorDetailPage({super.key, required this.device});

  @override
  State<SensorDetailPage> createState() => _SensorDetailPageState();
}

class _SensorDetailPageState extends State<SensorDetailPage> {
  Map<String, List<BleCharacteristic>>? gattInfo;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadGatt();
  }

  Future<void> _loadGatt() async {
    try {
      final result = await BleUtils.connectAndCheckGatt(widget.device.id);
      setState(() {
        gattInfo = result;
        loading = false;
      });
    } catch (e) {
      setState(() {
        gattInfo = {
          'Error': [
            BleCharacteristic(
              uuid: 'error',
              name: e.toString(),
              capabilities: [],
            )
          ]
        };
        loading = false;
      });
    }
  }

  void _navigateToCharacteristic(String deviceId, String serviceId, BleCharacteristic characteristic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacteristicValuePage(
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: characteristic.uuid,
          capabilities: characteristic.capabilities,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name.isNotEmpty ? widget.device.name : widget.device.id)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : gattInfo == null || gattInfo!.isEmpty
          ? const Center(child: Text('Not GATT-enabled or no services found.'))
          : ListView(
        children: gattInfo!.entries.map((entry) {
          return ExpansionTile(
            title: Text(entry.key),
            children: entry.value.map((char) => ListTile(
              title: Text('${char.name} (${char.capabilities.join(", ")})'),
              onTap: () => _navigateToCharacteristic(
                widget.device.id,
                entry.key,
                char,
              ),
            )).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class CharacteristicValuePage extends StatefulWidget {
  final String deviceId;
  final String serviceId;
  final String characteristicId;
  final List<String> capabilities;

  const CharacteristicValuePage({
    super.key,
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required this.capabilities,
  });

  @override
  State<CharacteristicValuePage> createState() => _CharacteristicValuePageState();
}

class _CharacteristicValuePageState extends State<CharacteristicValuePage> {
  String? value;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _readValue();
  }

  Future<void> _readValue() async {
    try {
      final result = await BleUtils.readCharacteristic(
        deviceId: widget.deviceId,
        serviceUuid: Uuid.parse(widget.serviceId),
        characteristicUuid: Uuid.parse(widget.characteristicId),
        capabilities: widget.capabilities,
      );
      setState(() {
        value = result.toString();
        loading = false;
      });
    } catch (e) {
      print('Error reading characteristic: $e');
      setState(() {
        value = '❌ Error: $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.characteristicId)),
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(value ?? 'No value'),
        ),
      ),
    );
  }
}
