import 'package:flutter/material.dart';
import '../services/vm_platform.dart';
import '../models/container.dart' as models;

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  List<models.Container> _containers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final containerMaps = await VmPlatform.listContainers();
      setState(() {
        _containers = containerMaps
            .map((map) => models.Container.fromJson(map))
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading containers: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Containers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadContainers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _containers.isEmpty
              ? _buildEmptyState()
              : _buildContainerList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContainerDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No containers running',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadContainers,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildContainerList() {
    return RefreshIndicator(
      onRefresh: _loadContainers,
      child: ListView.builder(
        itemCount: _containers.length,
        itemBuilder: (context, index) {
          final container = _containers[index];
          return _buildContainerCard(container);
        },
      ),
    );
  }

  Widget _buildContainerCard(models.Container container) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Icon(
          Icons.widgets,
          color: container.status == 'running' ? Colors.green : Colors.grey,
        ),
        title: Text(
          container.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${container.image} • ${container.status}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (container.ports.isNotEmpty) ...[
                  const Text(
                    'Ports:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(container.ports.join(', ')),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _viewLogs(container.name),
                        icon: const Icon(Icons.article),
                        label: const Text('Logs'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: container.status == 'running'
                            ? () => _stopContainer(container.name)
                            : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddContainerDialog() {
    final imageController = TextEditingController(text: 'busybox');
    final nameController = TextEditingController();
    final cmdController = TextEditingController(text: 'echo hello');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Container'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: imageController,
              decoration: const InputDecoration(
                labelText: 'Image',
                hintText: 'e.g., busybox, alpine:3.19',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Auto-generated if empty',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: cmdController,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'e.g., echo hello',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final image = imageController.text.trim();
              final name = nameController.text.trim().isEmpty
                  ? 'container_${DateTime.now().millisecondsSinceEpoch}'
                  : nameController.text.trim();
              final cmd = cmdController.text.trim().split(' ');

              Navigator.pop(context);

              try {
                await VmPlatform.startContainer(image, name, cmd);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Container started')),
                  );
                  _loadContainers();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopContainer(String name) async {
    try {
      await VmPlatform.stopContainer(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Container stopped')),
        );
        _loadContainers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _viewLogs(String name) async {
    try {
      final logs = await VmPlatform.getLogs(name, 100);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Logs: $name'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Text(
                  logs.isEmpty ? 'No logs available' : logs,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching logs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
