#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_GFX.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <WebServer.h>
#include <EEPROM.h>

// ========== CONFIGURAÇÕES MQTT ==========
const char* mqtt_server = "broker.hivemq.com";

// Tópicos MQTT
const char* TOPIC_STATUS = "energia/status";
const char* TOPIC_CONTROL = "energia/control";
const char* TOPIC_SENSORES = "energia/sensores";
const char* TOPIC_ENERGIA = "energia/consumo";
const char* TOPIC_CALIBRACAO = "energia/calibracao";

// ========== CONFIGURAÇÃO DE PINOS ==========
#define RELE_ZONA_1 27    // Lâmpadas Zona 1 - LOW = LIGADO
#define RELE_ZONA_2 26    // Lâmpadas Zona 2 - LOW = LIGADO
#define RELE_ZONA_3 25    // Lâmpadas Zona 3 - LOW = LIGADO
#define RELE_TOMADA_1 33  // Tomada 1 - LOW = LIGADO

#define SENSOR_ZONA_1 36  // GPIO36 - ADC1_CH0
#define SENSOR_ZONA_2 39  // GPIO39 - ADC1_CH3
#define SENSOR_ZONA_3 32  // GPIO32 - ADC1_CH4
#define SENSOR_TOMADA_1 35 // GPIO35 - ADC1_CH7

#define LDR_PIN 34        // GPIO34 - ADC1_CH6
#define BUTTON_PRESENCA 19 // Botão de presença

#define LED_VERDE 2
#define LED_AMARELO 4
#define LED_VERMELHO 5

// ========== CONSTANTES CALIBRADAS ==========
const float VREF_ESP32 = 3.3;          // Tensão de referência do ESP32
const float ADC_MAX = 4095.0;          // Máximo valor ADC (12 bits)
float TENSAO_REDE = 220.0;             // Tensão da rede elétrica (ajustável)

// Valor calibrado previamente - NÃO ALTERAR!
const float CORRECAO_GLOBAL_FIXO = 0.3702;  // Calibrado com LED 9W
float CORRECAO_GLOBAL = CORRECAO_GLOBAL_FIXO;

// Divisores por canal
float DIVISORES[] = {1.612, 2.0, 1.612, 1.612};

// Sensibilidades dos sensores ACS712
const float SENS_5A = 0.185;           // 185mV/A para ACS712-05B
const float SENS_30A = 0.066;          // 66mV/A para ACS712-30A
const float THRESHOLD_CORRENTE = 0.005; // Limite mínimo de corrente (5mA)

// ========== LIMITES DE CALIBRAÇÃO ==========
const float LIMITE_CALIBRACAO_OK = 5.0;    // Máximo 5mA para considerar calibrado
const float LIMITE_ALERTA_CALIBRACAO = 10.0; // Alerta se > 10mA
const float LIMITE_DESCALIBRADO = 30.0;   // Considera descalibrado se > 30mA
const int MAX_TENTATIVAS_CALIBRACAO = 60; // Aumentado para 60 tentativas

// ========== ESTRUTURA DE DADOS DOS CANAIS ==========
typedef struct {
  uint8_t pinoSensor;      // Pino ADC do sensor
  uint8_t pinoRele;        // Pino do relé correspondente
  float sensibilidade;     // Sensibilidade do sensor (V/A)
  float adcZero;           // Valor ADC quando I=0A (calibrado)
  float adcZeroAtual;      // ADC Zero atual (ajustável)
  float corrente;          // Corrente atual (A)
  float potencia;          // Potência atual (W)
  float energia;           // Energia acumulada (Wh)
  unsigned long ultimaLeitura; // Timestamp última leitura
  bool calibrado;          // Sensor calibrado?
  bool precisaRecalibracao;// Precisa de recalibração?
  char nome[8];            // Nome do canal
  float offsetCorrente;    // Offset individual de corrente (A)
  float historico[10];     // Histórico para filtro
  int indiceHist;          // Índice do histórico
  float fatorCorrecao;     // Fator de correção individual
  bool releLigado;         // Estado do relé (lógico)
  bool fisicamenteLigado;  // Estado físico real (baseado no pino)
  unsigned long ultimaCalibracao; // Quando foi calibrado
  int tentativasCalibracao; // Número de tentativas de calibração
  float correnteMedia;     // Corrente média para calibração
} CanalSensor;

// Inicialização dos canais
CanalSensor canais[] = {
  {SENSOR_ZONA_1, RELE_ZONA_1, SENS_5A, 0, 0, 0, 0, 0, 0, false, true, "Z1", 0.0, {0}, 0, 1.0, false, false, 0, 0, 0},
  {SENSOR_ZONA_2, RELE_ZONA_2, SENS_5A, 0, 0, 0, 0, 0, 0, false, true, "Z2", 0.0, {0}, 0, 1.0, false, false, 0, 0, 0},
  {SENSOR_ZONA_3, RELE_ZONA_3, SENS_5A, 0, 0, 0, 0, 0, 0, false, true, "Z3", 0.0, {0}, 0, 1.0, false, false, 0, 0, 0},
  {SENSOR_TOMADA_1, RELE_TOMADA_1, SENS_30A, 0, 0, 0, 0, 0, 0, false, true, "T1", 0.0, {0}, 0, 1.0, false, false, 0, 0, 0}
};

const int NUM_CANAIS = sizeof(canais) / sizeof(canais[0]);

// ========== ESTRUTURAS EEPROM ==========
struct WiFiConfig {
  char ssid[32];
  char password[64];
  bool configured;
  unsigned long checksum;
};

struct DadosCalibracao {
  float adcZeros[NUM_CANAIS];      // ADC Zero de cada canal
  float offsets[NUM_CANAIS];       // Offsets individuais
  float correcaoGlobal;            // Correção global
  float divisores[NUM_CANAIS];     // Divisores por canal
  float fatoresCorrecao[NUM_CANAIS]; // Fatores individuais
  float tensaoRede;                // Tensão da rede
  bool calibrado;                  // Status da calibração
  unsigned long dataCalibracao;    // Data da calibração
  unsigned long checksum;          // Verificação de integridade
};

#define EEPROM_SIZE (sizeof(WiFiConfig) + sizeof(DadosCalibracao))
#define EEPROM_WIFI_ADDR 0
#define EEPROM_CALIB_ADDR sizeof(WiFiConfig)

// ========== VARIÁVEIS DO SISTEMA ==========
bool modoAutomatico = true;
bool presencaSimulada = false;
unsigned long ultimoAcionamento = 0;
const unsigned long tempoDesligamento = 30000; // 30 segundos

// Estados das zonas
bool zona1Ativa = false, zona2Ativa = false, zona3Ativa = false;
bool tomada1Ativa = false;

// Limites de luminosidade
int LIMITE_ZONA_1 = 2000;
int LIMITE_ZONA_2 = 1500;  
int LIMITE_ZONA_3 = 1200;

// Variável para luminosidade
int luminosidade = 0;

// ========== DISPLAY OLED ==========
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// Cores para display bicolor (0.96" azul/amarelo)
#define SSD1306_YELLOW 1  // Parte superior (normalmente amarela)
#define SSD1306_BLUE 2    // Parte inferior (normalmente azula)

// ========== CLIENTES ==========
WiFiClient espClient;
PubSubClient client(espClient);
WebServer server(80);

// ========== VARIÁVEIS DE TEMPO ==========
unsigned long tempoZona1 = 0, tempoZona2 = 0, tempoZona3 = 0;
unsigned long tempoTomada1 = 0;
unsigned long tempoPresenca = 0;
unsigned long ultimoTempoUpdate = 0;

// ========== VARIÁVEIS PARA PUBLICAÇÃO MQTT ==========
unsigned long lastSensorPublish = 0;
const unsigned long sensorPublishInterval = 10000;
unsigned long lastStatusPublish = 0;
const unsigned long statusPublishInterval = 15000;
unsigned long lastEnergyPublish = 0;
const unsigned long energyPublishInterval = 30000;

// ========== VARIÁVEIS DO BOTÃO ==========
volatile bool botaoPressionado = false;
volatile unsigned long ultimaInterrupcao = 0;
const unsigned long DEBOUNCE_INTERVAL = 50;
bool botaoEstadoAnterior = HIGH;
unsigned long tempoPressionamentoInicio = 0;

// ========== VARIÁVEIS DE CALIBRAÇÃO ==========
bool calibracaoEmAndamento = false;
bool calibracaoConcluida = false;
bool precisaCalibracaoInicial = true;
int tentativasCalibracaoTotal = 0;
unsigned long tempoInicioCalibracao = 0;

// ========== VARIÁVEIS WiFi ==========
bool wifiConfigured = false;
bool wifiConnected = false;
bool modoAPAtivo = false;
unsigned long wifiConnectStart = 0;
const unsigned long wifiConnectTimeout = 30000;

// ========== PÁGINA HTML COMPLETA PARA CONFIGURAÇÃO WI-FI ==========
const char* CONFIG_PAGE = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
  <title>Configuração WiFi - Sistema Energia</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { 
      font-family: Arial, sans-serif; 
      margin: 0;
      padding: 20px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
    }
    .container { 
      max-width: 400px; 
      margin: 0 auto; 
      background: white; 
      padding: 30px; 
      border-radius: 15px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
    }
    h1 { 
      color: #333; 
      text-align: center;
      margin-bottom: 30px;
    }
    .logo {
      text-align: center;
      font-size: 24px;
      font-weight: bold;
      color: #667eea;
      margin-bottom: 10px;
    }
    .form-group { 
      margin-bottom: 20px; 
    }
    label { 
      display: block; 
      margin-bottom: 8px; 
      font-weight: bold;
      color: #555;
    }
    input[type="text"], input[type="password"] { 
      width: 100%; 
      padding: 12px; 
      border: 2px solid #ddd; 
      border-radius: 8px; 
      box-sizing: border-box;
      font-size: 16px;
      transition: border-color 0.3s;
    }
    input[type="text"]:focus, input[type="password"]:focus { 
      border-color: #667eea;
      outline: none;
    }
    button { 
      width: 100%; 
      padding: 15px; 
      background: #667eea; 
      color: white; 
      border: none; 
      border-radius: 8px; 
      cursor: pointer; 
      font-size: 16px;
      font-weight: bold;
      transition: background 0.3s;
    }
    button:hover { 
      background: #764ba2; 
    }
    .secondary-btn {
      background: #6c757d;
      margin-top: 10px;
    }
    .secondary-btn:hover {
      background: #545b62;
    }
    .status { 
      padding: 15px; 
      margin: 20px 0; 
      border-radius: 8px; 
      text-align: center;
      font-weight: bold;
    }
    .success { 
      background: #d4edda; 
      color: #155724; 
      border: 1px solid #c3e6cb;
    }
    .error { 
      background: #f8d7da; 
      color: #721c24; 
      border: 1px solid #f5c6cb;
    }
    .info { 
      background: #d1ecf1; 
      color: #0c5460; 
      border: 1px solid #bee5eb;
    }
    .networks { 
      margin: 20px 0; 
      max-height: 200px;
      overflow-y: auto;
      border: 1px solid #ddd;
      border-radius: 8px;
      padding: 10px;
    }
    .network-item { 
      padding: 12px; 
      border-bottom: 1px solid #eee; 
      cursor: pointer;
      transition: background 0.2s;
    }
    .network-item:hover { 
      background: #f8f9fa; 
    }
    .network-item:last-child {
      border-bottom: none;
    }
    .signal-strength {
      float: right;
      color: #666;
      font-size: 12px;
    }
    .loading {
      text-align: center;
      color: #666;
      padding: 20px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">⚡ Sistema Energia</div>
    <h1>Configuração WiFi</h1>
    
    <div class="status info">
      💡 Conecte-se à sua rede WiFi
    </div>
    
    <div id="status"></div>
    
    <form id="wifiForm">
      <div class="form-group">
        <label for="ssid">Rede WiFi:</label>
        <input type="text" id="ssid" name="ssid" placeholder="Nome da sua rede WiFi" required>
      </div>
      
      <div class="form-group">
        <label for="password">Senha:</label>
        <input type="password" id="password" name="password" placeholder="Senha da rede WiFi">
      </div>
      
      <button type="submit">🔗 Conectar & Salvar</button>
    </form>
    
    <button onclick="scanNetworks()" class="secondary-btn">🔍 Buscar Redes WiFi</button>
    
    <div id="networks" class="networks">
      <div class="loading">Clique em "Buscar Redes WiFi" para ver as redes disponíveis</div>
    </div>
    
    <div style="text-align: center; margin-top: 20px; color: #666; font-size: 12px;">
      IP: 192.168.4.1 | Sistema Energia v10.0
    </div>
  </div>

  <script>
    document.getElementById('wifiForm').addEventListener('submit', function(e) {
      e.preventDefault();
      saveConfig();
    });

    function scanNetworks() {
      showStatus('🔍 Buscando redes WiFi...', 'info');
      
      fetch('/scan')
        .then(response => response.json())
        .then(data => {
          const networksDiv = document.getElementById('networks');
          
          if (data.networks && data.networks.length > 0) {
            networksDiv.innerHTML = '<div style="font-weight: bold; margin-bottom: 10px;">📶 Redes Disponíveis:</div>';
            
            data.networks.forEach(network => {
              const div = document.createElement('div');
              div.className = 'network-item';
              
              div.innerHTML = `
                📶 ${network.ssid} 
                <span class="signal-strength">${network.rssi} dBm</span>
              `;
              
              div.onclick = () => {
                document.getElementById('ssid').value = network.ssid;
                document.getElementById('password').focus();
                showStatus(`✅ Rede "${network.ssid}" selecionada`, 'success');
              };
              
              networksDiv.appendChild(div);
            });
            
            showStatus(`✅ ${data.networks.length} redes encontradas`, 'success');
          } else {
            networksDiv.innerHTML = '<div class="loading">❌ Nenhuma rede encontrada</div>';
            showStatus('❌ Nenhuma rede WiFi encontrada', 'error');
          }
        })
        .catch(error => {
          console.error('Erro:', error);
          showStatus('❌ Erro ao buscar redes', 'error');
        });
    }

    function saveConfig() {
      const ssid = document.getElementById('ssid').value.trim();
      const password = document.getElementById('password').value;
      
      if (!ssid) {
        showStatus('❌ Por favor, digite o nome da rede WiFi', 'error');
        return;
      }

      showStatus('💾 Salvando configuração...', 'info');

      const formData = new FormData();
      formData.append('ssid', ssid);
      formData.append('password', password);

      fetch('/save', {
        method: 'POST',
        body: formData
      })
      .then(response => response.text())
      .then(data => {
        showStatus('✅ ' + data, 'success');
        setTimeout(() => {
          showStatus('🔄 Reiniciando o sistema...', 'info');
        }, 2000);
      })
      .catch(error => {
        console.error('Erro:', error);
        showStatus('❌ Erro ao salvar configuração', 'error');
      });
    }

    function showStatus(message, type) {
      const statusDiv = document.getElementById('status');
      statusDiv.innerHTML = `<div class="status ${type}">${message}</div>`;
    }

    window.onload = function() {
      scanNetworks();
    };
  </script>
</body>
</html>
)rawliteral";

// ========== FUNÇÃO PARA LER LUMINOSIDADE ==========
int lerLuminosidade() {
  static unsigned long ultimaLeituraLDR = 0;
  static int ultimaLuminosidade = 0;
  static int historicoLDR[5] = {0};
  static int indiceLDR = 0;
  
  if (millis() - ultimaLeituraLDR > 500) {
    int leitura = analogRead(LDR_PIN);
    
    historicoLDR[indiceLDR] = leitura;
    indiceLDR = (indiceLDR + 1) % 5;
    
    int soma = 0;
    for(int i = 0; i < 5; i++) {
      soma += historicoLDR[i];
    }
    int media = soma / 5;
    
    if(abs(media - ultimaLuminosidade) > 50 || millis() - ultimaLeituraLDR > 5000) {
      ultimaLuminosidade = media;
    }
    
    ultimaLeituraLDR = millis();
  }
  
  return ultimaLuminosidade;
}

// ========== FUNÇÕES AUXILIARES ==========
unsigned long calcularChecksum(void* dados, size_t tamanho) {
  unsigned long sum = 0;
  uint8_t* bytes = (uint8_t*)dados;
  
  for(size_t i = 0; i < tamanho - sizeof(unsigned long); i++) {
    sum += bytes[i];
  }
  return sum;
}

// ========== FUNÇÕES DE LEITURA ADC ==========
float lerADCRaw(int canal, int amostras = 100) {
  long soma = 0;
  for(int i = 0; i < amostras; i++) {
    soma += analogRead(canais[canal].pinoSensor);
    delayMicroseconds(100);
  }
  return soma / (float)amostras;
}

// ========== ATUALIZAR ESTADO FÍSICO DOS RELÉS ==========
void atualizarEstadoFisicoReles() {
  for(int i = 0; i < NUM_CANAIS; i++) {
    // Verifica o estado real do pino do relé
    bool estadoPino = (digitalRead(canais[i].pinoRele) == LOW); // LOW = ligado
    canais[i].fisicamenteLigado = estadoPino;
    
    // Mantém consistência entre estado lógico e físico
    if (canais[i].releLigado != estadoPino) {
      canais[i].releLigado = estadoPino;
    }
  }
}

// ========== VERIFICA SE TUDO ESTÁ DESLIGADO ==========
bool tudoDesligadoFisicamente() {
  for(int i = 0; i < NUM_CANAIS; i++) {
    if (canais[i].fisicamenteLigado) {
      return false;
    }
  }
  return true;
}

// ========== CALIBRAÇÃO ZERO COM TENTATIVAS ==========
bool calibrarZeroCanal(int canal) {
  Serial.print("Calibrando zero do ");
  Serial.print(canais[canal].nome);
  Serial.print(" (Tentativa ");
  Serial.print(canais[canal].tentativasCalibracao + 1);
  Serial.println(")...");
  
  // Usa o valor CORRECAO_GLOBAL correto (0.3702)
  CORRECAO_GLOBAL = CORRECAO_GLOBAL_FIXO;
  
  // Coleta 500 amostras para melhor precisão
  float soma = 0;
  int amostrasValidas = 0;
  float minLeitura = 4096.0;
  float maxLeitura = 0.0;
  
  for(int i = 0; i < 500; i++) {
    float leitura = analogRead(canais[canal].pinoSensor);
    
    // Filtra leituras extremas
    if(leitura > 100 && leitura < 4000) {
      soma += leitura;
      amostrasValidas++;
      if(leitura < minLeitura) minLeitura = leitura;
      if(leitura > maxLeitura) maxLeitura = leitura;
    }
    delay(2);
  }
  
  if(amostrasValidas > 450) {
    float novoZero = soma / amostrasValidas;
    float variacao = maxLeitura - minLeitura;
    
    Serial.print("  ADC Zero: ");
    Serial.print(novoZero, 1);
    Serial.print(" | Variação: ");
    Serial.print(variacao, 1);
    Serial.print(" | Amostras: ");
    Serial.print(amostrasValidas);
    Serial.print("/500");
    
    // Se variação muito grande, pode indicar ruído
    if(variacao > 100.0) {
      Serial.println(" ⚠️  (ruído alto)");
      return false;
    }
    
    canais[canal].adcZero = novoZero;
    canais[canal].adcZeroAtual = novoZero;
    canais[canal].ultimaCalibracao = millis();
    canais[canal].tentativasCalibracao++;
    
    Serial.println(" ✅");
    return true;
  } else {
    Serial.println("  ❌ Falha - muitas leituras inválidas");
    return false;
  }
}

// ========== FUNÇÃO PRINCIPAL DE CÁLCULO DE CORRENTE ==========
float calcularCorrente(int canal, int amostras = 100) {
  if(!canais[canal].calibrado) {
    return 0.0;
  }
  
  float adcMedio = lerADCRaw(canal, amostras);
  float diferencaADC = adcMedio - canais[canal].adcZero;
  
  // Ignora ruído muito baixo
  if(fabs(diferencaADC) < 1.0) {
    return 0.0;
  }
  
  // Cálculo considerando divisor de tensão e CORRECAO_GLOBAL = 0.3702
  float tensaoADC = diferencaADC * (VREF_ESP32 / ADC_MAX);
  float tensaoACS = tensaoADC / DIVISORES[canal];
  float corrente = tensaoACS / canais[canal].sensibilidade;
  
  // Aplica correção global (0.3702) e fator individual
  corrente = corrente * CORRECAO_GLOBAL * canais[canal].fatorCorrecao;
  
  // Valor absoluto
  corrente = fabs(corrente);
  
  // Threshold para evitar ruído
  if(corrente < THRESHOLD_CORRENTE) {
    return 0.0;
  }
  
  return corrente;
}

// ========== FILTRO DE MÉDIA MÓVEL ==========
float lerCorrenteFiltrada(int canal, int amostras = 100) {
  float corrente = calcularCorrente(canal, amostras);
  
  // Adiciona ao histórico
  canais[canal].historico[canais[canal].indiceHist] = corrente;
  canais[canal].indiceHist = (canais[canal].indiceHist + 1) % 10;
  
  // Calcula média móvel
  float soma = 0;
  for(int i = 0; i < 10; i++) {
    soma += canais[canal].historico[i];
  }
  
  return soma / 10.0;
}

// ========== VERIFICA SE CANAL ESTÁ CALIBRADO ==========
bool canalEstaCalibrado(int canal) {
  if(!canais[canal].calibrado) {
    return false;
  }
  
  // Só verifica calibração se o canal estiver fisicamente desligado
  if (canais[canal].fisicamenteLigado) {
    // Se está ligado, considera calibrado (não faz sentido verificar corrente zero)
    return true;
  }
  
  // Se está desligado, verifica se a corrente é próxima de zero
  float corrente = lerCorrenteFiltrada(canal, 200);
  float correnteMA = corrente * 1000;
  
  return (correnteMA <= LIMITE_CALIBRACAO_OK);
}

// ========== VERIFICA SE TODOS OS CANAIS ESTÃO CALIBRADOS ==========
bool todosCanaisCalibrados() {
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(!canalEstaCalibrado(i)) {
      return false;
    }
  }
  return true;
}

// ========== FUNÇÃO PARA VERIFICAR SE A CALIBRAÇÃO É VÁLIDA ==========
bool verificarCalibracaoValida() {
  if (!tudoDesligadoFisicamente()) {
    Serial.println("⚠️  Não é possível verificar calibração - há dispositivos ligados");
    return true; // Assume que está OK se não puder verificar
  }
  
  Serial.println("🔍 Verificando validade da calibração carregada...");
  bool calibracaoValida = true;
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(canais[i].calibrado) {
      float corrente = lerCorrenteFiltrada(i, 300);
      float correnteMA = corrente * 1000;
      
      Serial.print("  ");
      Serial.print(canais[i].nome);
      Serial.print(": ");
      Serial.print(correnteMA, 1);
      Serial.print(" mA");
      
      if(correnteMA > LIMITE_DESCALIBRADO) {
        Serial.println(" ❌ (DESCALIBRADO)");
        canais[i].precisaRecalibracao = true;
        calibracaoValida = false;
      } else if(correnteMA > LIMITE_ALERTA_CALIBRACAO) {
        Serial.println(" ⚠️  (ALERTA)");
      } else {
        Serial.println(" ✅ (OK)");
      }
    }
  }
  
  return calibracaoValida;
}

// ========== CALIBRAÇÃO AUTOMÁTICA COMPLETA ==========
bool calibrarTodosCanais() {
  // Usa variável local para tentativas nesta sessão
  static int tentativasEstaSessao = 0;
  
  if (tentativasEstaSessao == 0) {
    tempoInicioCalibracao = millis();
    Serial.println("\n🎯🎯🎯 INICIANDO CALIBRAÇÃO AUTOMÁTICA");
    Serial.print("✅ CORRECAO_GLOBAL = ");
    Serial.println(CORRECAO_GLOBAL_FIXO, 4);
  }
  
  tentativasEstaSessao++;
  tentativasCalibracaoTotal++; // Mantém histórico total
  
  unsigned long tempoDecorrido = (millis() - tempoInicioCalibracao) / 1000;
  
  Serial.print("\n🎯 Tentativa ");
  Serial.print(tentativasEstaSessao);
  Serial.print(" de ");
  Serial.println(MAX_TENTATIVAS_CALIBRACAO);
  Serial.print("✅ Tempo decorrido: ");
  Serial.print(tempoDecorrido);
  Serial.println(" segundos");
  
  // 1. Garante que TUDO está desligado FISICAMENTE
  Serial.println("🔌 Desligando todos os relés...");
  for(int i = 0; i < NUM_CANAIS; i++) {
    digitalWrite(canais[i].pinoRele, HIGH);
    canais[i].releLigado = false;
    canais[i].fisicamenteLigado = false;
    delay(100);
  }
  
  delay(2000); // Espera estabilizar
  
  // Atualiza estado físico
  atualizarEstadoFisicoReles();
  
  // 2. Calibra zero de cada canal
  Serial.println("🎯 Calibrando zeros dos sensores...");
  bool algumCanalCalibrado = false;
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(calibrarZeroCanal(i)) {
      algumCanalCalibrado = true;
    }
    delay(300);
  }
  
  if(!algumCanalCalibrado) {
    Serial.println("❌❌❌ FALHA TOTAL NA CALIBRAÇÃO!");
    return false;
  }
  
  // 3. Marca como calibrado (para permitir leitura)
  for(int i = 0; i < NUM_CANAIS; i++) {
    canais[i].calibrado = true;
    canais[i].precisaRecalibracao = false;
  }
  
  // 4. Teste pós-calibração
  Serial.println("\n🔍🔍🔍 TESTE PÓS-CALIBRAÇÃO (com tudo desligado):");
  bool todasCorrentesZero = true;
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    float corrente = lerCorrenteFiltrada(i, 300);
    float correnteMA = corrente * 1000;
    canais[i].correnteMedia = correnteMA;
    
    Serial.print("  ");
    Serial.print(canais[i].nome);
    Serial.print(": ");
    Serial.print(correnteMA, 1);
    Serial.print(" mA");
    
    if(correnteMA <= LIMITE_CALIBRACAO_OK) {
      Serial.println(" ✅ PERFEITO!");
      canais[i].precisaRecalibracao = false;
    } else if(correnteMA <= LIMITE_ALERTA_CALIBRACAO) {
      Serial.println(" ⚠️  ACEITÁVEL");
      canais[i].precisaRecalibracao = false;
      todasCorrentesZero = false; // Não está perfeito
    } else {
      Serial.println(" ❌ ALTA!");
      canais[i].precisaRecalibracao = true;
      todasCorrentesZero = false;
    }
  }
  
  // 5. VERIFICAÇÃO CRÍTICA: Só conclui se TODAS as correntes estiverem zeradas (com tudo desligado)
  if(todasCorrentesZero) {
    Serial.println("\n✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅");
    Serial.println("✅ TODAS AS CORRENTES ZERADAS (<5mA) COM TUDO DESLIGADO!");
    Serial.println("✅ CALIBRAÇÃO CONCLUÍDA COM SUCESSO!");
    Serial.print("✅ Tentativas nesta sessão: ");
    Serial.println(tentativasEstaSessao);
    Serial.print("✅ Tentativas totais (histórico): ");
    Serial.println(tentativasCalibracaoTotal);
    Serial.print("✅ Tempo total: ");
    Serial.print(tempoDecorrido);
    Serial.println(" segundos");
    
    // SALVA NA EEPROM
    if(salvarCalibracaoEEPROM()) {
      calibracaoConcluida = true;
      precisaCalibracaoInicial = false;
      
      // Reseta contadores de tentativas para os canais
      for(int i = 0; i < NUM_CANAIS; i++) {
        canais[i].tentativasCalibracao = 0;
      }
      
      // Reseta contador desta sessão
      tentativasEstaSessao = 0;
      
      Serial.println("✅ Calibração salva na EEPROM!");
      Serial.println("✅ Sistema usará estes dados se achar que está descalibrado");
      return true;
    } else {
      Serial.println("❌ ERRO ao salvar na EEPROM!");
      calibracaoConcluida = false;
      return false;
    }
  } else {
    Serial.println("\n❌❌❌ CALIBRAÇÃO INCOMPLETA!");
    Serial.println("❌ Algumas correntes não zeraram (<5mA) com tudo desligado");
    
    // Mostra resumo das correntes
    Serial.println("📊 RESUMO DAS CORRENTES:");
    for(int i = 0; i < NUM_CANAIS; i++) {
      Serial.print("  ");
      Serial.print(canais[i].nome);
      Serial.print(": ");
      Serial.print(canais[i].correnteMedia, 1);
      Serial.println(" mA");
    }
    
    // Verifica se já tentou muitas vezes
    if(tentativasEstaSessao >= MAX_TENTATIVAS_CALIBRACAO) {
      Serial.println("\n❌❌❌ MÁXIMO DE TENTATIVAS ALCANÇADO!");
      Serial.print("❌ ");
      Serial.print(MAX_TENTATIVAS_CALIBRACAO);
      Serial.println(" tentativas realizadas sem sucesso");
      Serial.println("❌ O sistema continuará operando, mas pode haver imprecisões");
      Serial.println("❌ Use o comando MQTT 'calibrar' para tentar novamente");
      
      // Reseta contador desta sessão
      tentativasEstaSessao = 0;
      
      // Marca como não calibrado mas permite operação
      calibracaoConcluida = false;
      return false;
    } else {
      int tentativasRestantes = MAX_TENTATIVAS_CALIBRACAO - tentativasEstaSessao;
      Serial.print("\n⚠️  Tentando novamente em 2 segundos... (");
      Serial.print(tentativasRestantes);
      Serial.println(" tentativas restantes)");
      delay(2000);
      return calibrarTodosCanais(); // Tenta novamente
    }
  }
}

// ========== EEPROM FUNCTIONS ==========
bool salvarCalibracaoEEPROM() {
  DadosCalibracao dados;
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    dados.adcZeros[i] = canais[i].adcZero;
    dados.offsets[i] = canais[i].offsetCorrente;
    dados.divisores[i] = DIVISORES[i];
    dados.fatoresCorrecao[i] = canais[i].fatorCorrecao;
  }
  
  dados.correcaoGlobal = CORRECAO_GLOBAL_FIXO; // SEMPRE 0.3702
  dados.tensaoRede = TENSAO_REDE;
  dados.calibrado = true;
  dados.dataCalibracao = millis();
  dados.checksum = calcularChecksum(&dados, sizeof(DadosCalibracao));
  
  EEPROM.put(EEPROM_CALIB_ADDR, dados);
  
  if(EEPROM.commit()) {
    Serial.println("✅ Calibração salva na EEPROM!");
    return true;
  } else {
    Serial.println("❌ Erro ao salvar calibração!");
    return false;
  }
}

bool carregarCalibracaoEEPROM() {
  DadosCalibracao dados;
  EEPROM.get(EEPROM_CALIB_ADDR, dados);
  
  unsigned long checksumCalculado = calcularChecksum(&dados, sizeof(DadosCalibracao));
  
  if(dados.checksum == checksumCalculado && dados.checksum != 0 && dados.calibrado) {
    // Carrega dados da calibração
    for(int i = 0; i < NUM_CANAIS; i++) {
      canais[i].adcZero = dados.adcZeros[i];
      canais[i].adcZeroAtual = dados.adcZeros[i];
      canais[i].offsetCorrente = dados.offsets[i];
      DIVISORES[i] = dados.divisores[i];
      canais[i].fatorCorrecao = dados.fatoresCorrecao[i];
      canais[i].calibrado = true;
      canais[i].precisaRecalibracao = false;
    }
    
    // Força CORRECAO_GLOBAL para 0.3702
    CORRECAO_GLOBAL = CORRECAO_GLOBAL_FIXO;
    
    TENSAO_REDE = dados.tensaoRede;
    
    Serial.println("✅ Calibração carregada da EEPROM");
    Serial.print("  CORRECAO_GLOBAL: ");
    Serial.println(CORRECAO_GLOBAL, 4);
    
    // NÃO marca como concluída ainda - vamos verificar se é válida
    Serial.println("🔄 Verificando se a calibração carregada é válida...");
    
    return true;
  } else {
    Serial.println("⚠️  Nenhuma calibração válida encontrada na EEPROM");
    return false;
  }
}

void salvarConfigWiFi(const String& ssid, const String& password) {
  WiFiConfig config;
  strncpy(config.ssid, ssid.c_str(), sizeof(config.ssid) - 1);
  strncpy(config.password, password.c_str(), sizeof(config.password) - 1);
  config.configured = true;
  config.checksum = calcularChecksum(&config, sizeof(WiFiConfig) - sizeof(unsigned long));
  
  EEPROM.put(EEPROM_WIFI_ADDR, config);
  
  if(EEPROM.commit()) {
    Serial.println("✅ Configuração WiFi salva na EEPROM");
  } else {
    Serial.println("❌ Erro ao salvar configuração WiFi");
  }
}

bool carregarConfigWiFi() {
  WiFiConfig config;
  EEPROM.get(EEPROM_WIFI_ADDR, config);
  
  unsigned long checksumCalculado = calcularChecksum(&config, sizeof(WiFiConfig) - sizeof(unsigned long));
  
  if(config.configured && config.ssid[0] != '\0' && config.checksum == checksumCalculado) {
    Serial.println("📖 Configuração WiFi carregada da EEPROM");
    wifiConfigured = true;
    return true;
  }
  
  Serial.println("❌ Nenhuma configuração WiFi encontrada");
  wifiConfigured = false;
  return false;
}

// ========== CÁLCULOS DE ENERGIA ==========
void calcularEnergia() {
  unsigned long agora = millis();
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(!canais[i].calibrado) continue;
    
    if(canais[i].ultimaLeitura == 0) {
      canais[i].ultimaLeitura = agora;
      continue;
    }
    
    unsigned long tempoMs = agora - canais[i].ultimaLeitura;
    if(tempoMs > 0) {
      float horas = tempoMs / 3600000.0;
      
      // Atualiza potência
      canais[i].potencia = canais[i].corrente * TENSAO_REDE;
      
      // Calcula energia apenas se há potência real
      if(canais[i].potencia > 0.1) { // Threshold mais baixo para capturar consumo real
        float energiaIntervalo = canais[i].potencia * horas;
        
        // Validação para evitar valores errados
        if(energiaIntervalo > 0 && energiaIntervalo < 1000.0) {
          canais[i].energia += energiaIntervalo;
        }
      }
      
      canais[i].ultimaLeitura = agora;
    }
  }
}

float calcularPotenciaTotal() {
  float potenciaTotal = 0;
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(!canais[i].calibrado) continue;
    if(canais[i].corrente >= THRESHOLD_CORRENTE) {
      potenciaTotal += canais[i].potencia;
    }
  }
  
  return potenciaTotal;
}

float calcularConsumoTotal() {
  float consumoTotal = 0;
  
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(canais[i].calibrado) {
      consumoTotal += canais[i].energia;
    }
  }
  
  return consumoTotal;
}

// ========== FUNÇÕES DO BOTÃO ==========
void IRAM_ATTR handleBotaoInterrupt() {
  unsigned long agora = millis();
  
  if (agora - ultimaInterrupcao > DEBOUNCE_INTERVAL) {
    botaoPressionado = (digitalRead(BUTTON_PRESENCA) == LOW);
    ultimaInterrupcao = agora;
  }
}

void processarBotao() {
  static unsigned long ultimaVerificacao = 0;
  
  if (millis() - ultimaVerificacao < 10) return;
  ultimaVerificacao = millis();
  
  bool estadoAtual = !botaoPressionado;
  
  if (!estadoAtual && botaoEstadoAnterior) {
    tempoPressionamentoInicio = millis();
    digitalWrite(LED_AMARELO, HIGH);
  }
  
  if (estadoAtual && !botaoEstadoAnterior) {
    unsigned long tempoPressionado = millis() - tempoPressionamentoInicio;
    
    digitalWrite(LED_AMARELO, LOW);
    
    if (tempoPressionado >= 50 && tempoPressionado < 1000) {
      presencaSimulada = !presencaSimulada;
      ultimoAcionamento = millis();
      Serial.println(presencaSimulada ? "👤 Presença ATIVADA" : "👤 Presença DESATIVADA");
      
      if (wifiConnected) {
        publicarStatus();
      }
    }
    else if (tempoPressionado >= 1000 && tempoPressionado < 3000) {
      modoAutomatico = !modoAutomatico;
      Serial.println(modoAutomatico ? "🔄 Modo AUTOMÁTICO" : "🔄 Modo MANUAL");
    }
    else if (tempoPressionado >= 3000) {
      Serial.println("\n🎯 FORÇANDO RECALIBRAÇÃO DE TODOS OS SENSORES!");
      calibracaoConcluida = false;
      for(int i = 0; i < NUM_CANAIS; i++) {
        canais[i].precisaRecalibracao = true;
        canais[i].tentativasCalibracao = 0;
      }
      tentativasCalibracaoTotal = 0;
    }
  }
  
  botaoEstadoAnterior = estadoAtual;
}

void verificarTimeoutPresenca() {
  if (presencaSimulada && (millis() - ultimoAcionamento > tempoDesligamento)) {
    presencaSimulada = false;
    Serial.println("⏰ TIMEOUT - Presença DESATIVADA");
    
    if (wifiConnected) {
      publicarStatus();
    }
  }
}

// ========== FUNÇÕES WiFi ==========
void conectarWiFi() {
  WiFiConfig config;
  EEPROM.get(EEPROM_WIFI_ADDR, config);
  
  if (!config.configured || config.ssid[0] == '\0') {
    Serial.println("❌ Nenhuma configuração WiFi disponível");
    wifiConfigured = false;
    iniciarModoAP();
    return;
  }
  
  wifiConfigured = true;
  Serial.println("📡 Conectando à rede WiFi: " + String(config.ssid));
  
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  
  WiFi.begin(config.ssid, config.password);
  wifiConnectStart = millis();
}

void iniciarModoAP() {
  Serial.println("🚀 Iniciando modo AP para configuração...");
  
  WiFi.disconnect(true);
  delay(1000);
  
  WiFi.mode(WIFI_AP);
  
  String apSSID = "SistemaEnergia_" + String(ESP.getEfuseMac() & 0xFFFFFF, HEX);
  apSSID.toUpperCase();
  
  bool apStarted = WiFi.softAP(apSSID.c_str(), NULL);
  
  if (apStarted) {
    Serial.println("✅ AP WiFi criado com sucesso!");
    Serial.println("📡 Nome da rede: " + apSSID);
    Serial.println("📱 IP do Access Point: " + WiFi.softAPIP().toString());
    modoAPAtivo = true;
    digitalWrite(LED_VERMELHO, HIGH);
  } else {
    Serial.println("❌ Falha ao criar AP WiFi");
    return;
  }
  
  server.on("/", HTTP_GET, []() {
    server.send(200, "text/html", CONFIG_PAGE);
  });
  
  server.on("/scan", HTTP_GET, []() {
    WiFi.mode(WIFI_AP_STA);
    int n = WiFi.scanNetworks();
    
    String json = "{\"networks\":[";
    for (int i = 0; i < n; ++i) {
      if (i > 0) json += ",";
      json += "{\"ssid\":\"" + WiFi.SSID(i) + "\",";
      json += "\"rssi\":" + String(WiFi.RSSI(i)) + "}";
    }
    json += "]}";
    
    WiFi.mode(WIFI_AP);
    server.send(200, "application/json", json);
  });
  
  server.on("/save", HTTP_POST, []() {
    if (server.hasArg("ssid") && server.hasArg("password")) {
      String ssid = server.arg("ssid");
      String password = server.arg("password");
      
      if (ssid.length() > 0) {
        salvarConfigWiFi(ssid, password);
        server.send(200, "text/plain", "Configuração salva com sucesso! Reiniciando...");
        
        delay(3000);
        ESP.restart();
      } else {
        server.send(400, "text/plain", "ERRO: SSID não pode estar vazio");
      }
    } else {
      server.send(400, "text/plain", "ERRO: Parâmetros faltando");
    }
  });
  
  server.begin();
  Serial.println("✅ Servidor web iniciado na porta 80");
}

void verificarConexaoWiFi() {
  if (!wifiConfigured && !modoAPAtivo) {
    iniciarModoAP();
    return;
  }
  
  if (wifiConfigured && !modoAPAtivo) {
    static unsigned long ultimaVerificacaoWiFi = 0;
    
    if (millis() - ultimaVerificacaoWiFi < 2000) return;
    ultimaVerificacaoWiFi = millis();
    
    wl_status_t status = WiFi.status();
    
    if (status == WL_CONNECTED) {
      if (!wifiConnected) {
        wifiConnected = true;
        Serial.println("✅ WiFi conectado!");
        Serial.print("📱 IP: ");
        Serial.println(WiFi.localIP());
        digitalWrite(LED_VERDE, HIGH);
        digitalWrite(LED_VERMELHO, LOW);
      }
    } else {
      if (wifiConnected) {
        wifiConnected = false;
        Serial.println("❌ WiFi desconectado!");
        digitalWrite(LED_VERDE, LOW);
        digitalWrite(LED_VERMELHO, HIGH);
      }
      
      if (millis() - wifiConnectStart > wifiConnectTimeout) {
        Serial.println("⏰ Timeout na conexão WiFi. Tentando reconectar...");
        WiFi.reconnect();
        wifiConnectStart = millis();
      }
    }
  }
  
  if (modoAPAtivo) {
    server.handleClient();
  }
}

// ========== FUNÇÕES MQTT ==========
void publicarStatus() {
  if (!wifiConnected) return;
  
  String status = "L:" + String(luminosidade) + 
                  ",P:" + String(presencaSimulada ? "1" : "0") +
                  ",M:" + String(modoAutomatico ? "A" : "M") +
                  ",Z1:" + String(zona1Ativa ? "1" : "0") +
                  ",Z2:" + String(zona2Ativa ? "1" : "0") +
                  ",Z3:" + String(zona3Ativa ? "1" : "0") +
                  ",T1:" + String(tomada1Ativa ? "1" : "0") +
                  ",CAL:" + String(calibracaoConcluida ? "1" : "0");
  
  if (client.publish(TOPIC_STATUS, status.c_str())) {
    Serial.print("📤 Status publicado: ");
    Serial.println(status);
  } else {
    Serial.println("❌ Falha ao publicar status MQTT");
  }
}

void publicarDadosEnergia() {
  if (!wifiConnected) return;
  
  float potenciaTotal = calcularPotenciaTotal();
  float consumoTotal = calcularConsumoTotal();
  
  String energia = "PTOTAL:" + String(potenciaTotal, 2) +
                   ",CONSUMO:" + String(consumoTotal, 3) +
                   ",PZ1:" + String(canais[0].corrente * 1000, 1) +
                   ",PZ2:" + String(canais[1].corrente * 1000, 1) +
                   ",PZ3:" + String(canais[2].corrente * 1000, 1) +
                   ",PT1:" + String(canais[3].corrente * 1000, 1);
  if (client.publish(TOPIC_ENERGIA, energia.c_str())) {
    Serial.print("📤 Energia publicado: ");
    Serial.println(energia);
  } else {
    Serial.println("❌ Falha ao publicar energia MQTT");
  }
}

void processarComando(String comando) {
  Serial.println("🎯 Comando: " + comando);
  
  if (comando == "atualizar_status") {
    publicarStatus();
    publicarDadosEnergia();
  }
  else if (comando == "calibrar") {
    Serial.println("🔧 Forçando recalibração via MQTT...");
    calibracaoConcluida = false;
    for(int i = 0; i < NUM_CANAIS; i++) {
      canais[i].precisaRecalibracao = true;
      canais[i].tentativasCalibracao = 0;
    }
    tentativasCalibracaoTotal = 0;
    calibrarTodosCanais();
  }
  else if (comando == "status_calibracao") {
    Serial.println("🔍 STATUS DA CALIBRAÇÃO:");
    Serial.print("  Calibração concluída: ");
    Serial.println(calibracaoConcluida ? "✅ SIM" : "❌ NÃO");
    Serial.print("  CORRECAO_GLOBAL: ");
    Serial.println(CORRECAO_GLOBAL, 4);
    Serial.print("  Tentativas totais (histórico): ");
    Serial.println(tentativasCalibracaoTotal);
    Serial.println("  Status por canal:");
    
    for(int i = 0; i < NUM_CANAIS; i++) {
      float corrente = lerCorrenteFiltrada(i, 200);
      float correnteMA = corrente * 1000;
      
      Serial.print("    ");
      Serial.print(canais[i].nome);
      Serial.print(": ");
      Serial.print(correnteMA, 1);
      Serial.print(" mA | Calibrado: ");
      Serial.print(canais[i].calibrado ? "✅" : "❌");
      Serial.print(" | Rele: ");
      Serial.print(canais[i].releLigado ? "LIGADO" : "DESLIGADO");
      Serial.print(" | ADC Zero: ");
      Serial.print(canais[i].adcZero, 1);
      Serial.print(" | Tentativas: ");
      Serial.println(canais[i].tentativasCalibracao);
    }
  }
  else if (comando == "presenca_on") {
    presencaSimulada = true;
    ultimoAcionamento = millis();
    Serial.println("✅ Presença ativada");
  }
  else if (comando == "presenca_off") {
    presencaSimulada = false;
    Serial.println("✅ Presença desligada");
  }
  else if (comando == "modo_auto") {
    modoAutomatico = true;
    Serial.println("✅ Modo automático");
  } 
  else if (comando == "modo_manual") {
    modoAutomatico = false;
    Serial.println("✅ Modo manual");
  }
  else if (comando == "zona1_on") {
    digitalWrite(RELE_ZONA_1, LOW);
    zona1Ativa = true;
    canais[0].releLigado = true;
    canais[0].fisicamenteLigado = true;
    Serial.println("💡 Zona 1 ligada");
  }
  else if (comando == "zona1_off") {
    digitalWrite(RELE_ZONA_1, HIGH);
    zona1Ativa = false;
    canais[0].releLigado = false;
    canais[0].fisicamenteLigado = false;
    Serial.println("💡 Zona 1 desligada");
  }
  else if (comando == "zona2_on") {
    digitalWrite(RELE_ZONA_2, LOW);
    zona2Ativa = true;
    canais[1].releLigado = true;
    canais[1].fisicamenteLigado = true;
    Serial.println("💡 Zona 2 ligada");
  }
  else if (comando == "zona2_off") {
    digitalWrite(RELE_ZONA_2, HIGH);
    zona2Ativa = false;
    canais[1].releLigado = false;
    canais[1].fisicamenteLigado = false;
    Serial.println("💡 Zona 2 desligada");
  }
  else if (comando == "zona3_on") {
    digitalWrite(RELE_ZONA_3, LOW);
    zona3Ativa = true;
    canais[2].releLigado = true;
    canais[2].fisicamenteLigado = true;
    Serial.println("💡 Zona 3 ligada");
  }
  else if (comando == "zona3_off") {
    digitalWrite(RELE_ZONA_3, HIGH);
    zona3Ativa = false;
    canais[2].releLigado = false;
    canais[2].fisicamenteLigado = false;
    Serial.println("💡 Zona 3 desligada");
  }
  else if (comando == "tomada1_on") {
    digitalWrite(RELE_TOMADA_1, LOW);
    tomada1Ativa = true;
    canais[3].releLigado = true;
    canais[3].fisicamenteLigado = true;
    Serial.println("🔌 Tomada 1 ligada");
  }
  else if (comando == "tomada1_off") {
    digitalWrite(RELE_TOMADA_1, HIGH);
    tomada1Ativa = false;
    canais[3].releLigado = false;
    canais[3].fisicamenteLigado = false;
    Serial.println("🔌 Tomada 1 desligada");
  }
  else if (comando == "debug") {
    Serial.println("🔍 DEBUG:");
    Serial.println("  Luminosidade: " + String(luminosidade));
    Serial.println("  Presença: " + String(presencaSimulada ? "SIM" : "NÃO"));
    Serial.println("  Modo: " + String(modoAutomatico ? "AUTO" : "MANUAL"));
    Serial.println("  Estados: Z1=" + String(zona1Ativa ? "ON" : "OFF") +
                  " Z2=" + String(zona2Ativa ? "ON" : "OFF") +
                  " Z3=" + String(zona3Ativa ? "ON" : "OFF") +
                  " T1=" + String(tomada1Ativa ? "ON" : "OFF"));
    Serial.println("  Potência Total: " + String(calcularPotenciaTotal(), 2) + "W");
    Serial.println("  Consumo Total: " + String(calcularConsumoTotal(), 3) + "Wh");
    Serial.println("  Tentativas totais: " + String(tentativasCalibracaoTotal));
  }
  
  if (wifiConnected) {
    publicarStatus();
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.print("📨 MQTT [");
  Serial.print(topic);
  Serial.print("]: ");
  Serial.println(message);
  
  if (String(topic) == TOPIC_CONTROL) {
    processarComando(message);
  }
}

void reconnect() {
  if (!wifiConnected) return;
  
  static unsigned long ultimaTentativa = 0;
  
  if (millis() - ultimaTentativa < 5000) return;
  ultimaTentativa = millis();
  
  Serial.print("🔄 Tentando conexão MQTT...");
  
  String clientId = "ESP32Energy-" + String(ESP.getEfuseMac() & 0xFFFFFF, HEX);
  
  if (client.connect(clientId.c_str())) {
    Serial.println("✅ Conectado ao broker MQTT!");
    client.subscribe(TOPIC_CONTROL);
    Serial.println("✅ Inscrito no tópico: " + String(TOPIC_CONTROL));
    publicarStatus();
    publicarDadosEnergia();
  } else {
    Serial.print("❌ Falha, rc=");
    Serial.print(client.state());
    Serial.println(". Tentando novamente em 5 segundos");
  }
}

// ========== FUNÇÕES DE CONTROLE AUTOMÁTICO ==========
void controlarIluminacaoAutomatica() {
  if (!modoAutomatico) return;
  
  bool mudou = false;
  
  if (presencaSimulada) {
    // ZONA 1
    if (luminosidade < LIMITE_ZONA_1) {
      if (!zona1Ativa) {
        digitalWrite(RELE_ZONA_1, LOW);
        zona1Ativa = true;
        canais[0].releLigado = true;
        canais[0].fisicamenteLigado = true;
        mudou = true;
        Serial.println("💡 Zona 1 LIGADA (luminosidade baixa)");
      }
    } else {
      if (zona1Ativa) {
        digitalWrite(RELE_ZONA_1, HIGH);
        zona1Ativa = false;
        canais[0].releLigado = false;
        canais[0].fisicamenteLigado = false;
        mudou = true;
        Serial.println("💡 Zona 1 DESLIGADA (luminosidade alta)");
      }
    }
    
    // ZONA 2
    if (luminosidade < LIMITE_ZONA_2) {
      if (!zona2Ativa) {
        digitalWrite(RELE_ZONA_2, LOW);
        zona2Ativa = true;
        canais[1].releLigado = true;
        canais[1].fisicamenteLigado = true;
        mudou = true;
        Serial.println("💡 Zona 2 LIGADA (luminosidade baixa)");
      }
    } else {
      if (zona2Ativa) {
        digitalWrite(RELE_ZONA_2, HIGH);
        zona2Ativa = false;
        canais[1].releLigado = false;
        canais[1].fisicamenteLigado = false;
        mudou = true;
        Serial.println("💡 Zona 2 DESLIGADA (luminosidade alta)");
      }
    }
    
    // ZONA 3
    if (luminosidade < LIMITE_ZONA_3) {
      if (!zona3Ativa) {
        digitalWrite(RELE_ZONA_3, LOW);
        zona3Ativa = true;
        canais[2].releLigado = true;
        canais[2].fisicamenteLigado = true;
        mudou = true;
        Serial.println("💡 Zona 3 LIGADA (luminosidade baixa)");
      }
    } else {
      if (zona3Ativa) {
        digitalWrite(RELE_ZONA_3, HIGH);
        zona3Ativa = false;
        canais[2].releLigado = false;
        canais[2].fisicamenteLigado = false;
        mudou = true;
        Serial.println("💡 Zona 3 DESLIGADA (luminosidade alta)");
      }
    }
  } else {
    // SEM PRESENÇA - Desliga todas as zonas
    if (zona1Ativa) {
      digitalWrite(RELE_ZONA_1, HIGH);
      zona1Ativa = false;
      canais[0].releLigado = false;
      canais[0].fisicamenteLigado = false;
      mudou = true;
      Serial.println("💡 Zona 1 DESLIGADA (sem presença)");
    }
    
    if (zona2Ativa) {
      digitalWrite(RELE_ZONA_2, HIGH);
      zona2Ativa = false;
      canais[1].releLigado = false;
      canais[1].fisicamenteLigado = false;
      mudou = true;
      Serial.println("💡 Zona 2 DESLIGADA (sem presença)");
    }
    
    if (zona3Ativa) {
      digitalWrite(RELE_ZONA_3, HIGH);
      zona3Ativa = false;
      canais[2].releLigado = false;
      canais[2].fisicamenteLigado = false;
      mudou = true;
      Serial.println("💡 Zona 3 DESLIGADA (sem presença)");
    }
  }
  
  if (mudou && wifiConnected) {
    publicarStatus();
  }
}

void controlarTomadaAutomatica() {
  if (!modoAutomatico) return;
  
  bool novaTomada1 = presencaSimulada;
  
  if (tomada1Ativa != novaTomada1) {
    digitalWrite(RELE_TOMADA_1, novaTomada1 ? LOW : HIGH);
    tomada1Ativa = novaTomada1;
    canais[3].releLigado = novaTomada1;
    canais[3].fisicamenteLigado = novaTomada1;
    Serial.println(tomada1Ativa ? "🔌 Tomada 1 LIGADA (presença)" : "🔌 Tomada 1 DESLIGADA (sem presença)");
    
    if (wifiConnected) {
      publicarStatus();
    }
  }
}

// ========== FUNÇÕES DISPLAY OLED ==========
void atualizarDisplay() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  // display.setTextColor(SSD1306_YELLOW);
  
  // Linha 1: Status da calibração
  display.setCursor(0, 0);
  display.print("Sistema de Energia");
  display.setCursor(0, 9);
  display.print("Calibr:");
  if(calibracaoConcluida) {
    // display.print("✅");
    display.print("OK");
  } else {
    // display.print("❌");
    // display.print("Calibr: ");
    // Linha 2: Tentativas (mantém histórico)
    display.setCursor(70, 9);
    display.print("T:");
    display.print(tentativasCalibracaoTotal);
    display.print("/");
    display.print(MAX_TENTATIVAS_CALIBRACAO);    
  }
  
  // // Linha 2: Tentativas (mantém histórico)
  // display.setCursor(70, 0);
  // display.print("T:");
  // display.print(tentativasCalibracaoTotal);
  // display.print("/");
  // display.print(MAX_TENTATIVAS_CALIBRACAO);
  
  // Linha 3: Potência
  display.setCursor(0, 18);
  display.print("P:");
  display.print(calcularPotenciaTotal(), 0);
  display.print("W");
  
  // Linha 4: Consumo
  display.setCursor(40, 18);
  display.print("C:");
  display.print(calcularConsumoTotal(), 0);
  display.print("Wh");
  
  // Linha 5: Luminosidade
  display.setCursor(0, 27);
  display.print("L:");
  display.print(luminosidade);
  
  // Linha 6: Presença
  display.setCursor(45, 27);
  display.print("P:");
  display.print(presencaSimulada ? "S" : "N");
  
  // Linha 7: Modo
  display.setCursor(75, 27);
  display.print("M:");
  display.print(modoAutomatico ? "Auto" : "Manual");
  
  // Linha 8: Estados das zonas
  display.setCursor(0, 36);
  display.print("Z1:");
  display.print(zona1Ativa ? "On" : "Off");
  display.setCursor(60, 36);
  display.print("Z2:");
  display.print(zona2Ativa ?  "On" : "Off");
  display.setCursor(0, 45);
  display.print("Z3:");
  display.print(zona3Ativa ?  "On" : "Off");
  
  // Linha 9: Tomada
  display.setCursor(60, 45);
  display.print("T1:");
  display.print(tomada1Ativa ?  "On" : "Off");
  
  // Linha 10: Correntes Z1 e Z2
  display.setCursor(0, 54);
  display.print("Z1:");
  display.print(canais[0].corrente * 1000, 0);
  display.print(" Z2:");
  display.print(canais[1].corrente * 1000, 0);  
  display.print(" Z3:");
  display.print(canais[2].corrente * 1000, 0);

  display.display();
}

// ========== ATUALIZAR TEMPOS DE USO ==========
void atualizarTemposUso() {
  unsigned long agora = millis();
  
  if (agora < ultimoTempoUpdate) {
    ultimoTempoUpdate = agora;
    return;
  }
  
  float deltaTempo = (agora - ultimoTempoUpdate) / 1000.0;
  
  if (deltaTempo > 0) {
    if (presencaSimulada) {
      tempoPresenca += deltaTempo;
    }
    
    if (zona1Ativa) tempoZona1 += deltaTempo;
    if (zona2Ativa) tempoZona2 += deltaTempo;
    if (zona3Ativa) tempoZona3 += deltaTempo;
    
    if (tomada1Ativa) tempoTomada1 += deltaTempo;
    
    ultimoTempoUpdate = agora;
  }
}

// ========== MONITORAMENTO DE DESCALIBRAÇÃO (MELHORADO) ==========
void monitorarDescalibracao() {
  static unsigned long ultimoMonitoramento = 0;
  
  if (millis() - ultimoMonitoramento < 60000) return; // Verifica a cada 1 minuto
  ultimoMonitoramento = millis();
  
  if (!calibracaoConcluida) return; // Só monitora se já foi calibrado
  
  // Atualiza estado físico antes de verificar
  atualizarEstadoFisicoReles();
  
  // Verifica se tudo está desligado FISICAMENTE
  if(tudoDesligadoFisicamente()) {
    bool descalibrado = false;
    
    for(int i = 0; i < NUM_CANAIS; i++) {
      if(canais[i].calibrado) {
        float corrente = lerCorrenteFiltrada(i, 300);
        float correnteMA = corrente * 1000;
        
        // Se corrente > 30mA com tudo desligado, marca como descalibrado
        if(correnteMA > LIMITE_DESCALIBRADO) {
          Serial.print("⚠️  ");
          Serial.print(canais[i].nome);
          Serial.print(" descalibrado! ");
          Serial.print(correnteMA, 1);
          Serial.println(" mA com tudo desligado.");
          canais[i].precisaRecalibracao = true;
          descalibrado = true;
        }
      }
    }
    
    if(descalibrado) {
      Serial.println("⚠️  Sistema detectado como descalibrado!");
      Serial.println("🔄 Tentando recarregar calibração da EEPROM primeiro...");
      
      // Tenta recarregar da EEPROM
      if (carregarCalibracaoEEPROM()) {
        if (verificarCalibracaoValida()) {
          Serial.println("✅ Calibração da EEPROM restaurada com sucesso!");
          calibracaoConcluida = true;
        } else {
          Serial.println("❌ Calibração da EEPROM não resolveu - marcando para recalibrar");
          calibracaoConcluida = false;
        }
      } else {
        Serial.println("❌ Nenhuma calibração válida na EEPROM - precisa recalibrar");
        calibracaoConcluida = false;
      }
    }
  }
}

// ========== SETUP COMPLETO ==========
void setup() {
  Serial.begin(115200);
  Serial.println();
  Serial.println("🎯🎯🎯 SISTEMA DE ENERGIA - CALIBRAÇÃO INTELIGENTE");
  Serial.println("✅ CORRECAO_GLOBAL fixo em 0.3702");
  Serial.println("✅ Primeiro carrega calibração da EEPROM");
  Serial.println("✅ Só recalibra se necessário ou solicitado");
  
  // Inicializar EEPROM
  EEPROM.begin(EEPROM_SIZE);
  
  // Configurar pinos
  pinMode(LDR_PIN, INPUT);
  pinMode(BUTTON_PRESENCA, INPUT);
  
  // Configurar relés
  pinMode(RELE_ZONA_1, OUTPUT);
  pinMode(RELE_ZONA_2, OUTPUT);
  pinMode(RELE_ZONA_3, OUTPUT);
  pinMode(RELE_TOMADA_1, OUTPUT);
  
  // Configurar sensores
  pinMode(SENSOR_ZONA_1, INPUT);
  pinMode(SENSOR_ZONA_2, INPUT);  
  pinMode(SENSOR_ZONA_3, INPUT);
  pinMode(SENSOR_TOMADA_1, INPUT);
  
  // LEDs de status
  pinMode(LED_VERDE, OUTPUT);
  pinMode(LED_AMARELO, OUTPUT);
  pinMode(LED_VERMELHO, OUTPUT);
  
  // INICIALIZAR TUDO DESLIGADO
  digitalWrite(RELE_ZONA_1, HIGH);
  digitalWrite(RELE_ZONA_2, HIGH);
  digitalWrite(RELE_ZONA_3, HIGH);
  digitalWrite(RELE_TOMADA_1, HIGH);
  digitalWrite(LED_VERDE, LOW);
  digitalWrite(LED_AMARELO, LOW);
  digitalWrite(LED_VERMELHO, LOW);
  
  // Configurar ADC
  analogSetWidth(12);
  analogSetAttenuation(ADC_11db);
  
  // Configurar interrupção do botão
  attachInterrupt(digitalPinToInterrupt(BUTTON_PRESENCA), handleBotaoInterrupt, CHANGE);
  
  // Inicializar display OLED
  if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("❌ Falha no display OLED");
  } else {
    Serial.println("✅ Display OLED inicializado");
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_YELLOW);
    display.setCursor(0,0);
    display.println("Sistema Energia");
    display.println("Inicializando...");
    display.display();
  }
  
  // Aguarda 2 segundos para estabilização
  delay(2000);
  
  // Configurar CORRECAO_GLOBAL fixo
  CORRECAO_GLOBAL = CORRECAO_GLOBAL_FIXO;
  
  // Inicializar estado físico dos relés
  atualizarEstadoFisicoReles();
  
  // ========== NOVA LÓGICA DE INICIALIZAÇÃO ==========
  Serial.println("\n🔧 INICIALIZAÇÃO DO SISTEMA:");
  
  // 1. TENTA CARREGAR CALIBRAÇÃO DA EEPROM (PRIMEIRA OPÇÃO)
  Serial.println("1️⃣  Tentando carregar calibração da EEPROM...");
  bool calibracaoCarregada = carregarCalibracaoEEPROM();
  
  if (calibracaoCarregada) {
    Serial.println("✅ Calibração carregada da EEPROM");
    
    // 2. VERIFICA SE A CALIBRAÇÃO É VÁLIDA
    Serial.println("2️⃣  Verificando se a calibração carregada é válida...");
    
    // Garante que tudo está desligado para testar
    Serial.println("🔌 Garantindo que tudo está desligado...");
    for(int i = 0; i < NUM_CANAIS; i++) {
      digitalWrite(canais[i].pinoRele, HIGH);
      delay(100);
    }
    delay(2000); // Espera estabilizar
    atualizarEstadoFisicoReles();
    
    // Verifica se a calibração é válida
    if (verificarCalibracaoValida()) {
      Serial.println("✅✅✅ CALIBRAÇÃO DA EEPROM VÁLIDA!");
      Serial.println("✅ Sistema pronto para operação");
      calibracaoConcluida = true;
      precisaCalibracaoInicial = false;
      
      // Limpa flags de recalibração
      for(int i = 0; i < NUM_CANAIS; i++) {
        canais[i].precisaRecalibracao = false;
      }
    } else {
      Serial.println("❌❌❌ CALIBRAÇÃO DA EEPROM INVÁLIDA!");
      Serial.println("🔧 Iniciando calibração automática...");
      calibracaoConcluida = false;
      precisaCalibracaoInicial = true;
      
      // Marca todos os canais para recalibração
      for(int i = 0; i < NUM_CANAIS; i++) {
        canais[i].precisaRecalibracao = true;
      }
      
      // Inicia calibração
      calibrarTodosCanais();
    }
  } else {
    // 3. SE NÃO HOUVER CALIBRAÇÃO NA EEPROM, CALIBRA
    Serial.println("❌ Nenhuma calibração válida encontrada na EEPROM");
    Serial.println("🔧 Iniciando calibração automática pela primeira vez...");
    
    calibracaoConcluida = false;
    precisaCalibracaoInicial = true;
    
    // Marca todos os canais para recalibração
    for(int i = 0; i < NUM_CANAIS; i++) {
      canais[i].precisaRecalibracao = true;
    }
    
    // Inicia calibração
    calibrarTodosCanais();
  }
  
  // Carregar configuração WiFi
  if (!carregarConfigWiFi()) {
    Serial.println("❌ Nenhuma configuração WiFi encontrada");
    Serial.println("📱 Conecte-se ao AP para configurar WiFi");
    iniciarModoAP();
  } else {
    Serial.println("✅ Config WiFi encontrada - Conectando...");
    conectarWiFi();
  }
  
  // Configurar MQTT
  client.setServer(mqtt_server, 1883);
  client.setCallback(mqttCallback);
  
  // Inicializar timers
  ultimoTempoUpdate = millis();
  ultimoAcionamento = millis();
  
  // Inicializar timestamps dos canais
  for(int i = 0; i < NUM_CANAIS; i++) {
    canais[i].ultimaLeitura = millis();
    canais[i].releLigado = false;
    canais[i].fisicamenteLigado = false;
  }
  
  Serial.println("\n✅ Sistema inicializado!");
  Serial.println("📋 COMANDOS MQTT:");
  Serial.println("  - atualizar_status    (Publica status e energia)");
  Serial.println("  - calibrar            (Força recalibração completa)");
  Serial.println("  - status_calibracao   (Mostra status detalhado da calibração)");
  Serial.println("  - presenca_on/off     (Controla presença)");
  Serial.println("  - modo_auto/manual    (Altera modo de operação)");
  Serial.println("  - zona[1-3]_on/off    (Controla zonas de iluminação)");
  Serial.println("  - tomada1_on/off      (Controla tomada)");
  Serial.println("  - debug               (Mostra informações detalhadas)");
  
  Serial.println("\n🎯 COMANDOS POR BOTÃO:");
  Serial.println("  - Pressione rápido: Alterna presença");
  Serial.println("  - Pressione 1-3s: Alterna modo automático/manual");
  Serial.println("  - Pressione >3s: Força recalibração");
  
  Serial.println("\n🔧 CORRECAO_GLOBAL fixo em: 0.3702");
  Serial.println("🎯 Máximo de tentativas por sessão: 60");
  Serial.println("💾 Dados de calibração são salvos na EEPROM para recarregamento");
}

// ========== LOOP PRINCIPAL ==========
void loop() {
  // Atualizar luminosidade
  luminosidade = lerLuminosidade();
  
  // Atualizar estado físico dos relés
  atualizarEstadoFisicoReles();
  
  // WiFi
  verificarConexaoWiFi();
  
  // Botão
  processarBotao();
  verificarTimeoutPresenca();
  
  // Monitora descalibração
  monitorarDescalibracao();
  
  // Se precisa de calibração e ainda não foi concluída
  if (!calibracaoConcluida) {
    // Verifica se algum canal precisa de recalibração
    bool precisaRecalibrar = false;
    for(int i = 0; i < NUM_CANAIS; i++) {
      if(canais[i].precisaRecalibracao) {
        precisaRecalibrar = true;
        break;
      }
    }
    
    if(precisaRecalibrar) {
      Serial.println("🎯 Sistema precisa de calibração...");
      calibrarTodosCanais();
    }
  }
  
  // Controle automático
  controlarIluminacaoAutomatica();
  controlarTomadaAutomatica();
  
  // Atualizar tempos de uso
  atualizarTemposUso();
  
  // Atualizar leituras de corrente
  for(int i = 0; i < NUM_CANAIS; i++) {
    if(canais[i].calibrado) {
      canais[i].corrente = lerCorrenteFiltrada(i, 100);
    }
  }
  
  // Calcular energia (sempre, independente de threshold)
  static unsigned long ultimoCalculoEnergia = 0;
  if(millis() - ultimoCalculoEnergia >= 1000) {
    calcularEnergia();
    ultimoCalculoEnergia = millis();
  }
  
  // Atualizar display
  static unsigned long ultimoDisplayUpdate = 0;
  if(millis() - ultimoDisplayUpdate >= 1000) {
    atualizarDisplay();
    ultimoDisplayUpdate = millis();
  }
  
  // MQTT
  if (wifiConnected) {
    if (!client.connected()) {
      reconnect();
    }
    client.loop();
    
    unsigned long agora = millis();
    
    if (agora - lastStatusPublish > statusPublishInterval) {
      publicarStatus();
      lastStatusPublish = agora;
    }
    
    if (agora - lastEnergyPublish > energyPublishInterval) {
      publicarDadosEnergia();
      lastEnergyPublish = agora;
    }
  }
  
  // Debug periódico (a cada 30 segundos)
  static unsigned long lastDebug = 0;
  if (millis() - lastDebug > 30000) {
    lastDebug = millis();
    
    Serial.println("========================================");
    Serial.println("📡 STATUS DO SISTEMA:");
    Serial.print("  Calibração: ");
    Serial.println(calibracaoConcluida ? "✅ CONCLUÍDA" : "❌ PENDENTE");
    Serial.print("  CORRECAO_GLOBAL: ");
    Serial.println(CORRECAO_GLOBAL, 4);
    Serial.print("  Tentativas totais (histórico): ");
    Serial.println(tentativasCalibracaoTotal);
    Serial.print("  WiFi: ");
    Serial.println(wifiConnected ? "CONECTADO" : "DESCONECTADO");
    
    Serial.println("  ESTADOS DOS RELÉS:");
    for(int i = 0; i < NUM_CANAIS; i++) {
      Serial.print("    ");
      Serial.print(canais[i].nome);
      Serial.print(": Lógico=");
      Serial.print(canais[i].releLigado ? "LIGADO" : "DESLIGADO");
      Serial.print(" | Físico=");
      Serial.println(canais[i].fisicamenteLigado ? "LIGADO" : "DESLIGADO");
    }
    
    Serial.println("  CORRENTES (mA):");
    for(int i = 0; i < NUM_CANAIS; i++) {
      if(canais[i].calibrado) {
        float corrente = canais[i].corrente * 1000;
        Serial.print("    ");
        Serial.print(canais[i].nome);
        Serial.print(": ");
        Serial.print(corrente, 1);
        Serial.print(" mA | ADC Zero: ");
        Serial.print(canais[i].adcZero, 1);
        if(!canais[i].fisicamenteLigado && corrente > LIMITE_CALIBRACAO_OK) {
          Serial.println(" ⚠️  (corrente alta com relé desligado)");
        } else {
          Serial.println();
        }
      }
    }
    
    Serial.print("  Potência Total: ");
    Serial.print(calcularPotenciaTotal(), 1);
    Serial.print("W | Consumo: ");
    Serial.print(calcularConsumoTotal(), 3);
    Serial.println("Wh");
    
    // Verifica se há calibração salva
    DadosCalibracao dados;
    EEPROM.get(EEPROM_CALIB_ADDR, dados);
    unsigned long checksumCalculado = calcularChecksum(&dados, sizeof(DadosCalibracao));
    
    if(dados.checksum == checksumCalculado && dados.checksum != 0) {
      Serial.println("  💾 Calibração salva na EEPROM: ✅ SIM");
    } else {
      Serial.println("  💾 Calibração salva na EEPROM: ❌ NÃO");
    }
    
    Serial.println("========================================");
  }
  
  delay(10);
}