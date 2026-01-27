import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vm_platform.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      Provider.of<VmState>(context, listen: false).refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Docker VM Dashboard'),
      ),
      body: Consumer<VmState>(
        builder: (context, vmState, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(vmState),
                const SizedBox(height: 16),
                _buildHealthCard(vmState),
                const SizedBox(height: 24),
                _buildActionButtons(vmState),
                const SizedBox(height: 24),
                _buildQuickActionsCard(vmState),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(VmState vmState) {
    Color statusColor;
    IconData statusIcon;

    switch (vmState.status) {
      case 'running':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'starting':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        break;
      case 'stopped':
        statusColor = Colors.grey;
        statusIcon = Icons.stop_circle;
        break;
      case 'error':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VM Status',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vmState.status.toUpperCase(),
                    style: TextStyle(fontSize: 24, color: statusColor),
                  ),
                ],
              ),
            ),
            if (vmState.isLoading)
              const CircularProgressIndicator()
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => vmState.refreshStatus(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard(VmState vmState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              vmState.isHealthy ? Icons.favorite : Icons.favorite_border,
              color: vmState.isHealthy ? Colors.green : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API Health',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vmState.isHealthy
                        ? 'API responding at localhost:7080'
                        : 'API not reachable',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(VmState vmState) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: vmState.status == 'stopped' && !vmState.isLoading
                ? () => vmState.startVm()
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start VM'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: vmState.status == 'running' && !vmState.isLoading
                ? () => vmState.stopVm()
                : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop VM'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsCard(VmState vmState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.science),
              title: const Text('Run Test Container'),
              subtitle: const Text('busybox echo "hello"'),
              trailing: const Icon(Icons.arrow_forward),
              enabled: vmState.isHealthy,
              onTap: vmState.isHealthy
                  ? () async {
                      try {
                        await VmPlatform.startContainer(
                          'busybox',
                          'test_${DateTime.now().millisecondsSinceEpoch}',
                          ['echo', 'hello from Docker VM'],
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Test container started'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: const Text('Run Alpine'),
              subtitle: const Text('alpine:3.19 sleep 60'),
              trailing: const Icon(Icons.arrow_forward),
              enabled: vmState.isHealthy,
              onTap: vmState.isHealthy
                  ? () async {
                      try {
                        await VmPlatform.startContainer(
                          'alpine:3.19',
                          'alpine_${DateTime.now().millisecondsSinceEpoch}',
                          ['sleep', '60'],
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Alpine container started'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
