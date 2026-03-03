import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/dashboard.dart';
import 'screens/containers.dart';
import 'screens/terminal.dart';
import 'screens/settings.dart';
import 'services/vm_platform.dart';

void main() {
  runApp(const DockerApp());
}

class DockerApp extends StatelessWidget {
  const DockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VmState(),
      child: MaterialApp(
        title: 'Docker VM',
        theme: ThemeData(
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFF1D6FE5),
            secondary: const Color(0xFF00C896),
            surface: const Color(0xFF161F2E),
            background: const Color(0xFF0B1120),
          ),
          scaffoldBackgroundColor: const Color(0xFF0B1120),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: const Color(0xFF111827),
            indicatorColor: const Color(0xFF1D6FE5).withOpacity(0.2),
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Color(0xFF1D6FE5));
              }
              return IconThemeData(color: Colors.white.withOpacity(0.4));
            }),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0B1120),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = <Widget>[
    DashboardScreen(),
    ContainersScreen(),
    TerminalScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_list),
            label: 'Containers',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal),
            label: 'Terminal',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
