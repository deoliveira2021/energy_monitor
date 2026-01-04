import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/sensor_data.dart';
import '../models/energy_data.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'energy_control_v2.db');
    
    return await openDatabase(
      path,
      version: 4, // Versão aumentada para nova estrutura
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Tabela de dados dos sensores (ATUALIZADA)
    await db.execute('''
      CREATE TABLE sensor_data(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        luminosidade INTEGER NOT NULL,
        presenca INTEGER NOT NULL,
        zona1 INTEGER NOT NULL,
        zona2 INTEGER NOT NULL,
        zona3 INTEGER NOT NULL,
        tomada1 INTEGER NOT NULL,
        tomada2 INTEGER NOT NULL,
        modoAutomatico INTEGER NOT NULL
      )
    ''');
    
    // Tabela para dados de energia (ATUALIZADA com campos monetários)
    await db.execute('''
      CREATE TABLE energy_data(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        power_total REAL NOT NULL,
        power_zone1 REAL NOT NULL,
        power_zone2 REAL NOT NULL,
        power_zone3 REAL NOT NULL,
        power_tomada1 REAL NOT NULL,
        power_tomada2 REAL NOT NULL,
        consumption_total REAL NOT NULL,
        valor_consumo REAL NOT NULL,
        moeda TEXT NOT NULL,
        time_zone1 REAL NOT NULL,
        time_zone2 REAL NOT NULL,
        time_zone3 REAL NOT NULL,
        time_tomada1 REAL NOT NULL,
        time_tomada2 REAL NOT NULL,
        time_presence REAL NOT NULL
      )
    ''');
    
    // Tabela para configurações do app
    await db.execute('''
      CREATE TABLE app_settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    
    await db.execute('CREATE INDEX idx_timestamp ON sensor_data(timestamp)');
    await db.execute('CREATE INDEX idx_energy_timestamp ON energy_data(timestamp)');
    
    // Inserir configurações padrão
    await _insertDefaultSettings(db);
    
    print('✅ Banco de dados v2 criado com nova estrutura');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Upgrade para versão 2 - adicionar tabela de energia
      await db.execute('''
        CREATE TABLE energy_data(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp INTEGER NOT NULL,
          power_total REAL NOT NULL,
          power_zone1 REAL NOT NULL,
          power_zone2 REAL NOT NULL,
          power_zone3 REAL NOT NULL,
          power_tomada1 REAL NOT NULL,
          power_tomada2 REAL NOT NULL,
          consumption_total REAL NOT NULL,
          valor_consumo REAL NOT NULL,
          moeda TEXT NOT NULL,
          time_zone1 REAL NOT NULL,
          time_zone2 REAL NOT NULL,
          time_zone3 REAL NOT NULL,
          time_tomada1 REAL NOT NULL,
          time_tomada2 REAL NOT NULL,
          time_presence REAL NOT NULL
        )
      ''');
      
      await db.execute('CREATE INDEX idx_energy_timestamp ON energy_data(timestamp)');
      print('🔄 Banco atualizado para versão 2 - Tabela energy_data criada');
    }
    
    if (oldVersion < 3) {
      // Upgrade para versão 3 - adicionar tabela de configurações
      await db.execute('''
        CREATE TABLE app_settings(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      
      await _insertDefaultSettings(db);
      print('🔄 Banco atualizado para versão 3 - Tabela app_settings criada');
    }
    
    if (oldVersion < 4) {
      // Upgrade para versão 4 - atualizar tabela sensor_data para separar tomadas
      await db.execute('''
        CREATE TABLE sensor_data_new(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp INTEGER NOT NULL,
          luminosidade INTEGER NOT NULL,
          presenca INTEGER NOT NULL,
          zona1 INTEGER NOT NULL,
          zona2 INTEGER NOT NULL,
          zona3 INTEGER NOT NULL,
          tomada1 INTEGER NOT NULL,
          tomada2 INTEGER NOT NULL,
          modoAutomatico INTEGER NOT NULL
        )
      ''');
      
      // Copiar dados antigos para nova tabela
      await db.execute('''
        INSERT INTO sensor_data_new 
        SELECT id, timestamp, luminosidade, presenca, zona1, zona2, zona3, 
               tomada as tomada1, 0 as tomada2, modoAutomatico 
        FROM sensor_data
      ''');
      
      // Remover tabela antiga
      await db.execute('DROP TABLE sensor_data');
      
      // Renomear nova tabela
      await db.execute('ALTER TABLE sensor_data_new RENAME TO sensor_data');
      
      await db.execute('CREATE INDEX idx_timestamp ON sensor_data(timestamp)');
      
      print('🔄 Banco atualizado para versão 4 - Tabela sensor_data atualizada');
    }
  }

  Future<void> _insertDefaultSettings(Database db) async {
    final defaultSettings = [
      {'key': 'tensao_rede', 'value': '220.0'},
      {'key': 'valor_kwh', 'value': '1.00'},
      {'key': 'moeda', 'value': 'R\$'},
      {'key': 'notificacoes', 'value': 'true'},
      {'key': 'modo_escuro', 'value': 'false'},
      {'key': 'auto_conectar', 'value': 'true'},
    ];
    
    for (var setting in defaultSettings) {
      await db.insert(
        'app_settings',
        setting,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    print('✅ Configurações padrão inseridas');
  }

  // ========== MÉTODOS PARA DADOS DOS SENSORES ==========

  Future<int> insertSensorData(SensorData data) async {
    final db = await database;
    
    try {
      final id = await db.insert(
        'sensor_data', 
        data.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('💾 Dados do sensor inseridos com ID: $id');
      return id;
    } catch (e) {
      print('❌ Erro ao inserir dados do sensor: $e');
      rethrow;
    }
  }

  Future<List<SensorData>> getSensorData(DateTime start, DateTime end) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'sensor_data',
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
        orderBy: 'timestamp ASC',
      );
      
      print('📊 Consulta sensor_data: ${maps.length} registros encontrados');
      return List.generate(maps.length, (i) => SensorData.fromMap(maps[i]));
    } catch (e) {
      print('❌ Erro ao consultar sensor_data: $e');
      rethrow;
    }
  }

  Future<List<SensorData>> getRecentSensorData(int limit) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'sensor_data',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      
      return List.generate(maps.length, (i) => SensorData.fromMap(maps[i]));
    } catch (e) {
      print('❌ Erro ao buscar dados recentes dos sensores: $e');
      rethrow;
    }
  }

  // ========== MÉTODOS PARA DADOS DE ENERGIA ==========

  Future<int> insertEnergyData(EnergyData data) async {
    final db = await database;
    
    try {
      final id = await db.insert(
        'energy_data', 
        data.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('⚡ Dados de energia inseridos com ID: $id');
      return id;
    } catch (e) {
      print('❌ Erro ao inserir dados de energia: $e');
      rethrow;
    }
  }

  Future<List<EnergyData>> getEnergyData(DateTime start, DateTime end) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'energy_data',
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
        orderBy: 'timestamp ASC',
      );
      
      print('📈 Consulta energy_data: ${maps.length} registros encontrados');
      return List.generate(maps.length, (i) => EnergyData.fromMap(maps[i]));
    } catch (e) {
      print('❌ Erro ao consultar energy_data: $e');
      rethrow;
    }
  }

  Future<List<EnergyData>> getDailyEnergyData(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return await getEnergyData(start, end);
  }

  Future<List<EnergyData>> getMonthlyEnergyData(DateTime date) async {
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0, 23, 59, 59);
    return await getEnergyData(start, end);
  }

  // ========== MÉTODOS PARA CONFIGURAÇÕES ==========

  Future<String?> getSetting(String key) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> result = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      
      return result.isNotEmpty ? result.first['value'] as String : null;
    } catch (e) {
      print('❌ Erro ao buscar configuração $key: $e');
      return null;
    }
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    
    try {
      await db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('✅ Configuração salva: $key = $value');
    } catch (e) {
      print('❌ Erro ao salvar configuração $key: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> result = await db.query('app_settings');
      final settings = <String, String>{};
      
      for (var row in result) {
        settings[row['key'] as String] = row['value'] as String;
      }
      
      return settings;
    } catch (e) {
      print('❌ Erro ao buscar todas as configurações: $e');
      return {};
    }
  }

  Future<double> getTensaoRede() async {
    final value = await getSetting('tensao_rede');
    return double.tryParse(value ?? '220.0') ?? 220.0;
  }

  Future<double> getValorKwh() async {
    final value = await getSetting('valor_kwh');
    return double.tryParse(value ?? '1.00') ?? 1.00;
  }

  Future<String> getMoeda() async {
    final value = await getSetting('moeda');
    return value ?? 'R\$';
  }

  // ========== MÉTODOS PARA ESTATÍSTICAS ==========

  Future<Map<String, dynamic>> getEnergyStatistics(DateTime start, DateTime end) async {
    try {
      final data = await getEnergyData(start, end);
      
      if (data.isEmpty) {
        return {
          'totalConsumption': 0.0,
          'totalValue': 0.0,
          'averagePower': 0.0,
          'maxPower': 0.0,
          'totalRecords': 0,
        };
      }

      double totalConsumption = 0.0;
      double totalValue = 0.0;
      double totalPower = 0.0;
      double maxPower = 0.0;

      for (final item in data) {
        totalConsumption += item.consumptionTotal;
        totalValue += item.valorConsumo;
        totalPower += item.powerTotal;
        if (item.powerTotal > maxPower) maxPower = item.powerTotal;
      }

      return {
        'totalConsumption': totalConsumption / 1000, // Converter para kWh
        'totalValue': totalValue,
        'averagePower': totalPower / data.length,
        'maxPower': maxPower,
        'totalRecords': data.length,
        'periodStart': start,
        'periodEnd': end,
      };
    } catch (e) {
      print('❌ Erro ao calcular estatísticas de energia: $e');
      return {
        'totalConsumption': 0.0,
        'totalValue': 0.0,
        'averagePower': 0.0,
        'maxPower': 0.0,
        'totalRecords': 0,
      };
    }
  }

  // ========== MÉTODOS GERAIS DO BANCO ==========

  Future<int> getRecordCount(String tableName) async {
    final db = await database;
    
    try {
      final List<Map<String, dynamic>> result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName'
      );
      return result.first['count'] as int;
    } catch (e) {
      print('❌ Erro ao contar registros da tabela $tableName: $e');
      return 0;
    }
  }

  Future<void> clearOldData(int daysToKeep) async {
    final db = await database;
    
    try {
      final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));
      
      // Limpar dados antigos de ambas as tabelas
      final deletedSensors = await db.delete(
        'sensor_data',
        where: 'timestamp < ?',
        whereArgs: [cutoff.millisecondsSinceEpoch],
      );
      
      final deletedEnergy = await db.delete(
        'energy_data',
        where: 'timestamp < ?',
        whereArgs: [cutoff.millisecondsSinceEpoch],
      );
      
      print('🗑️ $deletedSensors registros de sensores e $deletedEnergy registros de energia removidos');
    } catch (e) {
      print('❌ Erro ao limpar dados antigos: $e');
      rethrow;
    }
  }

  Future<void> initialize() async {
    try {
      final stats = await getDatabaseStats();
      
      print('🗃️ Banco de dados v2 inicializado:');
      print('   - Registros sensor_data: ${stats['sensorRecords']}');
      print('   - Registros energy_data: ${stats['energyRecords']}');
      print('   - Configurações carregadas: ${stats['settingsRecords']}');
      
      // Verificar estrutura das tabelas
      await _verifyTableStructure();
      
      // Limpar dados com mais de 30 dias automaticamente
      await clearOldData(30);
      
    } catch (e) {
      print('❌ Erro na inicialização do banco: $e');
    }
  }

  Future<void> _verifyTableStructure() async {
    try {
      final db = await database;
      
      // Verificar se a tabela sensor_data tem a coluna tomada2
      final sensorColumns = await db.rawQuery('PRAGMA table_info(sensor_data)');
      final hasTomada2 = sensorColumns.any((col) => col['name'] == 'tomada2');
      
      if (!hasTomada2) {
        print('⚠️ Tabela sensor_data precisa ser atualizada');
        // Aqui você poderia adicionar lógica para migração
      } else {
        print('✅ Estrutura das tabelas verificada');
      }
    } catch (e) {
      print('❌ Erro ao verificar estrutura: $e');
    }
  }

  Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final db = await database;
      final sensorCount = await getRecordCount('sensor_data');
      final energyCount = await getRecordCount('energy_data');
      final settingsCount = await getRecordCount('app_settings');
      
      // Data do registro mais antigo e mais recente
      final sensorOldest = await db.rawQuery(
        'SELECT MIN(timestamp) as oldest FROM sensor_data'
      );
      final sensorNewest = await db.rawQuery(
        'SELECT MAX(timestamp) as newest FROM sensor_data'
      );
      
      final energyOldest = await db.rawQuery(
        'SELECT MIN(timestamp) as oldest FROM energy_data'
      );
      final energyNewest = await db.rawQuery(
        'SELECT MAX(timestamp) as newest FROM energy_data'
      );
      
      return {
        'sensorRecords': sensorCount,
        'energyRecords': energyCount,
        'settingsRecords': settingsCount,
        'sensorOldest': sensorOldest.first['oldest'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(sensorOldest.first['oldest'] as int) 
            : null,
        'sensorNewest': sensorNewest.first['newest'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(sensorNewest.first['newest'] as int) 
            : null,
        'energyOldest': energyOldest.first['oldest'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(energyOldest.first['oldest'] as int) 
            : null,
        'energyNewest': energyNewest.first['newest'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(energyNewest.first['newest'] as int) 
            : null,
      };
    } catch (e) {
      print('❌ Erro ao obter estatísticas: $e');
      return {
        'sensorRecords': 0,
        'energyRecords': 0,
        'settingsRecords': 0,
        'sensorOldest': null,
        'sensorNewest': null,
        'energyOldest': null,
        'energyNewest': null,
      };
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      print('🔒 Conexão com o banco fechada');
    }
  }
}