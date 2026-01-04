
// history.dart (modificado)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/energy_data.dart'; // Removido sensor_data.dart

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _databaseService = DatabaseService();
  
  List<EnergyData> _energyData = [];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // Dados de consumo acumulado
  double _consumoDia = 0.0;
  double _consumoMes = 0.0;
  
  // Configurações de moeda e kWh
  String _moeda = 'R\$';
  double _valorKwh = 1.00;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _loadData();
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
      
      // Carregar apenas dados de energia
      final energyData = await _databaseService.getEnergyData(start, end);
      
      // Calcular consumo acumulado do dia
      _consumoDia = _calcularConsumoDia(energyData);
      
      // Calcular consumo acumulado do mês
      _consumoMes = await _calcularConsumoMes(_selectedDate);
      
      setState(() {
        _energyData = energyData.reversed.toList(); // Mais recentes primeiro
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() => _isLoading = false);
      print('❌ Erro ao carregar dados: $e');
    }
  }

  double _calcularConsumoDia(List<EnergyData> energyData) {
    if (energyData.isEmpty) return 0.0;
    
    // Pegar o último registro que tem o consumo acumulado do dia
    final ultimoRegistro = energyData.last;
    return ultimoRegistro.consumptionTotal / 1000; // Converter para kWh
  }

  Future<double> _calcularConsumoMes(DateTime data) async {
    try {
      final inicioMes = DateTime(data.year, data.month, 1);
      final fimMes = DateTime(data.year, data.month + 1, 0, 23, 59, 59);
      
      final dadosMes = await _databaseService.getEnergyData(inicioMes, fimMes);
      
      if (dadosMes.isEmpty) return 0.0;
      
      // Pegar o consumo acumulado do último registro do mês
      final ultimoRegistroMes = dadosMes.last;
      return ultimoRegistroMes.consumptionTotal / 1000; // Converter para kWh
    } catch (e) {
      print('❌ Erro ao calcular consumo mensal: $e');
      return 0.0;
    }
  }

  Widget _buildDateAndConsumptionHeader() {
    // Calcular valores em moeda
    final valorConsumoDia = _consumoDia * _valorKwh;
    final valorConsumoMes = _consumoMes * _valorKwh;
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Navegação por Data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  onPressed: () {
                    setState(() {
                      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    });
                    _loadData();
                  },
                  tooltip: 'Dia anterior',
                  color: Colors.blue,
                ),
                
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        DateFormat('EEEE, dd/MM/yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_energyData.length} registros de consumo',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: _selectedDate.isBefore(DateTime.now()) ? () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _loadData();
                  } : null,
                  tooltip: 'Próximo dia',
                  color: _selectedDate.isBefore(DateTime.now()) ? Colors.blue : Colors.grey,
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            
            // Consumo Acumulado em kWh e Moeda
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildConsumoCard(
                  'Consumo do Dia',
                  '${_consumoDia.toStringAsFixed(2)} kWh',
                  Colors.green,
                  Icons.today,
                  valorMoeda: '$_moeda ${valorConsumoDia.toStringAsFixed(2)}',
                ),
                _buildConsumoCard(
                  'Consumo do Mês',
                  '${_consumoMes.toStringAsFixed(2)} kWh',
                  Colors.blue,
                  Icons.calendar_today,
                  valorMoeda: '$_moeda ${valorConsumoMes.toStringAsFixed(2)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumoCard(String titulo, String valor, Color cor, IconData icone, {String? valorMoeda}) {
    return Column(
      children: [
        Icon(icone, color: cor, size: 24),
        const SizedBox(height: 4),
        Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
        if (valorMoeda != null)
          Text(
            valorMoeda,
            style: TextStyle(
              fontSize: 12,
              color: cor.withOpacity(0.8),
            ),
          ),
      ],
    );
  }

  Widget _buildEnergyHistory() {
    if (_energyData.isEmpty) {
      return _buildEmptyState('Nenhum registro de consumo encontrado');
    }

    return ListView.builder(
      itemCount: _energyData.length,
      itemBuilder: (context, index) {
        return _buildEnergyHistoryItem(_energyData[index], index);
      },
    );
  }

  Widget _buildEnergyHistoryItem(EnergyData data, int index) {
    // Calcular valores em moeda
    final consumoKwh = data.consumptionTotal / 1000;
    final valorConsumo = consumoKwh * _valorKwh;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('HH:mm:ss').format(data.timestamp),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${data.powerTotal.toStringAsFixed(1)} W',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (data.powerZone1 > 0) _buildPowerIndicator('Z1', data.powerZone1),
                if (data.powerZone2 > 0) _buildPowerIndicator('Z2', data.powerZone2),
                if (data.powerZone3 > 0) _buildPowerIndicator('Z3', data.powerZone3),
                if (data.powerTomada1 > 0) _buildPowerIndicator('T1', data.powerTomada1),
                if (data.powerTomada2 > 0) _buildPowerIndicator('T2', data.powerTomada2),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'Consumo: ${consumoKwh.toStringAsFixed(3)} kWh',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Valor: $_moeda ${valorConsumo.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerIndicator(String label, double power) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${power.toStringAsFixed(1)}W',
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Data: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Consumo'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildDateAndConsumptionHeader(),
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _buildEnergyHistory(),
          ),
        ],
      ),
    );
  }
}