// calibration_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import '../services/mqtt_service.dart';
import '../services/database_service.dart';

class CalibrationScreen extends StatefulWidget {
  final MQTTService mqttService;
  
  const CalibrationScreen({super.key, required this.mqttService});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final DatabaseService _databaseService = DatabaseService();
  
  bool _isConnected = false;
  bool _isCalibrating = false;
  String _currentCalibrationStep = 'Aguardando...';
  double _calibrationProgress = 0.0;
  
  // Fatores de calibração carregados do banco
  double _fatorZ1 = 1.0;
  double _fatorZ2 = 1.0;
  double _fatorZ3 = 1.0;
  double _fatorT1 = 1.0;
  double _fatorT2 = 1.0;
  double _tensaoRede = 220.0;
  
  // Valores de referência para calibração
  double _referenciaZ1 = 9.0; // 9W para lâmpada LED
  double _referenciaZ2 = 9.0;
  double _referenciaZ3 = 9.0;
  double _referenciaT1 = 45.0; // 45W para tomada comum
  double _referenciaT2 = 45.0;
  
  @override
  void initState() {
    super.initState();
    _loadCalibrationFactors();
  }
  
  Future<void> _loadCalibrationFactors() async {
    try {
      // Carregar tensão da rede
      _tensaoRede = await _databaseService.getTensaoRede();
      
      // Aqui você poderia carregar os fatores de calibração salvos
      // Por enquanto, vamos usar valores padrão
      setState(() {
        _fatorZ1 = 1.0;
        _fatorZ2 = 1.0;
        _fatorZ3 = 1.0;
        _fatorT1 = 1.0;
        _fatorT2 = 1.0;
      });
      
      print('✅ Fatores de calibração carregados');
    } catch (e) {
      print('❌ Erro ao carregar fatores de calibração: $e');
    }
  }
  
  void _startCalibration(String sensor, double referencia) {
    if (!widget.mqttService.isConnected) {
      _showErrorDialog('Erro', 'Conecte-se ao sistema antes de calibrar');
      return;
    }
    
    setState(() {
      _isCalibrating = true;
      _calibrationProgress = 0.0;
      _currentCalibrationStep = 'Iniciando calibração...';
    });
    
    // Enviar comando de calibração via MQTT
    widget.mqttService.publishMessage('energia/calibracao', 'calibrar_iniciar $sensor $referencia');
    
    // Simular progresso (na implementação real, isso viria do ESP32)
    _simulateCalibrationProgress();
  }
  
  void _simulateCalibrationProgress() {
    // Esta função simula o progresso da calibração
    // Na implementação real, você receberia atualizações via MQTT
    
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _calibrationProgress = 0.2;
        _currentCalibrationStep = 'Conectando carga de referência...';
      });
    });
    
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _calibrationProgress = 0.4;
        _currentCalibrationStep = 'Medindo corrente...';
      });
    });
    
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        _calibrationProgress = 0.6;
        _currentCalibrationStep = 'Calculando fator de correção...';
      });
    });
    
    Future.delayed(const Duration(seconds: 4), () {
      setState(() {
        _calibrationProgress = 0.8;
        _currentCalibrationStep = 'Validando medição...';
      });
    });
    
    Future.delayed(const Duration(seconds: 5), () {
      setState(() {
        _calibrationProgress = 1.0;
        _currentCalibrationStep = 'Calibração concluída!';
        _isCalibrating = false;
      });
      
      // Mostrar mensagem de sucesso
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Calibração concluída com sucesso!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
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
  
  Widget _buildSensorCalibrationCard(String title, String sensorId, double referencia, 
                                     double fatorAtual, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sensorId.startsWith('z') ? Icons.lightbulb_outline : Icons.power,
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
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
                        'Referência: ${referencia.toStringAsFixed(0)}W',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fator atual: ${fatorAtual.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                
                ElevatedButton(
                  onPressed: _isCalibrating ? null : () => _startCalibration(sensorId, referencia),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                  child: const Text('Calibrar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCalibrationProgress() {
    if (!_isCalibrating) return const SizedBox();
    
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Calibração em Andamento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            LinearProgressIndicator(
              value: _calibrationProgress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            
            const SizedBox(height: 12),
            
            Text(
              _currentCalibrationStep,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            Text(
              '${(_calibrationProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInstructions() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📋 Instruções de Calibração',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            
            const SizedBox(height: 12),
            
            _buildInstructionStep('1️⃣', 'Conecte uma carga conhecida (ex: lâmpada LED 9W)'),
            _buildInstructionStep('2️⃣', 'Clique em "Calibrar" para o sensor correspondente'),
            _buildInstructionStep('3️⃣', 'Aguarde o sistema realizar as medições'),
            _buildInstructionStep('4️⃣', 'O fator de correção será calculado automaticamente'),
            _buildInstructionStep('5️⃣', 'Repita para todos os sensores'),
            
            const SizedBox(height: 12),
            
            const Divider(),
            
            const SizedBox(height: 8),
            
            const Text(
              '💡 Dica: Use cargas com potência estável para melhores resultados',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInstructionStep(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibração de Sensores'),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildInstructions(),
          
          const SizedBox(height: 20),
          
          _buildCalibrationProgress(),
          
          if (_isCalibrating) const SizedBox(height: 20),
          
          const Text(
            'Sensores de Iluminação',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          
          const SizedBox(height: 12),
          
          _buildSensorCalibrationCard('Zona 1 - Lâmpadas', 'z1', _referenciaZ1, _fatorZ1, Colors.amber),
          const SizedBox(height: 12),
          _buildSensorCalibrationCard('Zona 2 - Lâmpadas', 'z2', _referenciaZ2, _fatorZ2, Colors.orange),
          const SizedBox(height: 12),
          _buildSensorCalibrationCard('Zona 3 - Lâmpadas', 'z3', _referenciaZ3, _fatorZ3, Colors.deepOrange),
          
          const SizedBox(height: 20),
          
          const Text(
            'Sensores de Tomadas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          
          const SizedBox(height: 12),
          
          _buildSensorCalibrationCard('Tomada 1', 't1', _referenciaT1, _fatorT1, Colors.blue),
          const SizedBox(height: 12),
          _buildSensorCalibrationCard('Tomada 2', 't2', _referenciaT2, _fatorT2, Colors.lightBlue),
          
          const SizedBox(height: 20),
          
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚙️ Configurações Avançadas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tensão da Rede:', style: TextStyle(fontSize: 14)),
                      Text(
                        '${_tensaoRede.toStringAsFixed(1)}V',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Slider(
                    value: _tensaoRede,
                    min: 100,
                    max: 250,
                    divisions: 30,
                    label: '${_tensaoRede.toStringAsFixed(1)}V',
                    onChanged: (value) {
                      setState(() => _tensaoRede = value);
                    },
                    onChangeEnd: (value) {
                      // Salvar tensão no banco
                      _databaseService.setSetting('tensao_rede', value.toStringAsFixed(1));
                    },
                  ),
                  
                  const SizedBox(height: 12),
                  
                  ElevatedButton.icon(
                    onPressed: () {
                      // Comando para resetar calibração no ESP32
                      widget.mqttService.publishMessage('energia/calibracao', 'calibrar_cancelar');
                      _loadCalibrationFactors();
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar Calibração Padrão'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}