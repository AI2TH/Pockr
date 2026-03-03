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
      if (mounted) Provider.of<VmState>(context, listen: false).refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VmState>(
      builder: (context, vmState, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B1120),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(vmState),
                  _buildStatusBanner(vmState),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResourceCards(vmState),
                        const SizedBox(height: 20),
                        _buildControlButtons(vmState),
                        if (vmState.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _buildErrorCard(vmState.errorMessage!),
                        ],
                        const SizedBox(height: 20),
                        _buildQuickActions(vmState),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(VmState vmState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/logo.jpeg',
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pockr',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Container Engine',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => vmState.refreshStatus(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: vmState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF1D6FE5)),
                      ),
                    )
                  : Icon(Icons.refresh_rounded,
                      color: Colors.white.withOpacity(0.6), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(VmState vmState) {
    final isRunning = vmState.status == 'running';
    final isStarting = vmState.status == 'starting';
    final color = isRunning
        ? const Color(0xFF00C896)
        : isStarting
            ? const Color(0xFFFF9500)
            : const Color(0xFF6B7280);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRunning
                  ? Icons.play_circle_filled_rounded
                  : isStarting
                      ? Icons.hourglass_top_rounded
                      : Icons.stop_circle_rounded,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      vmState.status.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    if (isRunning) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: color, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isRunning
                      ? vmState.isHealthy
                          ? 'API healthy at localhost:7080'
                          : 'VM running — API warming up...'
                      : isStarting
                          ? 'Extracting assets and launching QEMU...'
                          : 'Virtual machine is not running',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isRunning)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  vmState.isHealthy ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: vmState.isHealthy ? const Color(0xFF00C896) : Colors.white.withOpacity(0.3),
                  size: 20,
                ),
                const SizedBox(height: 2),
                Text(
                  vmState.isHealthy ? 'Healthy' : 'Checking',
                  style: TextStyle(
                    color: vmState.isHealthy
                        ? const Color(0xFF00C896)
                        : Colors.white.withOpacity(0.3),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildResourceCards(VmState vmState) {
    return Row(
      children: [
        Expanded(child: _resourceCard('Engine', 'QEMU/Alpine', Icons.memory_rounded, const Color(0xFF6366F1))),
        const SizedBox(width: 12),
        Expanded(child: _resourceCard('Runtime', 'Docker', Icons.widgets_rounded, const Color(0xFF1D6FE5))),
        const SizedBox(width: 12),
        Expanded(child: _resourceCard('API', 'Port 7080', Icons.wifi_rounded,
            vmState.isHealthy ? const Color(0xFF00C896) : const Color(0xFF6B7280))),
      ],
    );
  }

  Widget _resourceCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161F2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(VmState vmState) {
    final canStart = (vmState.status == 'stopped' || vmState.status == 'error') && !vmState.isLoading;
    final canStop = vmState.status == 'running' && !vmState.isLoading;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: canStart ? () => vmState.startVm() : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: canStart
                    ? const LinearGradient(
                        colors: [Color(0xFF1D6FE5), Color(0xFF1558C0)],
                      )
                    : null,
                color: canStart ? null : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: canStart
                      ? Colors.transparent
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded,
                      color: canStart ? Colors.white : Colors.white.withOpacity(0.2),
                      size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Start Engine',
                    style: TextStyle(
                      color: canStart ? Colors.white : Colors.white.withOpacity(0.2),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: canStop ? () => vmState.stopVm() : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: canStop
                    ? const Color(0xFF2A1215)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: canStop
                      ? const Color(0xFFE5534B).withOpacity(0.4)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop_rounded,
                      color: canStop
                          ? const Color(0xFFE5534B)
                          : Colors.white.withOpacity(0.2),
                      size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Stop Engine',
                    style: TextStyle(
                      color: canStop
                          ? const Color(0xFFE5534B)
                          : Colors.white.withOpacity(0.2),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1215),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5534B).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFE5534B), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: const Color(0xFFE5534B).withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(VmState vmState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Run',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        _quickActionTile(
          icon: Icons.science_rounded,
          color: const Color(0xFF6366F1),
          title: 'busybox',
          subtitle: 'echo "hello from Docker"',
          enabled: vmState.isHealthy,
          onTap: () => _runContainer(
            vmState, 'busybox',
            'test_${DateTime.now().millisecondsSinceEpoch}',
            ['echo', 'hello from Docker on Android'],
          ),
        ),
        const SizedBox(height: 8),
        _quickActionTile(
          icon: Icons.lan_rounded,
          color: const Color(0xFF0DB7ED),
          title: 'alpine:3.19',
          subtitle: 'sleep 60 — long-running test',
          enabled: vmState.isHealthy,
          onTap: () => _runContainer(
            vmState, 'alpine:3.19',
            'alpine_${DateTime.now().millisecondsSinceEpoch}',
            ['sleep', '60'],
          ),
        ),
        const SizedBox(height: 8),
        _quickActionTile(
          icon: Icons.dns_rounded,
          color: const Color(0xFF00C896),
          title: 'nginx:alpine',
          subtitle: 'Run a web server on port 8080',
          enabled: vmState.isHealthy,
          onTap: () => _runContainer(
            vmState, 'nginx:alpine',
            'nginx_${DateTime.now().millisecondsSinceEpoch}',
            [],
          ),
        ),
      ],
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161F2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.2),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runContainer(VmState vmState, String image, String name, List<String> cmd) async {
    try {
      await VmPlatform.startContainer(image, name, cmd);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF00C896), size: 16),
                const SizedBox(width: 8),
                Text('Started $image'),
              ],
            ),
            backgroundColor: const Color(0xFF161F2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: const TextStyle(fontSize: 12)),
            backgroundColor: const Color(0xFF2A1215),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
}
