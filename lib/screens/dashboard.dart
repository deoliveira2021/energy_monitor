import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import '../services/mqtt_service.dart';
import '../services/database_service.dart';
import '../models/sensor_data.dart';
import '../models/energy_data.dart';

class DashboardScreen extends StatefulWidget {
  final MQTTService mqttService;
  
  const DashboardScreen({super.key, required this.mqttService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _databaseService = DatabaseService();
  
  bool _isConnected = false;
  bool _isConnecting = false;
  Map<String, dynamic> _currentData = {};
  bool _modoAutomatico = true;

  // Variáveis para dados de energia
  double _consumoTotal = 0.0;
  double _potenciaTotal = 0.0;
  double _potenciaZona1 = 0.0;
  double _potenciaZona2 = 0.0;
  double _potenciaZona3 = 0.0;
  double _potenciaTomada1 = 0.0;
  double _potenciaTomada2 = 0.0;

  // Variáveis para tempos de uso
  double _tempoZona1 = 0.0;
  double _tempoZona2 = 0.0;
  double _tempoZona3 = 0.0;
  double _tempoTomada1 = 0.0;
  double _tempoTomada2 = 0.0;
  double _tempoPresenca = 0.0;
  
  // Configurações
  String _moeda = 'R\$';
  double _valorKwh = 1.00;
  
  // Variáveis de controle de salvamento
  int _lastSavedLuminosity = -1;
  bool _lastSavedPresence = false;
  DateTime _lastSaveTime = DateTime.now();
  
  // Variável para botão de presença
  bool _presencaAtiva = false;

  @override
  void initState() {
    super.initState();
    _initializeMQTT();
    _checkExistingConnection();
    _initializeDatabase();
    _carregarConfiguracoes();
  }

  void _initializeMQTT() {
    widget.mqttService.messageStream.listen((data) {
      if (mounted) {
        setState(() {
          if (data.containsKey('tipo') && data['tipo'] == 'energia') {
            // Processar dados de energia
            final dadosEnergia = data['dados'] as Map<String, dynamic>;
            _processarDadosEnergia(dadosEnergia);
          } else {
            // Processar dados normais do sistema
            _currentData.addAll(data);
            
            // Atualizar presença
            if (data.containsKey('presenca')) {
              _presencaAtiva = data['presenca'];
            }
            
            if (data.containsKey('modo_auto')) {
              _modoAutomatico = data['modo_auto'];
            }
            
            if (data.containsKey('connected')) {
              _isConnected = data['connected'];
            }
          }
        });
      }
    });
  }

  void _processarDadosEnergia(Map<String, dynamic> dados) {
    setState(() {
      _potenciaTotal = dados['potencia_total'] ?? 0.0;
      _potenciaZona1 = dados['potencia_zona1'] ?? 0.0;
      _potenciaZona2 = dados['potencia_zona2'] ?? 0.0;
      _potenciaZona3 = dados['potencia_zona3'] ?? 0.0;
      _potenciaTomada1 = dados['potencia_tomada1'] ?? 0.0;
      _potenciaTomada2 = dados['potencia_tomada2'] ?? 0.0;
      _consumoTotal = dados['consumo_total'] ?? 0.0;
      
      _tempoZona1 = dados['tempo_zona1'] ?? 0.0;
      _tempoZona2 = dados['tempo_zona2'] ?? 0.0;
      _tempoZona3 = dados['tempo_zona3'] ?? 0.0;
      _tempoTomada1 = dados['tempo_tomada1'] ?? 0.0;
      _tempoTomada2 = dados['tempo_tomada2'] ?? 0.0;
      _tempoPresenca = dados['tempo_presenca'] ?? 0.0;
    });
    
    // Salvar dados de energia no banco
    _salvarDadosEnergia();
  }

  void _salvarDadosEnergia() async {
    try {
      final currentLuminosity = _currentData['luminosidade'] ?? 0;
      final currentPresence = _currentData['presenca'] ?? false;
      final now = DateTime.now();
      
      // Intervalo de 5 minutos (300 segundos) entre salvamentos
      final timeSinceLastSave = now.difference(_lastSaveTime).inSeconds;
      final hasLuminosityChanged = (currentLuminosity - _lastSavedLuminosity).abs() > 50;
      final hasPresenceChanged = currentPresence != _lastSavedPresence;
      
      // Só salva a cada 5 minutos ou quando houver mudança significativa
      if (!hasLuminosityChanged && !hasPresenceChanged && timeSinceLastSave < 300) {
        return;
      }
      
      // Atualizar variáveis de controle
      _lastSavedLuminosity = currentLuminosity;
      _lastSavedPresence = currentPresence;
      _lastSaveTime = now;

      final energyData = EnergyData(
        timestamp: now,
        powerTotal: _potenciaTotal,
        powerZone1: _potenciaZona1,
        powerZone2: _potenciaZona2,
        powerZone3: _potenciaZona3,
        powerTomada1: _potenciaTomada1,
        powerTomada2: _potenciaTomada2,
        consumptionTotal: _consumoTotal,
        timeZone1: _tempoZona1,
        timeZone2: _tempoZona2,
        timeZone3: _tempoZona3,
        timeTomada1: _tempoTomada1,
        timeTomada2: _tempoTomada2,
        timePresence: _tempoPresenca,
      );
      
      await _databaseService.insertEnergyData(energyData);
      
      print('💾 Dados de energia salvos');
      
    } catch (e) {
      print('❌ Erro ao salvar dados de energia: $e');
    }
  }

  void _checkExistingConnection() {
    if (widget.mqttService.client != null) {
      setState(() {
        _isConnected = widget.mqttService.isConnected;
      });
    }
  }

  void _initializeDatabase() async {
    try {
      await _databaseService.initialize();
      print('🗃️ Banco de dados inicializado para energia');
    } catch (e) {
      print('❌ Erro ao inicializar banco: $e');
    }
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      _moeda = await _databaseService.getMoeda();
      _valorKwh = await _databaseService.getValorKwh();
      print('💰 Configurações carregadas: $_moeda, kWh: $_valorKwh');
    } catch (e) {
      print('❌ Erro ao carregar configurações: $e');
    }
  }

  Future<void> _connectMQTT() async {
    if (_isConnecting) return;
    
    setState(() => _isConnecting = true);
    
    try {
      final connected = await widget.mqttService.connect();
      
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _isConnecting = false;
        });
      }
      
      if (connected) {
        await Future.delayed(const Duration(seconds: 1));
        widget.mqttService.requestStatusUpdate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
        });
      }
      _showErrorDialog('Erro de Conexão', 'Não foi possível conectar ao sistema: $e');
    }
  }

  void _disconnectMQTT() {
    widget.mqttService.disconnect();
    setState(() {
      _isConnected = false;
      _currentData.clear();
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ========== MÉTODOS DE CONTROLE ==========

  void _toggleModoAutomatico(bool value) {
    setState(() {
      _modoAutomatico = value;
    });
    
    if (value) {
      widget.mqttService.setModoAutomatico();
    } else {
      widget.mqttService.setModoManual();
    }
  }

  // BOTÃO DE PRESENÇA - AGORA FUNCIONANDO CORRETAMENTE
  void _togglePresenca() {
    if (!_isConnected) return;
    
    final novaPresenca = !_presencaAtiva;
    
    if (novaPresenca) {
      // Ativar presença
      _enviarComandoPresenca(true);
    } else {
      // Desativar presença
      _enviarComandoPresenca(false);
    }
  }

  // No método _togglePresenca(), linha 216-228:
  // void _enviarComandoPresenca(bool ativar) {
  //   if (ativar) {
  //     // CORREÇÃO: Usar método público em vez de privado
  //     widget.mqttService.ativarPresenca();
  //     print('🎯 [DASHBOARD] Enviando comando: presenca_on');
  //   } else {
  //     // CORREÇÃO: Usar método público em vez de privado
  //     widget.mqttService.desativarPresenca();
  //     print('🎯 [DASHBOARD] Enviando comando: presenca_off');
  //   }
    
  //   // Atualiza estado local imediatamente para feedback visual
  //   setState(() {
  //     _presencaAtiva = ativar;
  //     _currentData['presenca'] = ativar;
  //   });
  // }
  void _enviarComandoPresenca(bool ativar) {
  if (ativar) {
    widget.mqttService.ativarPresenca();
    print('🎯 [DASHBOARD] Enviando comando: presenca_on');
  } else {
    widget.mqttService.desativarPresenca();
    print('🎯 [DASHBOARD] Enviando comando: presenca_off');
  }
  
  // Atualiza estado local imediatamente para feedback visual
  setState(() {
    _presencaAtiva = ativar;
    _currentData['presenca'] = ativar;
  });
}

  void _toggleZona1(bool value) {
    widget.mqttService.toggleZona1(value);
    setState(() {
      _currentData['zona1'] = value;
    });
  }

  void _toggleZona2(bool value) {
    widget.mqttService.toggleZona2(value);
    setState(() {
      _currentData['zona2'] = value;
    });
  }

  void _toggleZona3(bool value) {
    widget.mqttService.toggleZona3(value);
    setState(() {
      _currentData['zona3'] = value;
    });
  }

  void _toggleTomada1(bool value) {
    widget.mqttService.toggleTomada1(value);
    setState(() {
      _currentData['tomada1'] = value;
    });
  }

  void _toggleTomada2(bool value) {
    widget.mqttService.toggleTomada2(value);
    setState(() {
      _currentData['tomada2'] = value;
    });
  }

  // ========== WIDGETS DO DASHBOARD ==========

  Widget _buildConnectionStatus() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                if (_isConnecting)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  )
                else
                  Icon(
                    _isConnected ? Icons.wifi : Icons.wifi_off,
                    color: Colors.white,
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isConnecting 
                      ? 'Conectando...' 
                      : _isConnected ? 'Conectado' : 'Desconectado',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  Text(
                    'broker.hivemq.com:1883',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _isConnecting 
                  ? null 
                  : _isConnected ? _disconnectMQTT : _connectMQTT,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isConnected ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(_isConnected ? 'Desconectar' : 'Conectar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresenceCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: _presencaAtiva ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Presença',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _presencaAtiva ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _togglePresenca : null,
                  icon: Icon(
                    _presencaAtiva ? Icons.person_off : Icons.person_add,
                    size: 20,
                  ),
                  label: Text(_presencaAtiva ? 'Desativar' : 'Ativar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _presencaAtiva ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _tempoPresenca > 0 ? 1.0 : 0.0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                _presencaAtiva ? Colors.green : Colors.grey,
              ),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _presencaAtiva ? 'Ativa' : 'Inativa',
                  style: TextStyle(
                    color: _presencaAtiva ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Tempo: ${(_tempoPresenca / 3600).toStringAsFixed(1)}h',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyConsumptionCard() {
    final valorConsumo = (_consumoTotal / 1000) * _valorKwh;
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Consumo de Energia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Potência e Consumo Total
            Row(
              children: [
                Expanded(
                  child: _buildEnergyMetric(
                    'Potência Atual',
                    '${_potenciaTotal.toStringAsFixed(1)} W',
                    Colors.orange,
                    Icons.flash_on,
                  ),
                ),
                Expanded(
                  child: _buildEnergyMetric(
                    'Consumo Hoje',
                    '${(_consumoTotal / 1000).toStringAsFixed(2)} kWh',
                    Colors.green,
                    Icons.energy_savings_leaf,
                  ),
                ),
                Expanded(
                  child: _buildEnergyMetric(
                    'Valor',
                    '$_moeda ${valorConsumo.toStringAsFixed(2)}',
                    Colors.blue,
                    Icons.monetization_on,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Distribuição de Potência
            _buildPowerDistribution(),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyMetric(String title, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPowerDistribution() {
    double total = _potenciaZona1 + _potenciaZona2 + _potenciaZona3 + _potenciaTomada1 + _potenciaTomada2;
    
    if (total == 0) {
      return const Text(
        'Nenhum consumo no momento',
        style: TextStyle(color: Colors.grey, fontSize: 12),
        textAlign: TextAlign.center,
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Distribuição de Potência:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildPowerBar('💡 Zona 1', _potenciaZona1, total, Colors.amber),
        _buildPowerBar('💡 Zona 2', _potenciaZona2, total, Colors.orange),
        _buildPowerBar('💡 Zona 3', _potenciaZona3, total, Colors.deepOrange),
        _buildPowerBar('🔌 Tomada 1', _potenciaTomada1, total, Colors.blue),
        _buildPowerBar('🔌 Tomada 2', _potenciaTomada2, total, Colors.lightBlue),
      ],
    );
  }

  Widget _buildPowerBar(String label, double value, double total, Color color) {
    double percentage = total > 0 ? (value / total) * 100 : 0;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              '${value.toStringAsFixed(1)}W',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageTimeCard() {
    String formatTime(double seconds) {
      int hours = seconds ~/ 3600;
      int minutes = (seconds % 3600) ~/ 60;
      if (hours > 0) {
        return '${hours}h ${minutes}m';
      }
      return '${minutes}m';
    }
    
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Tempos de Uso (Hoje)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTimeItem('👤 Presença', formatTime(_tempoPresenca), Colors.orange),
            _buildTimeItem('💡 Zona 1', formatTime(_tempoZona1), Colors.amber),
            _buildTimeItem('💡 Zona 2', formatTime(_tempoZona2), Colors.orange),
            _buildTimeItem('💡 Zona 3', formatTime(_tempoZona3), Colors.deepOrange),
            _buildTimeItem('🔌 Tomada 1', formatTime(_tempoTomada1), Colors.blue),
            _buildTimeItem('🔌 Tomada 2', formatTime(_tempoTomada2), Colors.lightBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLuminosityCard() {
    int luminosidade = _currentData['luminosidade'] ?? 0;
    String statusLuz = _getLuminosityStatus(luminosidade);
    Color colorLuz = _getLuminosityColor(luminosidade);
    double progressValue = luminosidade / 4095.0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.light_mode,
                  color: colorLuz,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Luminosidade',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorLuz,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$luminosidade',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colorLuz,
                        ),
                      ),
                      Text(
                        statusLuz,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorLuz,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorLuz,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      CircularProgressIndicator(
                        value: progressValue,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(colorLuz),
                        strokeWidth: 4,
                      ),
                      Center(
                        child: Icon(
                          _getLuminosityIcon(luminosidade),
                          color: colorLuz,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progressValue,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(colorLuz),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getLuminosityIcon(int luminosity) {
    if (luminosity < 1000) return Icons.nightlight;
    if (luminosity < 2000) return Icons.lightbulb_outline;
    if (luminosity < 3000) return Icons.wb_sunny;
    return Icons.brightness_high;
  }

  String _getLuminosityStatus(int luminosity) {
    if (luminosity < 1000) return 'Muito Escuro';
    if (luminosity < 2000) return 'Escuro';
    if (luminosity < 3000) return 'Moderado';
    return 'Muito Claro';
  }

  Color _getLuminosityColor(int luminosity) {
    if (luminosity < 1000) return Colors.blue.shade700;
    if (luminosity < 2000) return Colors.orange.shade700;
    if (luminosity < 3000) return Colors.yellow.shade700;
    return Colors.red.shade700;
  }

  Widget _buildZoneCard(String zoneName, bool isActive, int zoneNumber) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              zoneName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isActive ? Colors.yellow.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? Colors.amber : Colors.grey,
                  width: 3,
                ),
              ),
              child: Icon(
                Icons.lightbulb_outline,
                size: 40,
                color: isActive ? Colors.amber : Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isActive ? 'LIGADA' : 'DESLIGADA',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            FlutterSwitch(
              value: isActive,
              onToggle: !_modoAutomatico && _isConnected ? 
                (value) {
                  switch (zoneNumber) {
                    case 1: _toggleZona1(value); break;
                    case 2: _toggleZona2(value); break;
                    case 3: _toggleZona3(value); break;
                  }
                } : (value) {},
              activeColor: Colors.blue,
              width: 50,
              height: 25,
              toggleColor: !_modoAutomatico && _isConnected ? Colors.white : Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZonesControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Controle de Zonas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildZoneCard(
                'Zona 1',
                _currentData['zona1'] ?? false,
                1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildZoneCard(
                'Zona 2',
                _currentData['zona2'] ?? false,
                2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildZoneCard(
                'Zona 3',
                _currentData['zona3'] ?? false,
                3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlSwitch(String title, bool value, Function(bool) onChanged, {bool enabled = true}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: enabled ? Colors.black : Colors.grey,
                  ),
                ),
                if (!enabled)
                  Text(
                    'Modo automático ativo',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
            FlutterSwitch(
              value: value,
              onToggle: enabled ? onChanged : (bool val) {},
              activeColor: enabled ? Colors.blue : Colors.grey,
              inactiveColor: Colors.grey.shade300,
              toggleColor: enabled ? Colors.white : Colors.grey.shade100,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Controles do Sistema',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildControlSwitch(
          'Modo Automático',
          _modoAutomatico,
          _toggleModoAutomatico,
          enabled: _isConnected,
        ),
        const SizedBox(height: 8),
        _buildControlSwitch(
          'Tomada Inteligente 1',
          _currentData['tomada1'] ?? false,
          _toggleTomada1,
          enabled: !_modoAutomatico && _isConnected,
        ),
        const SizedBox(height: 8),
        _buildControlSwitch(
          'Tomada Inteligente 2',
          _currentData['tomada2'] ?? false,
          _toggleTomada2,
          enabled: !_modoAutomatico && _isConnected,
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    // Calcular estados dos dispositivos
    final zona1Ativa = _currentData['zona1'] ?? false;
    final zona2Ativa = _currentData['zona2'] ?? false;
    final zona3Ativa = _currentData['zona3'] ?? false;
    final tomada1Ativa = _currentData['tomada1'] ?? false;
    final tomada2Ativa = _currentData['tomada2'] ?? false;
    
    final todosLigados = zona1Ativa && zona2Ativa && zona3Ativa && tomada1Ativa && tomada2Ativa;
    final todosDesligados = !zona1Ativa && !zona2Ativa && !zona3Ativa && !tomada1Ativa && !tomada2Ativa;
    
    // Verificar se pelo menos um está desligado
    final algumDesligado = !zona1Ativa || !zona2Ativa || !zona3Ativa || !tomada1Ativa || !tomada2Ativa;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ações Rápidas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isConnected && !_modoAutomatico && algumDesligado
                    ? () {
                        if (!zona1Ativa) _toggleZona1(true);
                        if (!zona2Ativa) _toggleZona2(true);
                        if (!zona3Ativa) _toggleZona3(true);
                        if (!tomada1Ativa) _toggleTomada1(true);
                        if (!tomada2Ativa) _toggleTomada2(true);
                      }
                    : null,
                icon: const Icon(Icons.power),
                label: const Text('Ligar Todos'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: _isConnected && !_modoAutomatico && algumDesligado 
                      ? Colors.green 
                      : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isConnected && !_modoAutomatico && !todosDesligados
                    ? () {
                        if (zona1Ativa) _toggleZona1(false);
                        if (zona2Ativa) _toggleZona2(false);
                        if (zona3Ativa) _toggleZona3(false);
                        if (tomada1Ativa) _toggleTomada1(false);
                        if (tomada2Ativa) _toggleTomada2(false);
                      }
                    : null,
                icon: const Icon(Icons.power_off),
                label: const Text('Desligar Todos'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: _isConnected && !_modoAutomatico && !todosDesligados
                      ? Colors.red 
                      : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _modoAutomatico 
              ? '⚠️ Ações rápidas disponíveis apenas no modo manual'
              : todosLigados
                  ? '✅ Todos os dispositivos estão ligados'
                  : todosDesligados
                      ? '⏸️ Todos os dispositivos estão desligados'
                      : '${[zona1Ativa, zona2Ativa, zona3Ativa, tomada1Ativa, tomada2Ativa].where((e) => e).length} de 5 dispositivos ligados',
          style: TextStyle(
            fontSize: 12,
            color: _modoAutomatico ? Colors.orange : Colors.grey,
            fontStyle: _modoAutomatico ? FontStyle.italic : FontStyle.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildConnectionRequired() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 24),
          const Text(
            'Sistema Desconectado',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Conecte-se ao sistema para monitorar\n e controlar os dispositivos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _connectMQTT,
            icon: const Icon(Icons.wifi),
            label: const Text('Conectar ao Sistema'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildConnectionStatus(),
        const SizedBox(height: 20),
        _buildPresenceCard(), // NOVO: Card de presença
        const SizedBox(height: 20),
        _buildEnergyConsumptionCard(),
        const SizedBox(height: 20),
        _buildLuminosityCard(),
        const SizedBox(height: 20),
        _buildZonesControl(),
        const SizedBox(height: 20),
        _buildSystemControls(),
        const SizedBox(height: 20),
        _buildQuickActions(),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard - Controle de Energia'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isConnected ? () => widget.mqttService.requestStatusUpdate() : null,
            tooltip: 'Atualizar Status',
          ),
        ],
      ),
      body: _isConnected ? _buildDashboardContent() : _buildConnectionRequired(),
    );
  }
}