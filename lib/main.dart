import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  runApp(const EnergyControlApp());
}

class EnergyControlApp extends StatelessWidget {
  const EnergyControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle de Energia Inteligente',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const App(),
      debugShowCheckedModeBanner: false,
    );
  }
}