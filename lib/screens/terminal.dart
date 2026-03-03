import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/vm_platform.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalEntry {
  final String cmd;
  final String stdout;
  final String stderr;
  final int exitCode;
  _TerminalEntry(this.cmd, this.stdout, this.stderr, this.exitCode);
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _cmdController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_TerminalEntry> _history = [];
  bool _busy = false;

  static const _quickCmds = [
    'docker ps -a',
    'docker images',
    'free -h',
    'df -h',
    'uname -a',
    'ps aux | head -20',
  ];

  @override
  void dispose() {
    _cmdController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _run(String cmd) async {
    final trimmed = cmd.trim();
    if (trimmed.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await VmPlatform.vmExec(trimmed);
      setState(() {
        _history.add(_TerminalEntry(
          trimmed,
          (result['stdout'] as String?) ?? '',
          (result['stderr'] as String?) ?? '',
          (result['exitCode'] as int?) ?? -1,
        ));
      });
    } catch (e) {
      setState(() {
        _history.add(_TerminalEntry(trimmed, '', e.toString(), -1));
      });
    } finally {
      setState(() => _busy = false);
      _cmdController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vmReady = context.watch<VmState>().isHealthy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear',
              onPressed: () => setState(() => _history.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          // Quick-command chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickCmds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ActionChip(
                label: Text(
                  _quickCmds[i],
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                backgroundColor: const Color(0xFF1A2540),
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
                onPressed: (vmReady && !_busy) ? () => _run(_quickCmds[i]) : null,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E2D45)),

          // Output area
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Text(
                      vmReady ? 'Run a command to see output' : 'VM not running',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _history.length,
                    itemBuilder: (_, i) => _buildEntry(_history[i]),
                  ),
          ),

          // Input row
          _buildInputRow(vmReady),
        ],
      ),
    );
  }

  Widget _buildEntry(_TerminalEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command line
          Row(
            children: [
              Text('\$ ', style: TextStyle(color: Colors.green[400], fontFamily: 'monospace', fontSize: 13)),
              Expanded(
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: e.cmd));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Text(
                    e.cmd,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (e.exitCode != 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${e.exitCode}',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                ),
            ],
          ),
          // stdout
          if (e.stdout.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 14),
              child: SelectableText(
                e.stdout.trimRight(),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.45),
              ),
            ),
          // stderr
          if (e.stderr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 14),
              child: SelectableText(
                e.stderr.trimRight(),
                style: const TextStyle(
                    color: Colors.orange,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.45),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputRow(bool vmReady) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(top: BorderSide(color: Color(0xFF1E2D45))),
      ),
      child: Row(
        children: [
          Text('\$ ', style: TextStyle(color: Colors.green[400], fontFamily: 'monospace', fontSize: 14)),
          Expanded(
            child: TextField(
              controller: _cmdController,
              enabled: vmReady && !_busy,
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: vmReady ? 'enter command...' : 'VM not running',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.25),
                    fontFamily: 'monospace',
                    fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (vmReady && !_busy) ? _run : null,
              textInputAction: TextInputAction.send,
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.send, size: 20),
              color: vmReady ? const Color(0xFF1D6FE5) : Colors.white24,
              onPressed: (vmReady && !_busy)
                  ? () => _run(_cmdController.text)
                  : null,
            ),
        ],
      ),
    );
  }
}
