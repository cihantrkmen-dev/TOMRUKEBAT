import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TomrukOlcumApp());
}

// ====================================================================
// 1. ÇEVRİMDIŞI LİSANSLAMA VE GÜVENLİK SERVİSİ (XOR + SHA-256)
// ====================================================================
class LisansServisi {
  static const String gelistiriciMail = 'cihantrkmen@gmail.com';
  static const String _prefTalepKey = 'tomruk_talep_kodu_v1';
  static const String _prefLisansKey = 'tomruk_lisans_anahtari_v1';

  // Gizli Tuz (XOR 0x5A ile gizlenmiş bayt dizisi - düz metin içermez)
  static const int _xorKey = 0x5A;
  static const List<int> _gizliTuzBytes = [
    21, 29, 23, 119, 30, 20, 0, 119, 104, 106, 104, 108, 119,
    25, 19, 18, 27, 20, 119, 14, 15, 8, 17, 23, 31, 20, 119,
    9, 27, 22, 14, 121, 99, 107
  ];

  // Yönetici şifresinin SHA-256 özeti
  static const String _yoneticiSifreHash =
      'fcf9ad9079a8319030d71827281b94f8513c610da250f0de32aa4302e8e3bb5f';

  static String _tuzuCoz() {
    return String.fromCharCodes(_gizliTuzBytes.map((b) => b ^ _xorKey));
  }

  static bool yoneticiSifresiDogrula(String girilenSifre) {
    final digest = sha256.convert(utf8.encode(girilenSifre.trim())).toString();
    return digest == _yoneticiSifreHash;
  }

  /// TALEP-XXXX kodundan OGM-XXXX-XXXX lisans anahtarı üretir
  static String lisansAnahtariUret(String talepKodu) {
    final temizTalep = talepKodu.trim().toUpperCase();
    final girdi = '$temizTalep|${_tuzuCoz()}';
    final hashHex = sha256.convert(utf8.encode(girdi)).toString().toUpperCase();
    return 'OGM-${hashHex.substring(0, 4)}-${hashHex.substring(4, 8)}';
  }

  static Future<String> talepKoduGetirVeyaUret() async {
    final prefs = await SharedPreferences.getInstance();
    String? mevcut = prefs.getString(_prefTalepKey);
    if (mevcut != null && mevcut.startsWith('TALEP-')) {
      return mevcut;
    }
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final kod = List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    final yeniTalep = 'TALEP-$kod';
    await prefs.setString(_prefTalepKey, yeniTalep);
    return yeniTalep;
  }

  static Future<bool> lisansGecerliMi() async {
    final prefs = await SharedPreferences.getInstance();
    final talep = await talepKoduGetirVeyaUret();
    final kayitliLisans = prefs.getString(_prefLisansKey);
    if (kayitliLisans == null) return false;
    return kayitliLisans.trim().toUpperCase() == lisansAnahtariUret(talep);
  }

  static Future<bool> lisansDogrulaVeKaydet(String girilenAnahtar) async {
    final talep = await talepKoduGetirVeyaUret();
    final beklenen = lisansAnahtariUret(talep);
    if (girilenAnahtar.trim().toUpperCase() == beklenen) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLisansKey, beklenen);
      return true;
    }
    return false;
  }
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
      home: const AcilisEkrani(),
    );
  }
}

// ====================================================================
// 2. AÇILIŞ EKRANI (SPLASH SCREEN)
// ====================================================================
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key});

  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> {
  @override
  void initState() {
    super.initState();
    _yonlendir();
  }

  Future<void> _yonlendir() async {
    await Future.delayed(const Duration(seconds: 2));
    final lisansli = await LisansServisi.lisansGecerliMi();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => lisansli ? const KameraOlcumSayfasi() : const LisansEkrani(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F3D1B),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forest, size: 84, color: Colors.lightGreenAccent),
              const SizedBox(height: 16),
              const Text(
                'TomrukOlcumAI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Geliştirici CİHAN TÜRKMEN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Denizli Orman Bölge Müdürlüğü',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: Colors.lightGreenAccent),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// 3. ÇEVRİMDIŞI LİSANS VE GİZLİ YÖNETİCİ PANELİ
// ====================================================================
class LisansEkrani extends StatefulWidget {
  const LisansEkrani({super.key});

  @override
  State<LisansEkrani> createState() => _LisansEkraniState();
}

class _LisansEkraniState extends State<LisansEkrani> {
  String _talepKodu = '...';
  final TextEditingController _lisansController = TextEditingController();
  String? _hataMesaji;

  @override
  void initState() {
    super.initState();
    _talepYukle();
  }

  Future<void> _talepYukle() async {
    final kod = await LisansServisi.talepKoduGetirVeyaUret();
    if (mounted) setState(() => _talepKodu = kod);
  }

  @override
  void dispose() {
    _lisansController.dispose();
    super.dispose();
  }

  Future<void> _lisansAktifle() async {
    final ok = await LisansServisi.lisansDogrulaVeKaydet(_lisansController.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const KameraOlcumSayfasi()),
      );
    } else {
      setState(() => _hataMesaji = 'Geçersiz lisans anahtarı. Lütfen kodu kontrol edin.');
    }
  }

  void _yoneticiPaneliAc() {
    final sifreCtrl = TextEditingController();
    final talepCtrl = TextEditingController(text: _talepKodu);
    String? uretilenAnahtar;
    bool yetkili = false;
    String? sifreHata;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Yönetici Lisans Paneli'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!yetkili) ...[
                    TextField(
                      controller: sifreCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Yönetici Şifresi',
                        errorText: sifreHata,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: talepCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı Talep Kodu (TALEP-XXXX)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setModalState(() {
                          uretilenAnahtar = LisansServisi.lisansAnahtariUret(talepCtrl.text);
                        });
                      },
                      child: const Text('Lisans Anahtarı Üret'),
                    ),
                    if (uretilenAnahtar != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        uretilenAnahtar!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Kopyala'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: uretilenAnahtar!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Lisans anahtarı kopyalandı.')),
                          );
                        },
                      ),
                    ],
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Kapat'),
                ),
                if (!yetkili)
                  FilledButton(
                    onPressed: () {
                      if (LisansServisi.yoneticiSifresiDogrula(sifreCtrl.text)) {
                        setModalState(() {
                          yetkili = true;
                          sifreHata = null;
                        });
                      } else {
                        setModalState(() => sifreHata = 'Hatalı yönetici şifresi');
                      }
                    },
                    child: const Text('Giriş'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lisans Aktivasyonu'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            tooltip: 'Yönetici Paneli',
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: _yoneticiPaneliAc,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.verified_user_outlined, size: 64, color: Color(0xFF2E5A27)),
          const SizedBox(height: 12),
          const Text(
            'Geliştirici CİHAN TÜRKMEN\nDenizli Orman Bölge Müdürlüğü',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Cihaz Talep Kodunuz:', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  SelectableText(
                    _talepKodu,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Talep Kodunu Kopyala'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _talepKodu));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Talep kodu kopyalandı.')),
                      );
                    },
                  ),
                  const Divider(height: 20),
                  const Text(
                    'Lisans anahtarı almak için yukarıdaki talep kodunu aşağıdaki e-posta adresine iletin:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const SelectableText(
                    LisansServisi.gelistiriciMail,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E5A27),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lisansController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Lisans Anahtarı (OGM-XXXX-XXXX)',
              errorText: _hataMesaji,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _lisansAktifle,
            icon: const Icon(Icons.lock_open),
            label: const Text('Lisansı Doğrula ve Başlat'),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// 4. KABUKSUZ KAMERALI TOMRUK ÖLÇÜM MOTORU
// ====================================================================
class TespitEdilenTomruk {
  double xNorm;
  double yNorm;
  double capNorm;
  double capCm;

  TespitEdilenTomruk({
    required this.xNorm,
    required this.yNorm,
    required this.capNorm,
    required this.capCm,
  });
}

class _AdayDaire {
  final double x;
  final double y;
  double r;
  final double skor;
  _AdayDaire(this.x, this.y, this.r, this.skor);
}

enum EtkilesimModu { kalibrasyon, secDuzenle, tomrukEkle }
enum ReferansTipi { aruco50, cubuk100, bilinenTomrukCapi }

class KameraOlcumSayfasi extends StatefulWidget {
  const KameraOlcumSayfasi({super.key});

  @override
  State<KameraOlcumSayfasi> createState() => _KameraOlcumSayfasiState();
}

class _KameraOlcumSayfasiState extends State<KameraOlcumSayfasi> {
  final ImagePicker _picker = ImagePicker();
  final TransformationController _zoomController = TransformationController();
  File? _seciliFoto;
  int _fotoGenislik = 1;
  int _fotoYukseklik = 1;
  bool _isleniyor = false;

  Offset? _refP1;
  Offset? _refP2;
  Offset? _refCenterNorm;
  double? _refCapNorm;
  bool _referansSecili = false;

  ReferansTipi _referansTipi = ReferansTipi.bilinenTomrukCapi;
  double _referansUzunlukCm = 28.0;
  final TextEditingController _bilinenCapController = TextEditingController(text: '28');
  double? _cmPerNormGenislik;

  final List<TespitEdilenTomruk> _tomruklar = [];
  int? _seciliTomrukIdx;
  EtkilesimModu _mod = EtkilesimModu.kalibrasyon;

  double _tomrukBoyu = 3.0;
  final double _varsayilanManuelCapCm = 24.0;

  double get _invAspect => _fotoYukseklik / max(1, _fotoGenislik);

  @override
  void dispose() {
    _bilinenCapController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  void _zoomSifirla() {
    _zoomController.value = Matrix4.identity();
  }

  double _maksimumCakismasizYaricapNorm(double nx, double ny, {int? haricIdx}) {
    double maxR = 0.5;
    for (int i = 0; i < _tomruklar.length; i++) {
      if (i == haricIdx) continue;
      final other = _tomruklar[i];
      final dx = nx - other.xNorm;
      final dy = (ny - other.yNorm) * _invAspect;
      final merkezMesafe = sqrt(dx * dx + dy * dy);
      final otherR = other.capNorm / 2.0;
      final kalanBosluk = merkezMesafe - otherR;
      if (kalanBosluk < maxR) {
        maxR = kalanBosluk;
      }
    }
    return maxR;
  }

  void _referansTipiniGuncelle(ReferansTipi yeniTip) {
    setState(() {
      _referansTipi = yeniTip;
      _referansSecili = false;
      if (yeniTip == ReferansTipi.aruco50) {
        _referansUzunlukCm = 50.0;
        _refCenterNorm = null;
        _refCapNorm = null;
      } else if (yeniTip == ReferansTipi.cubuk100) {
        _referansUzunlukCm = 100.0;
        _refCenterNorm = null;
        _refCapNorm = null;
      } else {
        final girilen = double.tryParse(_bilinenCapController.text.replaceAll(',', '.'));
        _referansUzunlukCm = (girilen != null && girilen >= 5 && girilen <= 200) ? girilen : 28.0;
      }
    });
    _kalibrasyonuHesapla();
  }

  void _bilinenCapDegisti(String val) {
    final girilen = double.tryParse(val.replaceAll(',', '.'));
    if (girilen != null && girilen >= 5 && girilen <= 200) {
      setState(() => _referansUzunlukCm = girilen);
      _kalibrasyonuRefDairedenGuncelle();
    }
  }

  Future<void> _fotoAl(ImageSource kaynak) async {
    final XFile? dosya = await _picker.pickImage(
      source: kaynak,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (dosya == null) return;

    final bytes = await dosya.readAsBytes();
    final decoded = img.decodeImage(bytes);

    _zoomSifirla();
    setState(() {
      _seciliFoto = File(dosya.path);
      _fotoGenislik = decoded?.width ?? 1;
      _fotoYukseklik = decoded?.height ?? 1;
      _refP1 = null;
      _refP2 = null;
      _refCenterNorm = null;
      _refCapNorm = null;
      _referansSecili = false;
      _cmPerNormGenislik = null;
      _tomruklar.clear();
      _seciliTomrukIdx = null;
      _mod = EtkilesimModu.kalibrasyon;
    });
  }

  void _kalibrasyonuHesapla() {
    if (_refP1 == null || _refP2 == null) return;
    final dxNorm = _refP2!.dx - _refP1!.dx;
    final dyNorm = (_refP2!.dy - _refP1!.dy) * _invAspect;
    final capNorm = sqrt(dxNorm * dxNorm + dyNorm * dyNorm);
    if (capNorm < 0.005) return;

    setState(() {
      if (_referansTipi == ReferansTipi.bilinenTomrukCapi) {
        _refCenterNorm = Offset(
          (_refP1!.dx + _refP2!.dx) / 2.0,
          (_refP1!.dy + _refP2!.dy) / 2.0,
        );
        _refCapNorm = capNorm;
      }
      _cmPerNormGenislik = _referansUzunlukCm / capNorm;
      for (final t in _tomruklar) {
        t.capCm = t.capNorm * _cmPerNormGenislik!;
      }
    });
  }

  void _kalibrasyonuRefDairedenGuncelle() {
    if (_referansTipi == ReferansTipi.bilinenTomrukCapi && _refCapNorm != null && _refCapNorm! > 0.005) {
      setState(() {
        _cmPerNormGenislik = _referansUzunlukCm / _refCapNorm!;
        for (final t in _tomruklar) {
          t.capCm = t.capNorm * _cmPerNormGenislik!;
        }
      });
    } else {
      _kalibrasyonuHesapla();
    }
  }

  void _referansMerkezKaydir(double dxNorm, double dyNorm) {
    if (_refCenterNorm == null) return;
    setState(() {
      _refCenterNorm = Offset(
        (_refCenterNorm!.dx + dxNorm).clamp(0.01, 0.99),
        (_refCenterNorm!.dy + dyNorm).clamp(0.01, 0.99),
      );
    });
  }

  void _referansCemberBoyutGuncelle(double yeniCapNorm) {
    setState(() {
      _refCapNorm = yeniCapNorm.clamp(0.015, 0.60);
    });
    _kalibrasyonuRefDairedenGuncelle();
  }

  Future<void> _otomatikTespitCalistir() async {
    if (_seciliFoto == null) return;
    if (_cmPerNormGenislik == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _referansTipi == ReferansTipi.bilinenTomrukCapi
                ? 'Önce çapını bildiğiniz tomruğun iki karşı kenarına dokunarak kırmızı referans çemberini oluşturun.'
                : 'Önce fotoğraf üzerinde referans nesnenin iki ucuna dokunarak kalibrasyon yapın.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isleniyor = true;
      _seciliTomrukIdx = null;
      _referansSecili = false;
    });

    try {
      final Uint8List bytes = await _seciliFoto!.readAsBytes();
      final img.Image? orijinal = img.decodeImage(bytes);
      if (orijinal == null) return;

      const int w = 360;
      final int h = max(1, (orijinal.height * w / orijinal.width).round());
      final img.Image kucuk = img.copyResize(orijinal, width: w, height: h);

      final List<int> mask = List<int>.filled(w * h, 0);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = kucuk.getPixel(x, y);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          final luma = 0.299 * r + 0.587 * g + 0.114 * b;
          final isGreen = g > r + 6 && g > b + 6;
          final isSky = b > r + 5;
          final isWood = !isGreen && !isSky && luma > 80 && luma < 245 && r >= b + 12 && r > 85 && g > 55;
          if (isWood) {
            mask[y * w + x] = 1;
          }
        }
      }

      final Float64List dist = Float64List(w * h);
      const double inf = 1e6;
      for (int i = 0; i < w * h; i++) {
        dist[i] = mask[i] == 1 ? inf : 0.0;
      }

      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          final idx = y * w + x;
          if (dist[idx] == 0.0) continue;
          double d = dist[idx];
          d = min(d, dist[idx - 1] + 1.0);
          d = min(d, dist[idx - w] + 1.0);
          d = min(d, dist[idx - w - 1] + 1.414);
          d = min(d, dist[idx - w + 1] + 1.414);
          dist[idx] = d;
        }
      }

      for (int y = h - 2; y >= 1; y--) {
        for (int x = w - 2; x >= 1; x--) {
          final idx = y * w + x;
          if (dist[idx] == 0.0) continue;
          double d = dist[idx];
          d = min(d, dist[idx + 1] + 1.0);
          d = min(d, dist[idx + w] + 1.0);
          d = min(d, dist[idx + w + 1] + 1.414);
          d = min(d, dist[idx + w - 1] + 1.414);
          dist[idx] = d;
        }
      }

      final double minR = max(3.5, (6.0 / _cmPerNormGenislik!) * w / 2.0);
      final double maxR = min(w * 0.18, (120.0 / _cmPerNormGenislik!) * w / 2.0);
      final List<_AdayDaire> adaylar = [];

      for (int y = 2; y < h - 2; y++) {
        for (int x = 2; x < w - 2; x++) {
          final val = dist[y * w + x];
          if (val < minR || val > maxR) continue;

          bool isPeak = true;
          for (int dy = -2; dy <= 2 && isPeak; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
              if (dx == 0 && dy == 0) continue;
              if (dist[(y + dy) * w + (x + dx)] > val) {
                isPeak = false;
                break;
              }
            }
          }
          if (!isPeak) continue;

          final int ri = val.round();
          int toplam = 0;
          int dolu = 0;
          for (int dy = -ri; dy <= ri; dy += 2) {
            for (int dx = -ri; dx <= ri; dx += 2) {
              if (dx * dx + dy * dy <= ri * ri) {
                final nx = x + dx;
                final ny = y + dy;
                if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
                  toplam++;
                  if (mask[ny * w + nx] == 1) dolu++;
                }
              }
            }
          }
          final doluluk = toplam > 0 ? dolu / toplam : 0.0;
          if (doluluk >= 0.68) {
            adaylar.add(_AdayDaire(x.toDouble(), y.toDouble(), val * 1.04, val * doluluk));
          }
        }
      }

      // Kesin sıfır çakışma (d >= r1 + r2)
      adaylar.sort((a, b) => b.skor.compareTo(a.skor));
      final List<_AdayDaire> secilenler = [];
      for (final aday in adaylar) {
        double izinVerilenMaxR = aday.r;
        bool gecersiz = false;

        for (final s in secilenler) {
          final dx = aday.x - s.x;
          final dy = aday.y - s.y;
          final merkezMesafe = sqrt(dx * dx + dy * dy);
          final kalanBosluk = merkezMesafe - s.r;

          if (kalanBosluk < minR) {
            gecersiz = true;
            break;
          }
          if (kalanBosluk < izinVerilenMaxR) {
            izinVerilenMaxR = kalanBosluk;
          }
        }

        if (!gecersiz && izinVerilenMaxR >= minR) {
          aday.r = izinVerilenMaxR;
          secilenler.add(aday);
        }
      }

      final List<TespitEdilenTomruk> bulunanlar = [];
      for (final s in secilenler) {
        final capNorm = (s.r * 2.0) / w;
        final capCm = capNorm * _cmPerNormGenislik!;
        if (capCm >= 6.0 && capCm <= 150.0) {
          bulunanlar.add(
            TespitEdilenTomruk(
              xNorm: s.x / w,
              yNorm: s.y / h,
              capNorm: capNorm,
              capCm: capCm,
            ),
          );
        }
      }

      setState(() {
        _tomruklar
          ..clear()
          ..addAll(bulunanlar);
        _mod = EtkilesimModu.secDuzenle;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${bulunanlar.length} adet tomruk tespit edildi. Daireye dokunup merkezini kaydırabilir veya çapını ayarlayabilirsiniz.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  void _seciliTomrukMerkezKaydir(double dxNorm, double dyNorm) {
    if (_seciliTomrukIdx == null || _seciliTomrukIdx! >= _tomruklar.length) return;
    final t = _tomruklar[_seciliTomrukIdx!];
    final yeniX = (t.xNorm + dxNorm).clamp(0.01, 0.99);
    final yeniY = (t.yNorm + dyNorm).clamp(0.01, 0.99);

    final maxRNorm = _maksimumCakismasizYaricapNorm(
      yeniX,
      yeniY,
      haricIdx: _seciliTomrukIdx,
    );
    if (t.capNorm / 2.0 > maxRNorm) return;

    setState(() {
      t.xNorm = yeniX;
      t.yNorm = yeniY;
    });
  }

  void _seciliTomrukCapGuncelle(double yeniCapCm) {
    if (_seciliTomrukIdx == null || _seciliTomrukIdx! >= _tomruklar.length) return;
    final t = _tomruklar[_seciliTomrukIdx!];
    double hedefCapCm = yeniCapCm.clamp(6.0, 150.0);

    if (_cmPerNormGenislik != null && _cmPerNormGenislik! > 0) {
      final maxRNorm = _maksimumCakismasizYaricapNorm(
        t.xNorm,
        t.yNorm,
        haricIdx: _seciliTomrukIdx,
      );
      final maxCapCm = max(6.0, (maxRNorm * 2.0) * _cmPerNormGenislik!);
      if (hedefCapCm > maxCapCm) {
        hedefCapCm = maxCapCm;
      }
      setState(() {
        t.capCm = hedefCapCm;
        t.capNorm = hedefCapCm / _cmPerNormGenislik!;
      });
    } else {
      setState(() => t.capCm = hedefCapCm);
    }
  }

  void _fotoyaDokunuldu(TapDownDetails details, Size widgetSize) {
    final nx = (details.localPosition.dx / widgetSize.width).clamp(0.0, 1.0);
    final ny = (details.localPosition.dy / widgetSize.height).clamp(0.0, 1.0);

    if (_mod == EtkilesimModu.kalibrasyon) {
      setState(() {
        _referansSecili = false;
        if (_refP1 == null || (_refP1 != null && _refP2 != null)) {
          _refP1 = Offset(nx, ny);
          _refP2 = null;
          _refCenterNorm = null;
          _refCapNorm = null;
          _cmPerNormGenislik = null;
        } else {
          _refP2 = Offset(nx, ny);
        }
      });
      if (_refP1 != null && _refP2 != null) {
        _kalibrasyonuHesapla();
      }
    } else if (_mod == EtkilesimModu.secDuzenle) {
      double minMesafe = 0.08;
      int? enYakinIdx;
      bool refEnYakin = false;

      if (_referansTipi == ReferansTipi.bilinenTomrukCapi && _refCenterNorm != null) {
        final dx = _refCenterNorm!.dx - nx;
        final dy = (_refCenterNorm!.dy - ny) * _invAspect;
        final d = sqrt(dx * dx + dy * dy);
        if (d < minMesafe) {
          minMesafe = d;
          refEnYakin = true;
        }
      }

      for (int i = 0; i < _tomruklar.length; i++) {
        final dx = _tomruklar[i].xNorm - nx;
        final dy = (_tomruklar[i].yNorm - ny) * _invAspect;
        final d = sqrt(dx * dx + dy * dy);
        if (d < minMesafe) {
          minMesafe = d;
          enYakinIdx = i;
          refEnYakin = false;
        }
      }

      setState(() {
        if (refEnYakin) {
          _referansSecili = true;
          _seciliTomrukIdx = null;
        } else {
          _referansSecili = false;
          _seciliTomrukIdx = enYakinIdx;
        }
      });
    } else if (_mod == EtkilesimModu.tomrukEkle) {
      final maxRNorm = _maksimumCakismasizYaricapNorm(nx, ny);
      final minRNorm = (_cmPerNormGenislik != null && _cmPerNormGenislik! > 0)
          ? (6.0 / _cmPerNormGenislik!) / 2.0
          : 0.015;

      if (maxRNorm < minRNorm) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu alan mevcut bir tomrukla çakışıyor; boş bir merkeze dokunun.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final istenenCapNorm = _cmPerNormGenislik != null
          ? _varsayilanManuelCapCm / _cmPerNormGenislik!
          : 0.06;
      final gercekCapNorm = min(istenenCapNorm, maxRNorm * 2.0);
      final gercekCapCm = _cmPerNormGenislik != null
          ? gercekCapNorm * _cmPerNormGenislik!
          : _varsayilanManuelCapCm;

      setState(() {
        _tomruklar.add(
          TespitEdilenTomruk(
            xNorm: nx,
            yNorm: ny,
            capNorm: gercekCapNorm,
            capCm: gercekCapCm,
          ),
        );
        _referansSecili = false;
        _seciliTomrukIdx = _tomruklar.length - 1;
      });
    }
  }

  /// Kabuksuz net hacim: Ondalık çaplar tam sayıya AŞAĞI yuvarlanarak (floor) hesaplanır
  double _netHacimHesapla(double capCm) {
    final int tamCapCm = capCm.floor();
    final rMetre = (tamCapCm / 100.0) / 2.0;
    return pi * rMetre * rMetre * _tomrukBoyu;
  }

  Widget _yonTuslari({required void Function(double dx, double dy) onKaydir}) {
    const double adim = 0.004;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Merkez: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => onKaydir(-adim, 0),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_upward),
          onPressed: () => onKaydir(0, -adim),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_downward),
          onPressed: () => onKaydir(0, adim),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => onKaydir(adim, 0),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final toplamHacim = _tomruklar.fold(0.0, (s, t) => s + _netHacimHesapla(t.capCm));
    final ince = _tomruklar.where((t) => t.capCm.floor() < 20).length;
    final orta = _tomruklar.where((t) => t.capCm.floor() >= 20 && t.capCm.floor() < 30).length;
    final kalin = _tomruklar.where((t) => t.capCm.floor() >= 30).length;
    final seciliTomruk =
        (_seciliTomrukIdx != null && _seciliTomrukIdx! < _tomruklar.length) ? _tomruklar[_seciliTomrukIdx!] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TomrukOlcumAI'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          if (_seciliFoto != null)
            IconButton(
              tooltip: 'Yakınlaştırmayı Sıfırla',
              icon: const Icon(Icons.zoom_out_map),
              onPressed: _zoomSifirla,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _fotoAl(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Kamera ile Çek'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _fotoAl(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galeriden Seç'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_seciliFoto != null) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: _fotoGenislik / max(1, _fotoYukseklik),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    return InteractiveViewer(
                      transformationController: _zoomController,
                      minScale: 1.0,
                      maxScale: 6.0,
                      child: GestureDetector(
                        onTapDown: (d) => _fotoyaDokunuldu(d, Size(w, h)),
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(_seciliFoto!, fit: BoxFit.fill),
                              CustomPaint(
                                painter: _OlcumOverlayPainter(
                                  refP1: _refP1,
                                  refP2: _refP2,
                                  refCenterNorm: _refCenterNorm,
                                  refCapNorm: _refCapNorm,
                                  refCapCm: _referansUzunlukCm,
                                  referansSecili: _referansSecili,
                                  tomruklar: _tomruklar,
                                  seciliIdx: _seciliTomrukIdx,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'İpucu: Hassas işaretleme için fotoğrafı iki parmakla yakınlaştırabilirsiniz.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ),
            SegmentedButton<EtkilesimModu>(
              segments: const [
                ButtonSegment(value: EtkilesimModu.kalibrasyon, label: Text('1. Referans')),
                ButtonSegment(value: EtkilesimModu.secDuzenle, label: Text('2. Düzenle')),
                ButtonSegment(value: EtkilesimModu.tomrukEkle, label: Text('3. Ekle')),
              ],
              selected: {_mod},
              onSelectionChanged: (s) => setState(() => _mod = s.first),
            ),
            if (_referansSecili && _refCenterNorm != null && _refCapNorm != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        'Kırmızı Referans Tomruk (${_referansUzunlukCm.floor()} cm) İnce Ayar',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      _yonTuslari(onKaydir: _referansMerkezKaydir),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () => _referansCemberBoyutGuncelle(_refCapNorm! - 0.003),
                          ),
                          Expanded(
                            child: Slider(
                              activeColor: Colors.red,
                              value: _refCapNorm!.clamp(0.015, 0.50),
                              min: 0.015,
                              max: 0.50,
                              onChanged: _referansCemberBoyutGuncelle,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.red),
                            onPressed: () => _referansCemberBoyutGuncelle(_refCapNorm! + 0.003),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (seciliTomruk != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Seçili Çap: ${seciliTomruk.capCm.floor()} cm (Ham: ${seciliTomruk.capCm.toStringAsFixed(1)})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            tooltip: 'Bu Tomruğu Sil',
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _tomruklar.removeAt(_seciliTomrukIdx!);
                                _seciliTomrukIdx = null;
                              });
                            },
                          ),
                        ],
                      ),
                      _yonTuslari(onKaydir: _seciliTomrukMerkezKaydir),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _seciliTomrukCapGuncelle(seciliTomruk.capCm - 1.0),
                          ),
                          Expanded(
                            child: Slider(
                              value: seciliTomruk.capCm.clamp(6.0, 100.0),
                              min: 6.0,
                              max: 100.0,
                              divisions: 94,
                              label: '${seciliTomruk.capCm.floor()} cm',
                              onChanged: _seciliTomrukCapGuncelle,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _seciliTomrukCapGuncelle(seciliTomruk.capCm + 1.0),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ReferansTipi>(
                    value: _referansTipi,
                    decoration: const InputDecoration(
                      labelText: 'Referans Yöntemi',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: ReferansTipi.bilinenTomrukCapi, child: Text('Bilinen Tomruk Çapı')),
                      DropdownMenuItem(value: ReferansTipi.aruco50, child: Text('50 cm Levha')),
                      DropdownMenuItem(value: ReferansTipi.cubuk100, child: Text('100 cm Çubuk')),
                    ],
                    onChanged: (v) {
                      if (v != null) _referansTipiniGuncelle(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _isleniyor ? null : _otomatikTespitCalistir,
                  icon: _isleniyor
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: const Text('Otomatik Say'),
                ),
              ],
            ),
            if (_referansTipi == ReferansTipi.bilinenTomrukCapi) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _bilinenCapController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Referans Tomruk Çapı (cm)',
                  helperText: 'İki karşı kenarına dokunduğunuzda kırmızı çember oluşur. Düzenle modunda ince ayar yapabilirsiniz.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _bilinenCapDegisti,
              ),
            ],
          ] else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Başlamak için "Kamera ile Çek" veya "Galeriden Seç" butonuna basın.\n\n'
                  '1) Referans tomruğun iki karşı kenarına dokunarak kırmızı çemberi oluşturun.\n'
                  '2) "Otomatik Say" ile çakışmasız tomruk adet ve çaplarını çıkarın.\n'
                  '3) Düzenle modunda hem kırmızı referansın hem diğer tomrukların merkez ve çapını ince ayarlayın.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<double>(
                    value: _tomrukBoyu,
                    decoration: const InputDecoration(
                      labelText: 'Tomruk Boyu (m)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [2.0, 2.5, 3.0, 4.0, 5.0]
                        .map((b) => DropdownMenuItem(value: b, child: Text('$b m')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _tomrukBoyu = v);
                    },
                  ),
                  const Divider(height: 20),
                  Text(
                    'Toplam Adet: ${_tomruklar.length}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Toplam Net Hacim (Kabuksuz): ${toplamHacim.toStringAsFixed(3)} m³',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('İnce (<20 cm): $ince | Orta (20-29 cm): $orta | Kalın (30+ cm): $kalin'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OlcumOverlayPainter extends CustomPainter {
  final Offset? refP1;
  final Offset? refP2;
  final Offset? refCenterNorm;
  final double? refCapNorm;
  final double refCapCm;
  final bool referansSecili;
  final List<TespitEdilenTomruk> tomruklar;
  final int? seciliIdx;

  _OlcumOverlayPainter({
    required this.refP1,
    required this.refP2,
    required this.refCenterNorm,
    required this.refCapNorm,
    required this.refCapCm,
    required this.referansSecili,
    required this.tomruklar,
    required this.seciliIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (refCenterNorm != null && refCapNorm != null) {
      final center = Offset(refCenterNorm!.dx * size.width, refCenterNorm!.dy * size.height);
      final radius = max(4.0, (refCapNorm! * size.width) / 2.0);
      final refCirclePaint = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = referansSecili ? 3.5 : 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, radius, refCirclePaint);

      final tp = TextPainter(
        text: TextSpan(
          text: 'REF ${refCapCm.floor()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.redAccent,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    } else if (refP1 != null) {
      final refPaint = Paint()
        ..color = Colors.amber
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final p1 = Offset(refP1!.dx * size.width, refP1!.dy * size.height);
      canvas.drawCircle(p1, 5, Paint()..color = Colors.amber);
      if (refP2 != null) {
        final p2 = Offset(refP2!.dx * size.width, refP2!.dy * size.height);
        canvas.drawCircle(p2, 5, Paint()..color = Colors.amber);
        canvas.drawLine(p1, p2, refPaint);
      }
    }

    for (int i = 0; i < tomruklar.length; i++) {
      final t = tomruklar[i];
      final isSelected = i == seciliIdx;
      final logPaint = Paint()
        ..color = isSelected ? Colors.cyanAccent : Colors.lightGreenAccent
        ..strokeWidth = isSelected ? 3.0 : 1.8
        ..style = PaintingStyle.stroke;

      final center = Offset(t.xNorm * size.width, t.yNorm * size.height);
      final radius = max(3.0, (t.capNorm * size.width) / 2.0);
      canvas.drawCircle(center, radius, logPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${t.capCm.floor()}',
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            backgroundColor: isSelected ? Colors.cyanAccent : Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _OlcumOverlayPainter oldDelegate) => true;
}
