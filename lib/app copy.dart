// import 'package:flutter/material.dart';
// import 'screens/dashboard.dart';
// import 'screens/history.dart';
// import 'screens/charts.dart';
// import 'screens/settings.dart';
// import 'services/mqtt_service.dart';

// class App extends StatefulWidget {
//   const App({super.key});

//   @override
//   State<App> createState() => _AppState();
// }

// class _AppState extends State<App> with WidgetsBindingObserver {
//   late final MQTTService _mqttService;
//   int _currentIndex = 0;
//   bool _presencaAtiva = false;

//   final List<Widget> _screens = [];

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _mqttService = MQTTService();
//     _initializeScreens();
//     _setupPresenceListener();
//   }

//   void _initializeScreens() {
//     _screens.addAll([
//       DashboardScreen(mqttService: _mqttService),
//       const ChartsScreen(),
//       const HistoryScreen(),
//       const SettingsScreen(),
//     ]);
//   }

//   void _setupPresenceListener() {
//     _mqttService.messageStream.listen((data) {
//       if (data.containsKey('presenca')) {
//         if (mounted) {
//           setState(() {
//             _presencaAtiva = data['presenca'];
//           });
//         }
//       }
//     });
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.resumed) {
//       if (!_mqttService.isConnected) {
//         _mqttService.connect();
//       }
//     }
//   }

//   // CORREÇÃO: Alterar o método para retornar AppBar diretamente
//   AppBar _buildAppBarWithPresence() {
//     return AppBar(
//       title: Row(
//         children: [
//           const Text('Controle de Energia'),
//           const Spacer(),
//           Icon(
//             Icons.person,
//             color: _presencaAtiva ? Colors.green : Colors.grey,
//             size: 24,
//           ),
//           const SizedBox(width: 4),
//           Text(
//             _presencaAtiva ? 'Presente' : 'Ausente',
//             style: TextStyle(
//               fontSize: 12,
//               color: _presencaAtiva ? Colors.green : Colors.grey,
//             ),
//           ),
//         ],
//       ),
//       backgroundColor: Colors.blue.shade700,
//       foregroundColor: Colors.white,
//       elevation: 0,
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       // CORREÇÃO: Usar o método que retorna AppBar diretamente
//       appBar: _currentIndex == 0 ? _buildAppBarWithPresence() : null,
//       body: _screens[_currentIndex],
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _currentIndex,
//         onTap: (index) => setState(() => _currentIndex = index),
//         type: BottomNavigationBarType.fixed,
//         backgroundColor: Colors.blue.shade700,
//         selectedItemColor: Colors.white,
//         unselectedItemColor: Colors.white.withOpacity(0.6),
//         items: const [
//           BottomNavigationBarItem(
//             icon: Icon(Icons.dashboard),
//             label: 'Dashboard',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.show_chart),
//             label: 'Gráficos',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.history),
//             label: 'Histórico',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.settings),
//             label: 'Configurações',
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _mqttService.dispose();
//     super.dispose();
//   }
// }

// app.dart (modificado)
import 'package:flutter/material.dart';
import 'screens/dashboard.dart';
import 'screens/history.dart';
import 'screens/charts.dart';
import 'screens/settings.dart';
import 'screens/calibration_screen.dart'; // NOVO
import 'services/mqtt_service.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  late final MQTTService _mqttService;
  int _currentIndex = 0;
  bool _presencaAtiva = false;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mqttService = MQTTService();
    _initializeScreens();
    _setupPresenceListener();
  }

  void _initializeScreens() {
    _screens.addAll([
      DashboardScreen(mqttService: _mqttService),
      const ChartsScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
      CalibrationScreen(mqttService: _mqttService), // NOVA TELA
    ]);
  }

  void _setupPresenceListener() {
    _mqttService.messageStream.listen((data) {
      if (data.containsKey('presenca')) {
        if (mounted) {
          setState(() {
            _presencaAtiva = data['presenca'];
          });
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_mqttService.isConnected) {
        _mqttService.connect();
      }
    }
  }

  AppBar _buildAppBarWithPresence() {
    return AppBar(
      title: Row(
        children: [
          const Text('Controle de Energia'),
          const Spacer(),
          Icon(
            Icons.person,
            color: _presencaAtiva ? Colors.green : Colors.grey,
            size: 24,
          ),
          const SizedBox(width: 4),
          Text(
            _presencaAtiva ? 'Presente' : 'Ausente',
            style: TextStyle(
              fontSize: 12,
              color: _presencaAtiva ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.blue.shade700,
      foregroundColor: Colors.white,
      elevation: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0 ? _buildAppBarWithPresence() : null,
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.blue.shade700,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white.withOpacity(0.6),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Gráficos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Histórico',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Configurações',
          ),
          BottomNavigationBarItem( // NOVO
            icon: Icon(Icons.tune),
            label: 'Calibração',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mqttService.dispose();
    super.dispose();
  }
}