import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _vcpuCount = 2;
  int _ramMb = 2048;
  bool _autoStart = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vcpuCount = prefs.getInt('vcpu_count') ?? 2;
      _ramMb = prefs.getInt('ram_mb') ?? 2048;
      _autoStart = prefs.getBool('auto_start') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vcpu_count', _vcpuCount);
    await prefs.setInt('ram_mb', _ramMb);
    await prefs.setBool('auto_start', _autoStart);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'VM Resources',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('vCPU Count'),
            subtitle: Text('$_vcpuCount cores'),
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: _vcpuCount.toDouble(),
                min: 1,
                max: 4,
                divisions: 3,
                label: '$_vcpuCount',
                onChanged: (value) {
                  setState(() {
                    _vcpuCount = value.toInt();
                  });
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('RAM'),
            subtitle: Text('${_ramMb}MB'),
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: _ramMb.toDouble(),
                min: 512,
                max: 4096,
                divisions: 7,
                label: '${_ramMb}MB',
                onChanged: (value) {
                  setState(() {
                    _ramMb = value.toInt();
                  });
                },
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Startup',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.power_settings_new),
            title: const Text('Auto-start VM'),
            subtitle: const Text('Start VM when app launches'),
            value: _autoStart,
            onChanged: (value) {
              setState(() {
                _autoStart = value;
              });
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'About',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('Version'),
            subtitle: Text('1.0.0+1'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Architecture'),
            subtitle: Text('Flutter + QEMU + Alpine Linux'),
          ),
          ListTile(
            leading: const Icon(Icons.article),
            title: const Text('Documentation'),
            subtitle: const Text('View architecture docs'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Documentation'),
                  content: const Text(
                    'See ARCHITECTURE.md and ARC_START.md in the project root.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
