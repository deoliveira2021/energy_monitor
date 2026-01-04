import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService {
  MqttServerClient? client;
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  final String server = 'broker.hivemq.com';
  final int port = 1883;
  
  final String topicStatus = 'energia/status';
  final String topicControl = 'energia/control';
  final String topicSensores = 'energia/sensores';
  final String topicEnergia = 'energia/consumo';
  final String topicConfig = 'energia/config'; // NOVO tópico para configurações

  Timer? _autoUpdateTimer;

  Future<bool> connect() async {
    try {
      String clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
      client = MqttServerClient(server, clientId);
      
      client!.port = port;
      client!.keepAlivePeriod = 60;
      client!.onDisconnected = _onDisconnected;
      client!.logging(on: true);
      client!.secure = false;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      
      client!.connectionMessage = connMessage;
      
      print('🔄 [FLUTTER] Conectando ao MQTT: $server:$port');
      
      await client!.connect();
      
      if (client!.connectionStatus?.state == MqttConnectionState.connected) {
        print('✅ [FLUTTER] Conectado ao MQTT com sucesso!');
        print('📡 [FLUTTER] ClientID: $clientId');
        
        // Subscrever aos tópicos
        client!.subscribe(topicStatus, MqttQos.atMostOnce);
        client!.subscribe(topicSensores, MqttQos.atMostOnce);
        client!.subscribe(topicEnergia, MqttQos.atMostOnce);
        client!.subscribe(topicConfig, MqttQos.atMostOnce); // NOVA inscrição
        
        print('✅ [FLUTTER] Inscrito nos tópicos:');
        print('   - $topicStatus');
        print('   - $topicSensores');
        print('   - $topicEnergia');
        print('   - $topicConfig');
        
        _setupMessageListener();
        _startAutoUpdate();
        
        return true;
      } else {
        print('❌ [FLUTTER] Falha na conexão MQTT');
        return false;
      }
    } catch (e) {
      print('❌ [FLUTTER] Exception na conexão MQTT: $e');
      return false;
    }
  }

  void _startAutoUpdate() {
    _autoUpdateTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isConnected) {
        print('🔄 [FLUTTER] Solicitando atualização de status...');
        requestStatusUpdate();
      }
    });
  }

  void _stopAutoUpdate() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
  }

  void requestStatusUpdate() {
    publishMessage(topicControl, 'atualizar_status');
  }

  void _setupMessageListener() {
    print('👂 [FLUTTER] Iniciando listener MQTT...');
    
    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      try {
        final MqttPublishMessage message = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(message.payload.message);
        final topic = messages[0].topic;
        
        print('📨 [FLUTTER] Mensagem MQTT recebida:');
        print('   Tópico: $topic');
        print('   Payload: $payload');
        
        if (topic == topicStatus) {
          _processStatusMessage(payload);
        } else if (topic == topicSensores) {
          _processSensorMessage(payload);
        } else if (topic == topicEnergia) {
          _processEnergyMessage(payload);
        } else if (topic == topicConfig) {
          _processConfigMessage(payload);
        }
      } catch (e) {
        print('❌ [FLUTTER] Erro ao processar mensagem: $e');
      }
    }, onError: (error) {
      print('❌ [FLUTTER] Erro no listener MQTT: $error');
    });
  }

  void _processStatusMessage(String payload) {
    try {
      print('🔧 [FLUTTER] Processando STATUS: $payload');
      
      Map<String, dynamic> data = {};
      
      List<String> pairs = payload.split(',');
      
      for (String pair in pairs) {
        List<String> keyValue = pair.split(':');
        if (keyValue.length == 2) {
          String key = keyValue[0].trim();
          String value = keyValue[1].trim();
          
          print('   🔍 Chave: $key, Valor: $value');
          
          switch (key) {
            case 'L':
              data['luminosidade'] = int.tryParse(value) ?? 0;
              break;
            case 'P':
              data['presenca'] = value == '1';
              break;
            case 'M':
              data['modo_auto'] = value == 'A';
              break;
            case 'Z1':
              data['zona1'] = value == '1';
              break;
            case 'Z2':
              data['zona2'] = value == '1';
              break;
            case 'Z3':
              data['zona3'] = value == '1';
              break;
            case 'T1':
              data['tomada1'] = value == '1';
              break;
            case 'T2':
              data['tomada2'] = value == '1';
              break;
          }
        }
      }
      
      print('✅ [FLUTTER] Dados processados: $data');
      _messageController.add(data);
    } catch (e) {
      print('❌ [FLUTTER] Erro ao processar status: $e');
    }
  }

  void _processSensorMessage(String payload) {
    try {
      print('🔧 [FLUTTER] Processando SENSORES: $payload');
      
      Map<String, dynamic> data = {};
      
      List<String> pairs = payload.split(',');
      
      for (String pair in pairs) {
        List<String> keyValue = pair.split(':');
        if (keyValue.length == 2) {
          String key = keyValue[0].trim();
          String value = keyValue[1].trim();
          
          if (key == 'L') {
            data['luminosidade'] = int.tryParse(value) ?? 0;
          } else if (key == 'P') {
            data['presenca'] = value == '1';
          }
        }
      }
      
      print('✅ [FLUTTER] Sensores processados: $data');
      _messageController.add(data);
    } catch (e) {
      print('❌ [FLUTTER] Erro ao processar sensores: $e');
    }
  }

  void _processEnergyMessage(String payload) {
    try {
      print('⚡ [FLUTTER] Processando DADOS DE ENERGIA: $payload');
      
      Map<String, dynamic> dadosEnergia = {};
      
      List<String> pairs = payload.split(',');
      
      for (String pair in pairs) {
        List<String> keyValue = pair.split(':');
        if (keyValue.length == 2) {
          String key = keyValue[0].trim();
          String value = keyValue[1].trim();
          
          switch (key) {
            case 'PZ1':
              dadosEnergia['potencia_zona1'] = double.tryParse(value) ?? 0.0;
              break;
            case 'PZ2':
              dadosEnergia['potencia_zona2'] = double.tryParse(value) ?? 0.0;
              break;
            case 'PZ3':
              dadosEnergia['potencia_zona3'] = double.tryParse(value) ?? 0.0;
              break;
            case 'PT1':
              dadosEnergia['potencia_tomada1'] = double.tryParse(value) ?? 0.0;
              break;
            case 'PT2':
              dadosEnergia['potencia_tomada2'] = double.tryParse(value) ?? 0.0;
              break;
            case 'PTOTAL':
              dadosEnergia['potencia_total'] = double.tryParse(value) ?? 0.0;
              break;
            case 'CONSUMO':
              dadosEnergia['consumo_total'] = double.tryParse(value) ?? 0.0;
              break;
            case 'VALOR':
              dadosEnergia['valor_consumo'] = double.tryParse(value) ?? 0.0;
              break;
            case 'MOEDA':
              dadosEnergia['moeda'] = value;
              break;
            case 'TZ1':
              dadosEnergia['tempo_zona1'] = double.tryParse(value) ?? 0.0;
              break;
            case 'TZ2':
              dadosEnergia['tempo_zona2'] = double.tryParse(value) ?? 0.0;
              break;
            case 'TZ3':
              dadosEnergia['tempo_zona3'] = double.tryParse(value) ?? 0.0;
              break;
            case 'TT1':
              dadosEnergia['tempo_tomada1'] = double.tryParse(value) ?? 0.0;
              break;
            case 'TT2':
              dadosEnergia['tempo_tomada2'] = double.tryParse(value) ?? 0.0;
              break;
            case 'TPRES':
              dadosEnergia['tempo_presenca'] = double.tryParse(value) ?? 0.0;
              break;
          }
        }
      }
      
      print('✅ [FLUTTER] Dados de energia processados: $dadosEnergia');
      
      _messageController.add({
        'tipo': 'energia',
        'dados': dadosEnergia,
        'timestamp': DateTime.now().millisecondsSinceEpoch
      });
      
    } catch (e) {
      print('❌ [FLUTTER] Erro ao processar dados de energia: $e');
    }
  }

  void _processConfigMessage(String payload) {
    try {
      print('⚙️ [FLUTTER] Processando CONFIGURAÇÃO: $payload');
      // Aqui você pode processar respostas de configuração se necessário
    } catch (e) {
      print('❌ [FLUTTER] Erro ao processar configuração: $e');
    }
  }

  // Métodos de controle
  void setModoAutomatico() {
    print('🎯 [FLUTTER] Enviando: modo_auto');
    publishMessage(topicControl, 'modo_auto');
  }

  void setModoManual() {
    print('🎯 [FLUTTER] Enviando: modo_manual');
    publishMessage(topicControl, 'modo_manual');
  }

  void toggleZona1(bool ligar) {
    String comando = ligar ? 'zona1_on' : 'zona1_off';
    print('🎯 [FLUTTER] Enviando: $comando');
    publishMessage(topicControl, comando);
  }

  void toggleZona2(bool ligar) {
    String comando = ligar ? 'zona2_on' : 'zona2_off';
    print('🎯 [FLUTTER] Enviando: $comando');
    publishMessage(topicControl, comando);
  }

  void toggleZona3(bool ligar) {
    String comando = ligar ? 'zona3_on' : 'zona3_off';
    print('🎯 [FLUTTER] Enviando: $comando');
    publishMessage(topicControl, comando);
  }

  void toggleTomada1(bool ligar) {
    String comando = ligar ? 'tomada1_on' : 'tomada1_off';
    print('🎯 [FLUTTER] Enviando: $comando');
    publishMessage(topicControl, comando);
  }

  void toggleTomada2(bool ligar) {
    String comando = ligar ? 'tomada2_on' : 'tomada2_off';
    print('🎯 [FLUTTER] Enviando: $comando');
    publishMessage(topicControl, comando);
  }

  // NOVOS métodos para controle de presença
  void ativarPresenca() {
    print('🎯 [FLUTTER] Enviando: presenca_on');
    publishMessage(topicControl, 'presenca_on');
  }

  void desativarPresenca() {
    print('🎯 [FLUTTER] Enviando: presenca_off');
    publishMessage(topicControl, 'presenca_off');
  }

  // NOVOS métodos para ligar/desligar todos
  void ligarTodos() {
    print('🎯 [FLUTTER] Enviando: ligar_todos');
    publishMessage(topicControl, 'ligar_todos');
  }

  void desligarTodos() {
    print('🎯 [FLUTTER] Enviando: desligar_todos');
    publishMessage(topicControl, 'desligar_todos');
  }

  // NOVO método para enviar configurações
  void enviarConfiguracao(String key, String value) {
    String config = '$key:$value';
    print('🎯 [FLUTTER] Enviando configuração: $config');
    publishMessage(topicConfig, config);
  }

  // NOVOS métodos para calibração
  void iniciarCalibracao(String sensor, double referencia) {
    String comando = 'calibrar_iniciar $sensor $referencia';
    print('🎯 [FLUTTER] Enviando comando de calibração: $comando');
    publishMessage('energia/calibracao', comando);
  }

  void concluirCalibracao() {
    print('🎯 [FLUTTER] Concluindo calibração');
    publishMessage('energia/calibracao', 'calibrar_concluir');
  }

  void cancelarCalibracao() {
    print('🎯 [FLUTTER] Cancelando calibração');
    publishMessage('energia/calibracao', 'calibrar_cancelar');
  }

  void publishMessage(String topic, String message) {
    if (client != null && client!.connectionStatus?.state == MqttConnectionState.connected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(message);
        client!.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
        print('📤 [FLUTTER] Mensagem PUBLICADA: $topic - $message');
      } catch (e) {
        print('❌ [FLUTTER] Erro ao publicar mensagem: $e');
      }
    } else {
      print('❌ [FLUTTER] Cliente MQTT não conectado');
    }
  }

  void disconnect() {
    _stopAutoUpdate();
    client?.disconnect();
    client = null;
    print('🔌 [FLUTTER] Desconectado do MQTT');
  }

  void _onDisconnected() {
    print('🔌 [FLUTTER] Desconectado do broker MQTT');
    _messageController.add({'error': 'Desconectado', 'connected': false});
  }

  bool get isConnected {
    return client?.connectionStatus?.state == MqttConnectionState.connected;
  }

  void dispose() {
    _stopAutoUpdate();
    disconnect();
    _messageController.close();
  }
}