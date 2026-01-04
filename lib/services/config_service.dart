// config_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'config.db');
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE config(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    
    // Inserir valores padrão
    await db.insert('config', {'key': 'tensao_rede', 'value': '220.0'});
    await db.insert('config', {'key': 'valor_kwh', 'value': '1.00'});
    await db.insert('config', {'key': 'moeda', 'value': 'R\$'});
    await db.insert('config', {'key': 'notificacoes', 'value': 'true'});
  }

  Future<String?> getConfig(String key) async {
    final db = await database;
    final result = await db.query(
      'config',
      where: 'key = ?',
      whereArgs: [key],
    );
    
    return result.isNotEmpty ? result.first['value'] as String : null;
  }

  Future<void> setConfig(String key, String value) async {
    final db = await database;
    await db.insert(
      'config',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAllConfigs() async {
    final db = await database;
    final results = await db.query('config');
    
    final configs = <String, String>{};
    for (var row in results) {
      configs[row['key'] as String] = row['value'] as String;
    }
    
    return configs;
  }
}