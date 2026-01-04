class SensorData {
  final int? id;
  final DateTime timestamp;
  final int luminosidade;
  final bool presenca;
  final bool zona1;
  final bool zona2;
  final bool zona3;
  final bool tomada1; // AGORA separado por tomada
  final bool tomada2; // NOVO campo
  final bool modoAutomatico;

  SensorData({
    this.id,
    required this.timestamp,
    required this.luminosidade,
    required this.presenca,
    required this.zona1,
    required this.zona2,
    required this.zona3,
    required this.tomada1,
    required this.tomada2,
    required this.modoAutomatico,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'luminosidade': luminosidade,
      'presenca': presenca ? 1 : 0,
      'zona1': zona1 ? 1 : 0,
      'zona2': zona2 ? 1 : 0,
      'zona3': zona3 ? 1 : 0,
      'tomada1': tomada1 ? 1 : 0, // AGORA separado
      'tomada2': tomada2 ? 1 : 0, // NOVO
      'modoAutomatico': modoAutomatico ? 1 : 0,
    };
  }

  factory SensorData.fromMap(Map<String, dynamic> map) {
    return SensorData(
      id: map['id'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      luminosidade: map['luminosidade'],
      presenca: map['presenca'] == 1,
      zona1: map['zona1'] == 1,
      zona2: map['zona2'] == 1,
      zona3: map['zona3'] == 1,
      tomada1: map['tomada1'] == 1, // AGORA separado
      tomada2: map['tomada2'] == 1, // NOVO
      modoAutomatico: map['modoAutomatico'] == 1,
    );
  }

  // Método para criar uma cópia atualizada
  SensorData copyWith({
    int? id,
    DateTime? timestamp,
    int? luminosidade,
    bool? presenca,
    bool? zona1,
    bool? zona2,
    bool? zona3,
    bool? tomada1,
    bool? tomada2,
    bool? modoAutomatico,
  }) {
    return SensorData(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      luminosidade: luminosidade ?? this.luminosidade,
      presenca: presenca ?? this.presenca,
      zona1: zona1 ?? this.zona1,
      zona2: zona2 ?? this.zona2,
      zona3: zona3 ?? this.zona3,
      tomada1: tomada1 ?? this.tomada1,
      tomada2: tomada2 ?? this.tomada2,
      modoAutomatico: modoAutomatico ?? this.modoAutomatico,
    );
  }

  // Método para verificar se todos os dispositivos estão ligados
  bool get todosLigados {
    return zona1 && zona2 && zona3 && tomada1 && tomada2;
  }

  // Método para verificar se todos os dispositivos estão desligados
  bool get todosDesligados {
    return !zona1 && !zona2 && !zona3 && !tomada1 && !tomada2;
  }

  // Método para contar dispositivos ligados
  int get dispositivosLigados {
    int count = 0;
    if (zona1) count++;
    if (zona2) count++;
    if (zona3) count++;
    if (tomada1) count++;
    if (tomada2) count++;
    return count;
  }

  @override
  String toString() {
    return 'SensorData{id: $id, timestamp: $timestamp, luminosidade: $luminosidade, presenca: $presenca, zonas: $zona1,$zona2,$zona3, tomadas: $tomada1,$tomada2, modoAuto: $modoAutomatico}';
  }
}