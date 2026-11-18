import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const TomrukOlcumApp());
}

class TomrukOlcumApp extends StatelessWidget {
  const TomrukOlcumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TomrukOlcumAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5A27)),
        useMaterial3: true,
      ),
      home: const AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  final Map<String, double> _kabukOranlari = const {
    'Kızılçam': 12.0,
    'Karaçam': 11.0,
    'Sedir': 10.0,
    'Kayın': 5.0,
    'Meşe': 9.0,
    'Diğer (0%)': 0.0,
  };

  String _seciliTur = 'Kızılçam';
  double _tomrukBoyu = 3.0;
  final List<double> _caplarCm = [18, 22, 26, 31, 34];
  final TextEditingController _capController = TextEditingController();

  double get _kabukOrani => _kabukOranlari[_seciliTur] ?? 0.0;

  double _hacimHesapla(double capCm, {required bool kabuksuz}) {
    final double rMetre = (capCm / 100.0) / 2.0;
    final double brut = pi * rMetre * rMetre * _tomrukBoyu;
    return kabuksuz ? brut * (1.0 - _kabukOrani / 100.0) : brut;
  }

  void _capEkle() {
    final val = double.tryParse(_capController.text.replaceAll(',', '.'));
    if (val != null && val >= 6 && val <= 150) {
      setState(() {
        _caplarCm.add(val);
        _capController.clear();
      });
    }
  }

  @override
  void dispose() {
    _capController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double brutToplam = _caplarCm.fold(
      0.0,
      (sum, d) => sum + _hacimHesapla(d, kabuksuz: false),
    );
    final double netToplam = _caplarCm.fold(
      0.0,
      (sum, d) => sum + _hacimHesapla(d, kabuksuz: true),
    );
    final int inceAdet = _caplarCm.where((d) => d < 20).length;
    final int ortaAdet = _caplarCm.where((d) => d >= 20 && d < 30).length;
    final int kalinAdet = _caplarCm.where((d) => d >= 30).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TomrukOlcumAI (MVP)'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ölçüm Parametreleri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _seciliTur,
                    decoration: const InputDecoration(
                      labelText: 'Ağaç Türü (Kabuk Düşümü)',
                      border: OutlineInputBorder(),
                    ),
                    items: _kabukOranlari.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text('${e.key} (%${e.value.toStringAsFixed(0)})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _seciliTur = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<double>(
                    value: _tomrukBoyu,
                    decoration: const InputDecoration(
                      labelText: 'Tomruk Boyu (m)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [2.0, 2.5, 3.0, 4.0, 5.0]
                        .map(
                          (b) => DropdownMenuItem(
                            value: b,
                            child: Text('${b.toStringAsFixed(1)} m'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _tomrukBoyu = v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Özet Sonuçlar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Toplam Adet: ${_caplarCm.length}'),
                  Text('Kabuklu Hacim: ${brutToplam.toStringAsFixed(3)} m³'),
                  Text(
                    'Kabuksuz Net Hacim: ${netToplam.toStringAsFixed(3)} m³',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(height: 20),
                  Text('İnce (<20 cm): $inceAdet | Orta (20-29 cm): $ortaAdet | Kalın (30+ cm): $kalinAdet'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _capController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Test Çapı Ekle (cm)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _capEkle,
                child: const Text('Ekle'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: List.generate(
              _caplarCm.length,
              (i) => Chip(
                label: Text('${_caplarCm[i].toStringAsFixed(0)} cm'),
                onDeleted: () => setState(() => _caplarCm.removeAt(i)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
