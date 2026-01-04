import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  
  // Configurações de energia
  double _tensaoRede = 220.0;
  double _valorKwh = 1.00;
  String _moeda = 'R\$';
  bool _notificacoesAtivas = true;
  bool _modoEscuro = false;
  bool _autoConectar = true;
  
  final List<String> _moedasDisponiveis = ['R\$', 'US\$', '€', '£', '¥'];
  final List<double> _tensoesDisponiveis = [110.0, 127.0, 220.0, 230.0, 240.0];

  final _valorKwhController = TextEditingController();
  final _tensaoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final settings = await _databaseService.getAllSettings();
      
      setState(() {
        _tensaoRede = double.tryParse(settings['tensao_rede'] ?? '220.0') ?? 220.0;
        _valorKwh = double.tryParse(settings['valor_kwh'] ?? '1.00') ?? 1.00;
        _moeda = settings['moeda'] ?? 'R\$';
        _notificacoesAtivas = settings['notificacoes'] == 'true';
        _modoEscuro = settings['modo_escuro'] == 'true';
        _autoConectar = settings['auto_conectar'] == 'true';
      });
      
      _valorKwhController.text = _valorKwh.toStringAsFixed(2);
      _tensaoController.text = _tensaoRede.toStringAsFixed(0);
      
      print('✅ Configurações carregadas');
    } catch (e) {
      print('❌ Erro ao carregar configurações: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _salvarTodasConfiguracoes,
            tooltip: 'Salvar todas as configurações',
          ),
        ],
      ),
      body: _buildSettingsContent(),
    );
  }

  Widget _buildSettingsContent() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSettingsSection(
          '⚡ Configurações de Energia',
          Icons.bolt,
          Colors.amber,
          [
            _buildTensaoSetting(),
            const SizedBox(height: 16),
            _buildValorKwhSetting(),
            const SizedBox(height: 16),
            _buildMoedaSetting(),
          ],
        ),
        
        const SizedBox(height: 24),
        
        _buildSettingsSection(
          '📱 Configurações do App',
          Icons.smartphone,
          Colors.blue,
          [
            _buildSwitchSetting(
              'Notificações',
              _notificacoesAtivas,
              Icons.notifications,
              (value) {
                setState(() => _notificacoesAtivas = value);
                _databaseService.setSetting('notificacoes', value.toString());
              },
            ),
            
            const SizedBox(height: 12),
            
            _buildSwitchSetting(
              'Modo Escuro',
              _modoEscuro,
              Icons.dark_mode,
              (value) {
                setState(() => _modoEscuro = value);
                _databaseService.setSetting('modo_escuro', value.toString());
              },
            ),
            
            const SizedBox(height: 12),
            
            _buildSwitchSetting(
              'Conectar Automaticamente',
              _autoConectar,
              Icons.wifi,
              (value) {
                setState(() => _autoConectar = value);
                _databaseService.setSetting('auto_conectar', value.toString());
              },
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        _buildSettingsSection(
          '📊 Informações do Sistema',
          Icons.info,
          Colors.green,
          [
            _buildInfoItem('Versão do App', '2.0.0'),
            _buildInfoItem('Última Atualização', _getCurrentDate()),
            _buildInfoItem('Configurações Salvas', '6'),
          ],
        ),
        
        const SizedBox(height: 32),
        
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _resetarConfiguracoes,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar Padrões'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _salvarTodasConfiguracoes,
                icon: const Icon(Icons.save),
                label: const Text('Salvar Tudo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsSection(String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
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
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTensaoSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tensão da Rede',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tensaoController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Digite a tensão',
                  prefixIcon: const Icon(Icons.bolt),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  final tensao = double.tryParse(value) ?? 220.0;
                  setState(() => _tensaoRede = tensao);
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<double>(
              value: _tensaoRede,
              items: _tensoesDisponiveis.map((tensao) {
                return DropdownMenuItem<double>(
                  value: tensao,
                  child: Text('${tensao.toStringAsFixed(0)}V'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _tensaoRede = value);
                  _tensaoController.text = value.toStringAsFixed(0);
                  _databaseService.setSetting('tensao_rede', value.toStringAsFixed(1));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tensão atual: ${_tensaoRede.toStringAsFixed(0)}V',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildValorKwhSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Valor do kWh',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _valorKwhController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Digite o valor do kWh',
            prefixIcon: const Icon(Icons.monetization_on),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (value) {
            final valor = double.tryParse(value) ?? 1.00;
            setState(() => _valorKwh = valor);
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Valor atual: $_moeda ${_valorKwh.toStringAsFixed(2)}/kWh',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildMoedaSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Moeda',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _moeda,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.currency_exchange),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          items: _moedasDisponiveis.map((moeda) {
            return DropdownMenuItem<String>(
              value: moeda,
              child: Text(moeda),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _moeda = value);
              _databaseService.setSetting('moeda', value);
            }
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Moeda atual: $_moeda',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting(String label, bool value, IconData icon, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 24, color: Colors.grey.shade700),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        FlutterSwitch(
          value: value,
          onToggle: onChanged,
          activeColor: Colors.blue,
          width: 50,
          height: 25,
          toggleSize: 23,
        ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  Future<void> _salvarTodasConfiguracoes() async {
    try {
      await _databaseService.setSetting('tensao_rede', _tensaoRede.toStringAsFixed(1));
      await _databaseService.setSetting('valor_kwh', _valorKwh.toStringAsFixed(2));
      await _databaseService.setSetting('moeda', _moeda);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Todas as configurações foram salvas!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      
      print('✅ Configurações salvas:');
      print('   - Tensão: ${_tensaoRede}V');
      print('   - kWh: $_moeda ${_valorKwh.toStringAsFixed(2)}');
      print('   - Moeda: $_moeda');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar configurações: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _resetarConfiguracoes() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar Configurações'),
        content: const Text('Tem certeza que deseja restaurar todas as configurações para os valores padrão?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                // Restaurar valores padrão
                setState(() {
                  _tensaoRede = 220.0;
                  _valorKwh = 1.00;
                  _moeda = 'R\$';
                  _notificacoesAtivas = true;
                  _modoEscuro = false;
                  _autoConectar = true;
                });
                
                _valorKwhController.text = '1.00';
                _tensaoController.text = '220';
                
                await _salvarTodasConfiguracoes();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Configurações restauradas com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Erro ao restaurar configurações: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }
}