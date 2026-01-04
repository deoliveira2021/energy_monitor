import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/sensor_data.dart';
import '../models/energy_data.dart';

enum ChartType {
  luminosity,
  powerConsumption,
  usageTime,
  dailyConsumption,
  monthlyConsumption,
}

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<SensorData> _sensorData = [];
  List<EnergyData> _energyData = [];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  
  ChartType _selectedChartType = ChartType.powerConsumption;
  bool _showSettings = false;
  
  // Configurações do gráfico atual
  bool _showPowerZones = true;
  bool _showPowerSockets = false;
  
  // Configurações de moeda
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
      if (_selectedChartType == ChartType.luminosity || 
          _selectedChartType == ChartType.powerConsumption ||
          _selectedChartType == ChartType.usageTime) {
        
        // Gráficos que usam dados do dia
        final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
        
        if (_selectedChartType == ChartType.luminosity) {
          _sensorData = await _databaseService.getSensorData(start, end);
          _sensorData = _filterData(_sensorData);
        } else {
          _energyData = await _databaseService.getEnergyData(start, end);
          _energyData = _filterData(_energyData);
        }
      } else if (_selectedChartType == ChartType.dailyConsumption) {
        // Gráfico de consumo diário - últimos 7 dias
        await _loadDailyConsumptionData();
      } else if (_selectedChartType == ChartType.monthlyConsumption) {
        // Gráfico de consumo mensal - últimos 12 meses
        await _loadMonthlyConsumptionData();
      }
      
      setState(() => _isLoading = false);
      
    } catch (e) {
      setState(() => _isLoading = false);
      print('❌ Erro ao carregar dados: $e');
    }
  }

  // Future<void> _loadDailyConsumptionData() async {
  //   final List<ChartData> dailyData = [];
    
  //   // Buscar dados dos últimos 7 dias
  //   for (int i = 6; i >= 0; i--) {
  //     final date = DateTime.now().subtract(Duration(days: i));
  //     final start = DateTime(date.year, date.month, date.day);
  //     final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
  //     try {
  //       final data = await _databaseService.getEnergyData(start, end);
  //       double consumoDia = 0.0;
        
  //       if (data.isNotEmpty) {
  //         // Pegar o consumo acumulado do último registro do dia
  //         consumoDia = data.last.consumptionTotal / 1000;
  //       }
        
  //       // Usar dias da semana abreviados
  //       final dayName = _getWeekdayAbbreviation(date.weekday);
        
  //       dailyData.add(ChartData(
  //         dayName,
  //         consumoDia,
  //         _getDayColor(date),
  //       ));
  //     } catch (e) {
  //       print('❌ Erro ao carregar dados do dia ${DateFormat('dd/MM').format(date)}: $e');
  //       dailyData.add(ChartData(
  //         _getWeekdayAbbreviation(date.weekday),
  //         0.0,
  //         _getDayColor(date),
  //       ));
  //     }
  //   }
    
  //   // Converter para o formato esperado pelo gráfico
  //   _energyData = dailyData.map((e) => EnergyData(
  //     timestamp: DateTime.now(),
  //     powerTotal: e.value,
  //     powerZone1: 0,
  //     powerZone2: 0,
  //     powerZone3: 0,
  //     powerTomada1: 0,
  //     powerTomada2: 0,
  //     consumptionTotal: e.value * 1000,
  //     timeZone1: 0,
  //     timeZone2: 0,
  //     timeZone3: 0,
  //     timeTomada1: 0,
  //     timeTomada2: 0,
  //     timePresence: 0,
  //   )).toList();
  // }

  Future<void> _loadDailyConsumptionData() async {
    final List<ChartData> dailyData = [];
    
    // Ajustar para começar no domingo
    DateTime hoje = _selectedDate;
    int diaDaSemana = hoje.weekday; // 1 = domingo, 2 = segunda, ..., 7 = sábado
    
    // Buscar dados dos últimos 7 dias começando no domingo
    for (int i = 6; i >= 0; i--) {
      // Ajustar para que o índice 0 seja domingo, 1 segunda, etc.
      int diasParaSubtrair = (diaDaSemana - 1 + (6 - i)) % 7;
      final date = hoje.subtract(Duration(days: diasParaSubtrair));
      final start = DateTime(date.year, date.month, date.day);
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      try {
        final data = await _databaseService.getEnergyData(start, end);
        double consumoDia = 0.0;
        
        if (data.isNotEmpty) {
          // Pegar o consumo acumulado do último registro do dia
          consumoDia = data.last.consumptionTotal / 1000;
        }
        
        // Usar dias da semana abreviados começando no domingo
        final dayName = _getWeekdayAbbreviation(date.weekday);
        
        dailyData.add(ChartData(
          dayName,
          consumoDia,
          _getDayColor(date),
        ));
      } catch (e) {
        print('❌ Erro ao carregar dados do dia ${DateFormat('dd/MM').format(date)}: $e');
        dailyData.add(ChartData(
          _getWeekdayAbbreviation(date.weekday),
          0.0,
          _getDayColor(date),
        ));
      }
    }
    
    // Ordenar por dia da semana (domingo primeiro)
    dailyData.sort((a, b) {
      final dias = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
      return dias.indexOf(a.category).compareTo(dias.indexOf(b.category));
    });
    
    // Converter para o formato esperado pelo gráfico
    _energyData = dailyData.map((e) => EnergyData(
      timestamp: DateTime.now(),
      powerTotal: e.value,
      powerZone1: 0,
      powerZone2: 0,
      powerZone3: 0,
      powerTomada1: 0,
      powerTomada2: 0,
      consumptionTotal: e.value * 1000,
      timeZone1: 0,
      timeZone2: 0,
      timeZone3: 0,
      timeTomada1: 0,
      timeTomada2: 0,
      timePresence: 0,
    )).toList();
  }


  String _getWeekdayAbbreviation(int weekday) {
    switch (weekday) {
      case 1: return 'Seg';
      case 2: return 'Ter';
      case 3: return 'Qua';
      case 4: return 'Qui';
      case 5: return 'Sex';
      case 6: return 'Sáb';
      case 7: return 'Dom';
      default: return '';
    }
  }

  Future<void> _loadMonthlyConsumptionData() async {
    final List<ChartData> monthlyData = [];
    final now = DateTime.now();
    
    // Buscar dados dos últimos 12 meses
    for (int i = 11; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      final start = DateTime(date.year, date.month, 1);
      final end = DateTime(date.year, date.month + 1, 0, 23, 59, 59);
      
      try {
        final data = await _databaseService.getEnergyData(start, end);
        double consumoMes = 0.0;
        
        if (data.isNotEmpty) {
          // Pegar o consumo acumulado do último registro do mês
          consumoMes = data.last.consumptionTotal / 1000;
        }
        
        // Usar meses abreviados
        final monthName = _getMonthAbbreviation(date.month);
        
        monthlyData.add(ChartData(
          monthName,
          consumoMes,
          _getMonthColor(date.month),
        ));
      } catch (e) {
        print('❌ Erro ao carregar dados do mês ${DateFormat('MM/yyyy').format(date)}: $e');
        monthlyData.add(ChartData(
          _getMonthAbbreviation(date.month),
          0.0,
          _getMonthColor(date.month),
        ));
      }
    }
    
    // Converter para o formato esperado pelo gráfico
    _energyData = monthlyData.map((e) => EnergyData(
      timestamp: DateTime.now(),
      powerTotal: e.value,
      powerZone1: 0,
      powerZone2: 0,
      powerZone3: 0,
      powerTomada1: 0,
      powerTomada2: 0,
      consumptionTotal: e.value * 1000,
      timeZone1: 0,
      timeZone2: 0,
      timeZone3: 0,
      timeTomada1: 0,
      timeTomada2: 0,
      timePresence: 0,
    )).toList();
  }

  String _getMonthAbbreviation(int month) {
    switch (month) {
      case 1: return 'Jan';
      case 2: return 'Fev';
      case 3: return 'Mar';
      case 4: return 'Abr';
      case 5: return 'Mai';
      case 6: return 'Jun';
      case 7: return 'Jul';
      case 8: return 'Ago';
      case 9: return 'Set';
      case 10: return 'Out';
      case 11: return 'Nov';
      case 12: return 'Dez';
      default: return '';
    }
  }

  Color _getDayColor(DateTime date) {
    final weekDay = date.weekday;
    return weekDay == DateTime.saturday || weekDay == DateTime.sunday 
        ? Colors.green 
        : Colors.blue;
  }

  Color _getMonthColor(int month) {
    // Cores diferentes para cada estação do ano (aproximadamente)
    if (month >= 3 && month <= 5) return Colors.green; // Primavera
    if (month >= 6 && month <= 8) return Colors.orange; // Verão
    if (month >= 9 && month <= 11) return Colors.brown; // Outono
    return Colors.blue; // Inverno
  }

  List<T> _filterData<T>(List<T> data) {
    if (data.length <= 100) return data;
    
    int step = (data.length / 100).ceil();
    return List.generate(
      (data.length / step).ceil(),
      (i) => data[i * step],
    );
  }

  // Widget _buildDateSelector() {
  //   return Card(
  //     margin: const EdgeInsets.all(16),
  //     child: Padding(
  //       padding: const EdgeInsets.all(16.0),
  //       child: Row(
  //         children: [
  //           const Icon(Icons.calendar_today, size: 20),
  //           const SizedBox(width: 8),
  //           const Text('Período: ', style: TextStyle(fontWeight: FontWeight.bold)),
  //           Expanded(
  //             child: TextButton(
  //               onPressed: _selectedChartType == ChartType.dailyConsumption || 
  //                         _selectedChartType == ChartType.monthlyConsumption
  //                   ? null // Desabilita para gráficos de consumo
  //                   : () => _selectDate(context),
  //               child: Text(
  //                 _getDateText(),
  //                 style: TextStyle(
  //                   fontSize: 16,
  //                   color: _selectedChartType == ChartType.dailyConsumption || 
  //                          _selectedChartType == ChartType.monthlyConsumption
  //                       ? Colors.grey
  //                       : Colors.blue,
  //                 ),
  //               ),
  //             ),
  //           ),
  //           if (_energyData.isNotEmpty || _sensorData.isNotEmpty)
  //             Text(
  //               _getDataPointText(),
  //               style: const TextStyle(
  //                 color: Colors.grey,
  //                 fontSize: 12,
  //               ),
  //             ),
  //         ],
  //       ),
  //     ),
  //   );
  // }
  Widget _buildDateSelector() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () {
                setState(() {
                  if (_selectedChartType == ChartType.dailyConsumption) {
                    // Para gráfico diário, subtrai 7 dias
                    _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                  } else if (_selectedChartType == ChartType.monthlyConsumption) {
                    // Para gráfico mensal, subtrai 1 mês
                    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1);
                  } else {
                    // Para outros gráficos, subtrai 1 dia
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                  }
                });
                _loadData();
              },
              tooltip: 'Período anterior',
              color: Colors.blue,
            ),
            
            Expanded(
              child: Column(
                children: [
                  Text(
                    _getDateText(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getDataPointText(),
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
              onPressed: () {
                DateTime now = DateTime.now();
                DateTime maxDate = now;
                
                // Definir data máxima baseada no tipo de gráfico
                if (_selectedChartType == ChartType.dailyConsumption) {
                  // Para gráfico diário, o último dia da semana não pode passar de hoje
                  DateTime semanaSeguinte = _selectedDate.add(const Duration(days: 7));
                  if (semanaSeguinte.isBefore(now) || 
                      semanaSeguinte.difference(now).inDays.abs() <= 1) {
                    setState(() {
                      _selectedDate = semanaSeguinte;
                    });
                    _loadData();
                  }
                } else if (_selectedChartType == ChartType.monthlyConsumption) {
                  // Para gráfico mensal, verificar se não passa do mês atual
                  DateTime proximoMes = DateTime(_selectedDate.year, _selectedDate.month + 1);
                  if (proximoMes.isBefore(now) || 
                      (proximoMes.year == now.year && proximoMes.month <= now.month)) {
                    setState(() {
                      _selectedDate = proximoMes;
                    });
                    _loadData();
                  }
                } else if (_selectedDate.isBefore(DateTime(now.year, now.month, now.day))) {
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                  });
                  _loadData();
                }
              },
              tooltip: 'Próximo período',
              color: _getNextButtonColor(),
            ),
          ],
        ),
      ),
    );
  }

  Color _getNextButtonColor() {
    DateTime now = DateTime.now();
    
    if (_selectedChartType == ChartType.dailyConsumption) {
      DateTime semanaSeguinte = _selectedDate.add(const Duration(days: 7));
      if (semanaSeguinte.isBefore(now) || 
          semanaSeguinte.difference(now).inDays.abs() <= 1) {
        return Colors.blue;
      }
    } else if (_selectedChartType == ChartType.monthlyConsumption) {
      DateTime proximoMes = DateTime(_selectedDate.year, _selectedDate.month + 1);
      if (proximoMes.isBefore(now) || 
          (proximoMes.year == now.year && proximoMes.month <= now.month)) {
        return Colors.blue;
      }
    } else if (_selectedDate.isBefore(DateTime(now.year, now.month, now.day))) {
      return Colors.blue;
    }
    
    return Colors.grey;
  }

  // String _getDateText() {
  //   switch (_selectedChartType) {
  //     case ChartType.dailyConsumption:
  //       return 'Últimos 7 dias';
  //     case ChartType.monthlyConsumption:
  //       return 'Últimos 12 meses';
  //     default:
  //       return DateFormat('dd/MM/yyyy').format(_selectedDate);
  //   }
  // }
  String _getDateText() {
    switch (_selectedChartType) {
      case ChartType.dailyConsumption:
        final inicio = _selectedDate.subtract(Duration(days: 6));
        return '${DateFormat('dd/MM').format(inicio)} - ${DateFormat('dd/MM').format(_selectedDate)}';
      case ChartType.monthlyConsumption:
        return '${DateFormat('MMM/yyyy').format(_selectedDate)}';
      default:
        return DateFormat('dd/MM/yyyy').format(_selectedDate);
    }
  }

  String _getDataPointText() {
    switch (_selectedChartType) {
      case ChartType.luminosity:
        return '${_sensorData.length} pontos';
      case ChartType.dailyConsumption:
      case ChartType.monthlyConsumption:
        return '${_energyData.length} períodos';
      default:
        return '${_energyData.length} pontos';
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadData();
    }
  }

  Widget _buildSettingsButton() {
    return FloatingActionButton(
      onPressed: () {
        setState(() {
          _showSettings = !_showSettings;
        });
      },
      backgroundColor: Colors.blue,
      child: Icon(
        _showSettings ? Icons.close : Icons.settings,
        color: Colors.white,
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: _showSettings ? 16 : -300,
      top: 100,
      child: Card(
        elevation: 8,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configurações do Gráfico',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Seleção do tipo de gráfico
              const Text(
                'Tipo de Gráfico:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ChartType.values.map((type) {
                  return FilterChip(
                    label: Text(_getChartTypeLabel(type)),
                    selected: _selectedChartType == type,
                    onSelected: (selected) {
                      setState(() {
                        _selectedChartType = type;
                      });
                      _loadData();
                    },
                    backgroundColor: Colors.grey.shade200,
                    selectedColor: Colors.blue.shade100,
                    checkmarkColor: Colors.blue,
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              // Configurações específicas por tipo de gráfico
              if (_selectedChartType == ChartType.powerConsumption) ...[
                const Text(
                  'Exibir no Gráfico:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                
                _buildSettingsSwitch(
                  'Potência Total',
                  true,
                  (value) {}, // Sempre visível
                  enabled: false,
                ),
                _buildSettingsSwitch(
                  'Zonas de Iluminação',
                  _showPowerZones,
                  (value) => setState(() => _showPowerZones = value),
                ),
                _buildSettingsSwitch(
                  'Tomadas',
                  _showPowerSockets,
                  (value) => setState(() => _showPowerSockets = value),
                ),
              ],
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              const Text(
                'Dicas de Navegação:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Toque duplo: Resetar zoom',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Text(
                '• Pinça: Zoom nos eixos',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Text(
                '• Arraste: Navegar no gráfico',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Text(
                '• Toque longo: Ver detalhes',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSwitch(String title, bool value, Function(bool) onChanged, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: value ? FontWeight.bold : FontWeight.normal,
                color: enabled ? Colors.black : Colors.grey,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  String _getChartTypeLabel(ChartType type) {
    switch (type) {
      case ChartType.luminosity:
        return '📊 Luminosidade';
      case ChartType.powerConsumption:
        return '⚡ Potência';
      case ChartType.usageTime:
        return '⏱️ Tempos de Uso';
      case ChartType.dailyConsumption:
        return '📈 Consumo Diário';
      case ChartType.monthlyConsumption:
        return '📊 Consumo Mensal';
    }
  }

  String _getChartTitle(ChartType type) {
    switch (type) {
      case ChartType.luminosity:
        return 'Luminosidade ao Longo do Dia';
      case ChartType.powerConsumption:
        return 'Consumo de Energia em Tempo Real';
      case ChartType.usageTime:
        return 'Tempo de Uso dos Dispositivos';
      case ChartType.dailyConsumption:
        return 'Consumo Diário de Energia (Últimos 7 Dias)';
      case ChartType.monthlyConsumption:
        return 'Consumo Mensal de Energia (Últimos 12 Meses)';
    }
  }

  Widget _buildSelectedChart() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Carregando dados...'),
          ],
        ),
      );
    }
    
    switch (_selectedChartType) {
      case ChartType.luminosity:
        return _buildLuminosityChart();
      case ChartType.powerConsumption:
        return _buildPowerConsumptionChart();
      case ChartType.usageTime:
        return _buildUsageTimeChart();
      case ChartType.dailyConsumption:
        return _buildDailyConsumptionChart();
      case ChartType.monthlyConsumption:
        return _buildMonthlyConsumptionChart();
    }
  }

  Widget _buildLuminosityChart() {
    if (_sensorData.isEmpty) return _buildEmptyState();
    
    return SfCartesianChart(
      title: ChartTitle(text: _getChartTitle(_selectedChartType)),
      legend: const Legend(isVisible: true, position: LegendPosition.top),
      tooltipBehavior: TooltipBehavior(enable: true),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        zoomMode: ZoomMode.x,
        enableSelectionZooming: true,
      ),
      trackballBehavior: TrackballBehavior(
        enable: true,
        tooltipSettings: const InteractiveTooltip(format: 'point.x : point.y'),
      ),
      primaryXAxis: DateTimeAxis(
        dateFormat: DateFormat('HH:mm'),
        title: const AxisTitle(text: 'Horário'),
        intervalType: DateTimeIntervalType.hours,
        interval: 2,
      ),
      primaryYAxis: NumericAxis(
        title: const AxisTitle(text: 'Luminosidade'),
      ),
      series: [
        LineSeries<SensorData, DateTime>(
          dataSource: _sensorData,
          xValueMapper: (SensorData data, _) => data.timestamp,
          yValueMapper: (SensorData data, _) => data.luminosidade.toDouble(),
          name: 'Luminosidade',
          color: Colors.orange,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
      ],
    );
  }

  Widget _buildPowerConsumptionChart() {
    if (_energyData.isEmpty) return _buildEmptyState();
    
    final List<CartesianSeries> series = [];

    // Potência Total (sempre visível)
    series.add(
      LineSeries<EnergyData, DateTime>(
        dataSource: _energyData,
        xValueMapper: (EnergyData data, _) => data.timestamp,
        yValueMapper: (EnergyData data, _) => data.powerTotal,
        name: 'Potência Total',
        color: Colors.red,
        markerSettings: const MarkerSettings(isVisible: true),
        width: 2,
      ),
    );

    // Zonas de Iluminação
    if (_showPowerZones) {
      series.addAll([
        LineSeries<EnergyData, DateTime>(
          dataSource: _energyData,
          xValueMapper: (EnergyData data, _) => data.timestamp,
          yValueMapper: (EnergyData data, _) => data.powerZone1,
          name: 'Zona 1',
          color: Colors.amber,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
        LineSeries<EnergyData, DateTime>(
          dataSource: _energyData,
          xValueMapper: (EnergyData data, _) => data.timestamp,
          yValueMapper: (EnergyData data, _) => data.powerZone2,
          name: 'Zona 2',
          color: Colors.orange,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
        LineSeries<EnergyData, DateTime>(
          dataSource: _energyData,
          xValueMapper: (EnergyData data, _) => data.timestamp,
          yValueMapper: (EnergyData data, _) => data.powerZone3,
          name: 'Zona 3',
          color: Colors.deepOrange,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
      ]);
    }

    // Tomadas
    if (_showPowerSockets) {
      series.addAll([
        LineSeries<EnergyData, DateTime>(
          dataSource: _energyData,
          xValueMapper: (EnergyData data, _) => data.timestamp,
          yValueMapper: (EnergyData data, _) => data.powerTomada1,
          name: 'Tomada 1',
          color: Colors.blue,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
        LineSeries<EnergyData, DateTime>(
          dataSource: _energyData,
          xValueMapper: (EnergyData data, _) => data.timestamp,
          yValueMapper: (EnergyData data, _) => data.powerTomada2,
          name: 'Tomada 2',
          color: Colors.lightBlue,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
      ]);
    }

    return SfCartesianChart(
      title: ChartTitle(text: _getChartTitle(_selectedChartType)),
      legend: const Legend(
        isVisible: true,
        position: LegendPosition.top,
        overflowMode: LegendItemOverflowMode.wrap,
      ),
      tooltipBehavior: TooltipBehavior(enable: true),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        zoomMode: ZoomMode.x,
        enableSelectionZooming: true,
        selectionRectColor: Colors.blue.withOpacity(0.3),
        selectionRectBorderColor: Colors.blue,
        selectionRectBorderWidth: 2,
      ),
      trackballBehavior: TrackballBehavior(
        enable: true,
        tooltipSettings: const InteractiveTooltip(format: 'series.name : point.y W'),
      ),
      primaryXAxis: DateTimeAxis(
        dateFormat: DateFormat('HH:mm'),
        title: const AxisTitle(text: 'Horário'),
        intervalType: DateTimeIntervalType.hours,
        interval: 2,
      ),
      primaryYAxis: NumericAxis(
        title: const AxisTitle(text: 'Potência (W)'),
      ),
      series: series,
    );
  }

  Widget _buildUsageTimeChart() {
    if (_energyData.isEmpty) return _buildEmptyState();
    
    final lastData = _energyData.isNotEmpty ? _energyData.last : EnergyData(
      timestamp: DateTime.now(),
      powerTotal: 0, powerZone1: 0, powerZone2: 0, powerZone3: 0,
      powerTomada1: 0, powerTomada2: 0, consumptionTotal: 0,
      timeZone1: 0, timeZone2: 0, timeZone3: 0,
      timeTomada1: 0, timeTomada2: 0, timePresence: 0,
    );
    
    final List<ChartData> usageData = [
      ChartData('Presença', lastData.timePresence / 3600, Colors.orange),
      ChartData('Zona 1', lastData.timeZone1 / 3600, Colors.amber),
      ChartData('Zona 2', lastData.timeZone2 / 3600, Colors.orange),
      ChartData('Zona 3', lastData.timeZone3 / 3600, Colors.deepOrange),
      ChartData('Tomada 1', lastData.timeTomada1 / 3600, Colors.blue),
      ChartData('Tomada 2', lastData.timeTomada2 / 3600, Colors.lightBlue),
    ];
    
    return SfCartesianChart(
      title: const ChartTitle(text: 'Tempo de Uso Acumulado (Horas)'),
      primaryXAxis: CategoryAxis(),
      primaryYAxis: NumericAxis(title: const AxisTitle(text: 'Horas')),
      tooltipBehavior: TooltipBehavior(enable: true),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        zoomMode: ZoomMode.x,
      ),
      series: [
        BarSeries<ChartData, String>(
          dataSource: usageData,
          xValueMapper: (ChartData data, _) => data.category,
          yValueMapper: (ChartData data, _) => data.value,
          name: 'Horas de Uso',
          color: Colors.blue,
          dataLabelSettings: const DataLabelSettings(
            isVisible: true,
            labelPosition: ChartDataLabelPosition.outside,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyConsumptionChart() {
    if (_energyData.isEmpty) return _buildEmptyState();
    
    // Converter os dados para o formato de gráfico de barras
    final List<ChartData> chartData = _energyData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final date = DateTime.now().subtract(Duration(days: 6 - index));
      final dayName = _getWeekdayAbbreviation(date.weekday);
      
      return ChartData(
        dayName,
        data.consumptionTotal / 1000,
        _getDayColor(date),
      );
    }).toList();
    
    return SfCartesianChart(
      title: ChartTitle(text: 'Consumo Diário de Energia (kWh)'),
      primaryXAxis: CategoryAxis(
        title: const AxisTitle(text: 'Dias da Semana'),
      ),
      primaryYAxis: NumericAxis(
        title: const AxisTitle(text: 'Consumo (kWh)'),
      ),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        zoomMode: ZoomMode.x,
        enableSelectionZooming: true,
      ),
      tooltipBehavior: TooltipBehavior(
        enable: true,
        // CORREÇÃO: Usar parâmetro correto no builder
        builder: (data, point, series, pointIndex, seriesIndex) {
          final value = point.y as double;
          final valorMonetario = value * _valorKwh;
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${point.x}', // CORREÇÃO: point.x está acessível aqui
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('${value.toStringAsFixed(2)} kWh'),
                Text('$_moeda ${valorMonetario.toStringAsFixed(2)}'),
              ],
            ),
          );
        },
      ),
      series: [
        ColumnSeries<ChartData, String>(
          dataSource: chartData,
          xValueMapper: (ChartData data, _) => data.category,
          yValueMapper: (ChartData data, _) => data.value,
          name: 'Consumo Diário',
          color: Colors.green,
          dataLabelSettings: const DataLabelSettings(
            isVisible: true,
            labelPosition: ChartDataLabelPosition.outside,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyConsumptionChart() {
    if (_energyData.isEmpty) return _buildEmptyState();
    
    // Converter os dados para gráfico de barras horizontais
    final List<ChartData> chartData = _energyData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final monthIndex = 11 - index;
      final date = DateTime(DateTime.now().year, DateTime.now().month - monthIndex, 1);
      final monthName = _getMonthAbbreviation(date.month);
      
      return ChartData(
        monthName,
        data.consumptionTotal / 1000,
        _getMonthColor(date.month),
      );
    }).toList();
    
    return SfCartesianChart(
      title: ChartTitle(text: 'Consumo Mensal de Energia (kWh)'),
      primaryXAxis: CategoryAxis(
        title: const AxisTitle(text: 'Meses'),
        labelRotation: 45,
      ),
      primaryYAxis: NumericAxis(
        title: const AxisTitle(text: 'Consumo (kWh)'),
      ),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        enableDoubleTapZooming: true,
        zoomMode: ZoomMode.x,
        enableSelectionZooming: true,
      ),
      tooltipBehavior: TooltipBehavior(
        enable: true,
        // CORREÇÃO: Usar parâmetro correto no builder
        builder: (data, point, series, pointIndex, seriesIndex) {
          final value = point.y as double;
          final valorMonetario = value * _valorKwh;
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${point.x}', // CORREÇÃO: point.x está acessível aqui
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('${value.toStringAsFixed(2)} kWh'),
                Text('$_moeda ${valorMonetario.toStringAsFixed(2)}'),
              ],
            ),
          );
        },
      ),
      series: [
        BarSeries<ChartData, String>(
          dataSource: chartData,
          xValueMapper: (ChartData data, _) => data.category,
          yValueMapper: (ChartData data, _) => data.value,
          name: 'Consumo Mensal',
          color: Colors.purple,
          dataLabelSettings: const DataLabelSettings(
            isVisible: true,
            labelPosition: ChartDataLabelPosition.inside,
          ),
          width: 0.6,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Nenhum dado disponível',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Os dados aparecerão aqui automaticamente\nconforme o sistema opera',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gráficos Analíticos'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildDateSelector(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _buildSelectedChart(),
                ),
              ),
            ],
          ),
          
          // Painel de configurações
          _buildSettingsPanel(),
        ],
      ),
      floatingActionButton: _buildSettingsButton(),
    );
  }
}

class ChartData {
  final String category;
  final double value;
  final Color color;
  
  ChartData(this.category, this.value, this.color);
}