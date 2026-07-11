import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/session_controller.dart';
import '../models/remote_event.dart';
import '../widgets/screen_select_dialog.dart';
import 'host_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _serverController = TextEditingController(text: 'ws://localhost:3000/ws');
  final _roomController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null) {
      _serverController.text = saved;
    }
  }

  Future<void> _saveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _serverController.text.trim());
  }

  Future<void> _startHost() async {
    String? screenSourceId;
    String? screenSourceName;
    String? screenSourceType;
    if (WebRTC.platformIsDesktop) {
      final source = await showDialog<DesktopCapturerSource>(
        context: context,
        builder: (context) => const ScreenSelectDialog(),
      );
      if (source == null || !mounted) return;
      screenSourceId = source.id;
      screenSourceName = source.name;
      screenSourceType = desktopSourceTypeToString[source.type];
    }

    setState(() => _loading = true);
    final session = context.read<SessionController>();
    session.serverUrl = _serverController.text.trim();
    await _saveServerUrl();
    await session.connectAsHost(
      screenSourceId: screenSourceId,
      screenSourceName: screenSourceName,
      screenSourceType: screenSourceType,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (session.status == ConnectionStatus.error || session.roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.errorMessage ?? '未获取到房间号')),
      );
      await session.disconnect();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostScreen()),
    );
    await session.disconnect();
  }

  Future<void> _startViewer() async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入房间号')),
      );
      return;
    }

    setState(() => _loading = true);
    final session = context.read<SessionController>();
    session.serverUrl = _serverController.text.trim();
    await _saveServerUrl();
    await session.connectAsViewer(roomId);

    if (!mounted) return;
    setState(() => _loading = false);

    if (session.status == ConnectionStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.errorMessage ?? '连接失败')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ViewerScreen()),
    );
    await session.disconnect();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.desktop_windows_rounded,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    '远程桌面控制',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '基于 WebRTC 的低延迟远程桌面',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: '信令服务器',
                      hintText: 'ws://localhost:3000/ws',
                      prefixIcon: Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    icon: Icons.cast_connected,
                    title: '作为主机',
                    subtitle: '共享本机屏幕，等待控制端连接',
                    color: theme.colorScheme.primaryContainer,
                    onPressed: _loading ? null : _startHost,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _roomController,
                    decoration: const InputDecoration(
                      labelText: '房间号',
                      hintText: '输入主机提供的房间号',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    icon: Icons.touch_app,
                    title: '作为控制端',
                    subtitle: '连接远程主机并操控桌面',
                    color: theme.colorScheme.secondaryContainer,
                    onPressed: _loading ? null : _startViewer,
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
