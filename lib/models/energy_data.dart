class EnergyData {
  final int? id;
  final DateTime timestamp;
  final double powerTotal;
  final double powerZone1;
  final double powerZone2;
  final double powerZone3;
  final double powerTomada1;
  final double powerTomada2;
  final double consumptionTotal;
  final double timeZone1;
  final double timeZone2;
  final double timeZone3;
  final double timeTomada1;
  final double timeTomada2;
  final double timePresence;
  
  // NOVOS campos para valor monetário
  final double valorConsumo;
  final String moeda;

  EnergyData({
    this.id,
    required this.timestamp,
    required this.powerTotal,
    required this.powerZone1,
    required this.powerZone2,
    required this.powerZone3,
    required this.powerTomada1,
    required this.powerTomada2,
    required this.consumptionTotal,
    required this.timeZone1,
    required this.timeZone2,
    required this.timeZone3,
    required this.timeTomada1,
    required this.timeTomada2,
    required this.timePresence,
    this.valorConsumo = 0.0,
    this.moeda = 'R\$',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'power_total': powerTotal,
      'power_zone1': powerZone1,
      'power_zone2': powerZone2,
      'power_zone3': powerZone3,
      'power_tomada1': powerTomada1,
      'power_tomada2': powerTomada2,
      'consumption_total': consumptionTotal,
      'valor_consumo': valorConsumo, // NOVO campo
      'moeda': moeda, // NOVO campo
      'time_zone1': timeZone1,
      'time_zone2': timeZone2,
      'time_zone3': timeZone3,
      'time_tomada1': timeTomada1,
      'time_tomada2': timeTomada2,
      'time_presence': timePresence,
    };
  }

  factory EnergyData.fromMap(Map<String, dynamic> map) {
    return EnergyData(
      id: map['id'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      powerTotal: map['power_total']?.toDouble() ?? 0.0,
      powerZone1: map['power_zone1']?.toDouble() ?? 0.0,
      powerZone2: map['power_zone2']?.toDouble() ?? 0.0,
      powerZone3: map['power_zone3']?.toDouble() ?? 0.0,
      powerTomada1: map['power_tomada1']?.toDouble() ?? 0.0,
      powerTomada2: map['power_tomada2']?.toDouble() ?? 0.0,
      consumptionTotal: map['consumption_total']?.toDouble() ?? 0.0,
      valorConsumo: map['valor_consumo']?.toDouble() ?? 0.0, // NOVO
      moeda: map['moeda']?.toString() ?? 'R\$', // NOVO
      timeZone1: map['time_zone1']?.toDouble() ?? 0.0,
      timeZone2: map['time_zone2']?.toDouble() ?? 0.0,
      timeZone3: map['time_zone3']?.toDouble() ?? 0.0,
      timeTomada1: map['time_tomada1']?.toDouble() ?? 0.0,
      timeTomada2: map['time_tomada2']?.toDouble() ?? 0.0,
      timePresence: map['time_presence']?.toDouble() ?? 0.0,
    );
  }

  // Método para calcular valor monetário do consumo
  double calcularValor(double valorKwh) {
    return (consumptionTotal / 1000) * valorKwh;
  }

  // Método para criar uma cópia atualizada
  EnergyData copyWith({
    int? id,
    DateTime? timestamp,
    double? powerTotal,
    double? powerZone1,
    double? powerZone2,
    double? powerZone3,
    double? powerTomada1,
    double? powerTomada2,
    double? consumptionTotal,
    double? valorConsumo,
    String? moeda,
    double? timeZone1,
    double? timeZone2,
    double? timeZone3,
    double? timeTomada1,
    double? timeTomada2,
    double? timePresence,
  }) {
    return EnergyData(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      powerTotal: powerTotal ?? this.powerTotal,
      powerZone1: powerZone1 ?? this.powerZone1,
      powerZone2: powerZone2 ?? this.powerZone2,
      powerZone3: powerZone3 ?? this.powerZone3,
      powerTomada1: powerTomada1 ?? this.powerTomada1,
      powerTomada2: powerTomada2 ?? this.powerTomada2,
      consumptionTotal: consumptionTotal ?? this.consumptionTotal,
      valorConsumo: valorConsumo ?? this.valorConsumo,
      moeda: moeda ?? this.moeda,
      timeZone1: timeZone1 ?? this.timeZone1,
      timeZone2: timeZone2 ?? this.timeZone2,
      timeZone3: timeZone3 ?? this.timeZone3,
      timeTomada1: timeTomada1 ?? this.timeTomada1,
      timeTomada2: timeTomada2 ?? this.timeTomada2,
      timePresence: timePresence ?? this.timePresence,
    );
  }

  @override
  String toString() {
    return 'EnergyData{id: $id, timestamp: $timestamp, powerTotal: $powerTotal W, consumptionTotal: $consumptionTotal Wh, valor: $moeda $valorConsumo}';
  }
}