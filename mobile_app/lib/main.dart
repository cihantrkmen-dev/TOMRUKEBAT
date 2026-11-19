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

  static const int _xorKey = 0x5A;
  static const List<int> _gizliTuzBytes = [
    21, 29, 23, 119, 30, 20, 0, 119, 104, 106, 104, 108, 119,
    25, 19, 18, 27, 20, 119, 14, 15, 8, 17, 23, 31, 20, 119,
    9, 27, 22, 14, 121, 99, 107
  ];

  static const String _yoneticiSifreHash =
      'fcf9ad9079a8319030d71827281b94f8513c610da250f0de32aa4302e8e3bb5f';

  static String _tuzuCoz() {
    return String.fromCharCodes(_gizliTuzBytes.map((b) => b ^ _xorKey));
  }

  static bool yoneticiSifresiDogrula(String girilenSifre) {
    final digest = sha256.convert(utf8.encode(girilenSifre.trim())).toString();
    return digest == _yoneticiSifreHash;
  }

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

  static void yoneticiPaneliGoster(BuildContext context, {String varsayilanTalep = ''}) {
    final sifreCtrl = TextEditingController();
    final talepCtrl = TextEditingController(text: varsayilanTalep);
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
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı Talep Kodu (TALEP-XXXX)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        if (talepCtrl.text.trim().isEmpty) return;
                        setModalState(() {
                          uretilenAnahtar = lisansAnahtariUret(talepCtrl.text);
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
                      if (yoneticiSifresiDogrula(sifreCtrl.text)) {
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
// 3. ÇEVRİMDIŞI LİSANS EKRANI
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
            onPressed: () => LisansServisi.yoneticiPaneliGoster(
              context,
              varsayilanTalep: _talepKodu,
            ),
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
// 4. HASSAS KABUKSUZ ÖLÇÜM MOTORU (ÇİFT REF + ROI + MORFOLOJİ)
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

enum EtkilesimModu { ref1, ref2, roiAlani, secDuzenle, tomrukEkle }
enum SeciliHedef { hicbiri, ref1, ref2, tomruk }

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

  // Ref-1 (Kırmızı - Zorunlu)
  Offset? _ref1P1;
  Offset? _ref1Center;
  double? _ref1CapNorm;
  double _ref1CapCm = 25.0;
  final TextEditingController _ref1CapCtrl = TextEditingController(text: '25');

  // Ref-2 (Turuncu - İsteğe Bağlı Perspektif Referansı)
  Offset? _ref2P1;
  Offset? _ref2Center;
  double? _ref2CapNorm;
  double _ref2CapCm = 25.0;
  final TextEditingController _ref2CapCtrl = TextEditingController(text: '25');

  // İstif Çerçevesi (ROI - İsteğe Bağlı)
  Offset? _roiP1;
  Rect? _roiNorm;

  // Tespit edilen tomruklar
  final List<TespitEdilenTomruk> _tomruklar = [];
  SeciliHedef _seciliHedef = SeciliHedef.hicbiri;
  int? _seciliTomrukIdx;
  EtkilesimModu _mod = EtkilesimModu.ref1;

  double _emvalBoyu = 3.0;
  final TextEditingController _emvalBoyuController = TextEditingController(text: '3.0');
  final double _varsayilanManuelCapCm = 24.0;

  double get _invAspect => _fotoYukseklik / max(1, _fotoGenislik);

  bool get _ref1Hazir => _ref1Center != null && _ref1CapNorm != null && _ref1CapNorm! > 0.005;
  bool get _ref2Hazir => _ref2Center != null && _ref2CapNorm != null && _ref2CapNorm! > 0.005;

  /// Verilen (xNorm, yNorm) konumundaki yerel ölçeği (cm / birim genişlik) hesaplar.
  /// Ref-2 varsa iki referans arasında doğrusal perspektif interpolasyonu yapar.
  double? _olcekHesapla(double xNorm, double yNorm) {
    if (!_ref1Hazir) return null;
    final double scale1 = _ref1CapCm / _ref1CapNorm!;
    if (!_ref2Hazir) return scale1;

    final double scale2 = _ref2CapCm / _ref2CapNorm!;
    final double vx = _ref2Center!.dx - _ref1Center!.dx;
    final double vy = (_ref2Center!.dy - _ref1Center!.dy) * _invAspect;
    final double lenSq = vx * vx + vy * vy;
    if (lenSq < 1e-6) return (scale1 + scale2) / 2.0;

    final double px = xNorm - _ref1Center!.dx;
    final double py = (yNorm - _ref1Center!.dy) * _invAspect;
    final double t = ((px * vx + py * vy) / lenSq).clamp(-0.25, 1.25);
    return max(5.0, scale1 + t * (scale2 - scale1));
  }

  void _tumTomrukCaplariniGuncelle() {
    if (!_ref1Hazir) return;
    for (final t in _tomruklar) {
      final sc = _olcekHesapla(t.xNorm, t.yNorm);
      if (sc != null) {
        t.capCm = t.capNorm * sc;
      }
    }
  }

  @override
  void dispose() {
    _ref1CapCtrl.dispose();
    _ref2CapCtrl.dispose();
    _emvalBoyuController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  void _zoomSifirla() {
    _zoomController.value = Matrix4.identity();
  }

  void _emvalBoyuDegisti(String val) {
    final girilen = double.tryParse(val.replaceAll(',', '.'));
    if (girilen != null && girilen > 0 && girilen <= 30.0) {
      setState(() => _emvalBoyu = girilen);
    }
  }

  /// Hem tespit edilen tomruklarla hem de kilitli Ref-1 / Ref-2 çemberleriyle
  /// kesin sıfır çakışma (teğet sınırı) kontrolü yapar.
  double _maksimumCakismasizYaricapNorm(double nx, double ny, {int? haricIdx}) {
    double maxR = 0.5;

    void kontrolEt(double ox, double oy, double oCapNorm) {
      final dx = nx - ox;
      final dy = (ny - oy) * _invAspect;
      final merkezMesafe = sqrt(dx * dx + dy * dy);
      final kalanBosluk = merkezMesafe - (oCapNorm / 2.0);
      if (kalanBosluk < maxR) {
        maxR = kalanBosluk;
      }
    }

    if (_ref1Hazir) kontrolEt(_ref1Center!.dx, _ref1Center!.dy, _ref1CapNorm!);
    if (_ref2Hazir) kontrolEt(_ref2Center!.dx, _ref2Center!.dy, _ref2CapNorm!);

    for (int i = 0; i < _tomruklar.length; i++) {
      if (i == haricIdx) continue;
      kontrolEt(_tomruklar[i].xNorm, _tomruklar[i].yNorm, _tomruklar[i].capNorm);
    }
    return maxR;
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
      _ref1P1 = null;
      _ref1Center = null;
      _ref1CapNorm = null;
      _ref2P1 = null;
      _ref2Center = null;
      _ref2CapNorm = null;
      _roiP1 = null;
      _roiNorm = null;
      _tomruklar.clear();
      _seciliHedef = SeciliHedef.hicbiri;
      _seciliTomrukIdx = null;
      _mod = EtkilesimModu.ref1;
    });
  }

  /// 3x3 Morfolojik Kapama (Dilation + Erosion) ile tomruk içi çatlak ve etiketleri kapatır
  List<int> _morfolojikKapama(List<int> src, int w, int h) {
    final dilated = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int hit = 0;
        for (int dy = -1; dy <= 1 && hit == 0; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (src[(y + dy) * w + (x + dx)] == 1) {
              hit = 1;
              break;
            }
          }
        }
        dilated[y * w + x] = hit;
      }
    }
    final closed = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int all = 1;
        for (int dy = -1; dy <= 1 && all == 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dilated[(y + dy) * w + (x + dx)] == 0) {
              all = 0;
              break;
            }
          }
        }
        closed[y * w + x] = all;
      }
    }
    return closed;
  }

  Future<void> _otomatikTespitCalistir() async {
    if (_seciliFoto == null) return;
    if (!_ref1Hazir) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce Ref-1 modunda çapını bildiğiniz tomruğun iki karşı kenarına dokunun.'),
        ),
      );
      return;
    }

    setState(() {
      _isleniyor = true;
      _seciliHedef = SeciliHedef.hicbiri;
      _seciliTomrukIdx = null;
    });

    try {
      final Uint8List bytes = await _seciliFoto!.readAsBytes();
      final img.Image? orijinal = img.decodeImage(bytes);
      if (orijinal == null) return;

      const int w = 360;
      final int h = max(1, (orijinal.height * w / orijinal.width).round());
      final img.Image kucuk = img.copyResize(orijinal, width: w, height: h);

      // 1) Ref-1 çemberi içinden gerçek ahşap renk profili öğren
      double sumR = 0, sumG = 0, sumB = 0;
      int sampleCount = 0;
      final double r1cx = _ref1Center!.dx * w;
      final double r1cy = _ref1Center!.dy * h;
      final double r1rad = (_ref1CapNorm! * w) * 0.38; // İç %75 bölge

      for (int y = max(0, (r1cy - r1rad).floor()); y <= min(h - 1, (r1cy + r1rad).ceil()); y++) {
        for (int x = max(0, (r1cx - r1rad).floor()); x <= min(w - 1, (r1cx + r1rad).ceil()); x++) {
          final dx = x - r1cx;
          final dy = y - r1cy;
          if (dx * dx + dy * dy <= r1rad * r1rad) {
            final p = kucuk.getPixel(x, y);
            sumR += p.r.toDouble();
            sumG += p.g.toDouble();
            sumB += p.b.toDouble();
            sampleCount++;
          }
        }
      }

      final double meanR = sampleCount > 0 ? sumR / sampleCount : 155.0;
      final double meanG = sampleCount > 0 ? sumG / sampleCount : 115.0;
      final double meanB = sampleCount > 0 ? sumB / sampleCount : 80.0;
      final double meanLuma = 0.299 * meanR + 0.587 * meanG + 0.114 * meanB;

      // ROI sınırları (varsa sadece çerçeve içi taranır)
      final int roiMinX = _roiNorm != null ? max(1, (_roiNorm!.left * w).floor()) : 1;
      final int roiMaxX = _roiNorm != null ? min(w - 2, (_roiNorm!.right * w).ceil()) : w - 2;
      final int roiMinY = _roiNorm != null ? max(1, (_roiNorm!.top * h).floor()) : 1;
      final int roiMaxY = _roiNorm != null ? min(h - 2, (_roiNorm!.bottom * h).ceil()) : h - 2;

      // 2) Referans renk profiline dayalı ahşap maskesi
      List<int> mask = List<int>.filled(w * h, 0);
      for (int y = roiMinY; y <= roiMaxY; y++) {
        for (int x = roiMinX; x <= roiMaxX; x++) {
          final p = kucuk.getPixel(x, y);
          final r = p.r.toDouble();
          final g = p.g.toDouble();
          final b = p.b.toDouble();
          final luma = 0.299 * r + 0.587 * g + 0.114 * b;

          final isGreen = g > r + 5 && g > b + 5;
          final isSky = b > r + 4;
          final isWarmWood = r >= b + 8;

          // Referans tomruk rengine yakınlık (parlaklık ve ton toleransı)
          final colorDist = sqrt(
            pow(r - meanR, 2) + pow(g - meanG, 2) + pow(b - meanB, 2),
          );
          final lumaOk = luma > max(65.0, meanLuma - 75.0) && luma < min(245.0, meanLuma + 75.0);

          if (!isGreen && !isSky && isWarmWood && lumaOk && colorDist < 115.0) {
            mask[y * w + x] = 1;
          }
        }
      }

      // 3) Morfolojik Kapama (çatlak, koyu öz ve barkod etiketlerini birleştir)
      mask = _morfolojikKapama(mask, w, h);

      // 4) Chamfer Mesafe Dönüşümü
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

      // 5) Akıllı Çap Bandı: Referans çapın %55 - %165 aralığı (parazit küçük daireleri engeller)
      final double refMinCm = _ref2Hazir ? min(_ref1CapCm, _ref2CapCm) : _ref1CapCm;
      final double refMaxCm = _ref2Hazir ? max(_ref1CapCm, _ref2CapCm) : _ref1CapCm;
      final double minTargetCm = max(8.0, refMinCm * 0.55);
      final double maxTargetCm = min(150.0, refMaxCm * 1.65);

      final List<_AdayDaire> adaylar = [];

      for (int y = roiMinY + 2; y <= roiMaxY - 2; y++) {
        for (int x = roiMinX + 2; x <= roiMaxX - 2; x++) {
          final val = dist[y * w + x];
          if (val < 3.5) continue;

          final localScale = _olcekHesapla(x / w, y / h)!;
          final double localMinR = (minTargetCm / localScale) * w / 2.0;
          final double localMaxR = (maxTargetCm / localScale) * w / 2.0;
          if (val < localMinR || val > localMaxR) continue;

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
          if (doluluk >= 0.70) {
            adaylar.add(_AdayDaire(x.toDouble(), y.toDouble(), val * 1.05, val * doluluk));
          }
        }
      }

      // 6) Kilitli Referans Alanları + Kesin Sıfır Çakışma (d >= r1 + r2)
      adaylar.sort((a, b) => b.skor.compareTo(a.skor));
      final List<_AdayDaire> kilitliler = [
        _AdayDaire(_ref1Center!.dx * w, _ref1Center!.dy * h, (_ref1CapNorm! * w) / 2.0, 1e9),
      ];
      if (_ref2Hazir) {
        kilitliler.add(
          _AdayDaire(_ref2Center!.dx * w, _ref2Center!.dy * h, (_ref2CapNorm! * w) / 2.0, 1e9),
        );
      }

      final List<_AdayDaire> secilenler = [];
      for (final aday in adaylar) {
        final localScale = _olcekHesapla(aday.x / w, aday.y / h)!;
        final double localMinR = (minTargetCm / localScale) * w / 2.0;

        double izinVerilenMaxR = aday.r;
        bool gecersiz = false;

        for (final s in [...kilitliler, ...secilenler]) {
          final dx = aday.x - s.x;
          final dy = aday.y - s.y;
          final merkezMesafe = sqrt(dx * dx + dy * dy);
          final kalanBosluk = merkezMesafe - s.r;

          if (kalanBosluk < localMinR) {
            gecersiz = true;
            break;
          }
          if (kalanBosluk < izinVerilenMaxR) {
            izinVerilenMaxR = kalanBosluk;
          }
        }

        if (!gecersiz && izinVerilenMaxR >= localMinR) {
          aday.r = izinVerilenMaxR;
          secilenler.add(aday);
        }
      }

      final List<TespitEdilenTomruk> bulunanlar = [];
      for (final s in secilenler) {
        final xN = s.x / w;
        final yN = s.y / h;
        final capNorm = (s.r * 2.0) / w;
        final localScale = _olcekHesapla(xN, yN)!;
        final capCm = capNorm * localScale;
        if (capCm >= minTargetCm && capCm <= maxTargetCm) {
          bulunanlar.add(
            TespitEdilenTomruk(
              xNorm: xN,
              yNorm: yN,
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
        final int refAdet = (_ref1Hazir ? 1 : 0) + (_ref2Hazir ? 1 : 0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${bulunanlar.length} adet yeni + $refAdet referans = ${bulunanlar.length + refAdet} tomruk tespit edildi.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  void _merkezKaydir(double dxNorm, double dyNorm) {
    if (_seciliHedef == SeciliHedef.ref1 && _ref1Center != null) {
      setState(() {
        _ref1Center = Offset(
          (_ref1Center!.dx + dxNorm).clamp(0.01, 0.99),
          (_ref1Center!.dy + dyNorm).clamp(0.01, 0.99),
        );
        _tumTomrukCaplariniGuncelle();
      });
    } else if (_seciliHedef == SeciliHedef.ref2 && _ref2Center != null) {
      setState(() {
        _ref2Center = Offset(
          (_ref2Center!.dx + dxNorm).clamp(0.01, 0.99),
          (_ref2Center!.dy + dyNorm).clamp(0.01, 0.99),
        );
        _tumTomrukCaplariniGuncelle();
      });
    } else if (_seciliHedef == SeciliHedef.tomruk &&
        _seciliTomrukIdx != null &&
        _seciliTomrukIdx! < _tomruklar.length) {
      final t = _tomruklar[_seciliTomrukIdx!];
      final yeniX = (t.xNorm + dxNorm).clamp(0.01, 0.99);
      final yeniY = (t.yNorm + dyNorm).clamp(0.01, 0.99);
      final maxRNorm = _maksimumCakismasizYaricapNorm(yeniX, yeniY, haricIdx: _seciliTomrukIdx);
      if (t.capNorm / 2.0 > maxRNorm) return;

      setState(() {
        t.xNorm = yeniX;
        t.yNorm = yeniY;
        final sc = _olcekHesapla(yeniX, yeniY);
        if (sc != null) t.capCm = t.capNorm * sc;
      });
    }
  }

  void _seciliTomrukCapGuncelle(double yeniCapCm) {
    if (_seciliTomrukIdx == null || _seciliTomrukIdx! >= _tomruklar.length) return;
    final t = _tomruklar[_seciliTomrukIdx!];
    double hedefCapCm = yeniCapCm.clamp(6.0, 150.0);
    final sc = _olcekHesapla(t.xNorm, t.yNorm);

    if (sc != null && sc > 0) {
      final maxRNorm = _maksimumCakismasizYaricapNorm(t.xNorm, t.yNorm, haricIdx: _seciliTomrukIdx);
      final maxCapCm = max(6.0, (maxRNorm * 2.0) * sc);
      if (hedefCapCm > maxCapCm) hedefCapCm = maxCapCm;
      setState(() {
        t.capCm = hedefCapCm;
        t.capNorm = hedefCapCm / sc;
      });
    } else {
      setState(() => t.capCm = hedefCapCm);
    }
  }

  void _fotoyaDokunuldu(TapDownDetails details, Size widgetSize) {
    final nx = (details.localPosition.dx / widgetSize.width).clamp(0.0, 1.0);
    final ny = (details.localPosition.dy / widgetSize.height).clamp(0.0, 1.0);

    if (_mod == EtkilesimModu.ref1) {
      setState(() {
        _seciliHedef = SeciliHedef.hicbiri;
        if (_ref1P1 == null) {
          _ref1P1 = Offset(nx, ny);
        } else {
          final dx = nx - _ref1P1!.dx;
          final dy = (ny - _ref1P1!.dy) * _invAspect;
          final capN = sqrt(dx * dx + dy * dy);
          if (capN >= 0.008) {
            _ref1Center = Offset((_ref1P1!.dx + nx) / 2.0, (_ref1P1!.dy + ny) / 2.0);
            _ref1CapNorm = capN;
            _tumTomrukCaplariniGuncelle();
          }
          _ref1P1 = null;
        }
      });
    } else if (_mod == EtkilesimModu.ref2) {
      setState(() {
        _seciliHedef = SeciliHedef.hicbiri;
        if (_ref2P1 == null) {
          _ref2P1 = Offset(nx, ny);
        } else {
          final dx = nx - _ref2P1!.dx;
          final dy = (ny - _ref2P1!.dy) * _invAspect;
          final capN = sqrt(dx * dx + dy * dy);
          if (capN >= 0.008) {
            _ref2Center = Offset((_ref2P1!.dx + nx) / 2.0, (_ref2P1!.dy + ny) / 2.0);
            _ref2CapNorm = capN;
            _tumTomrukCaplariniGuncelle();
          }
          _ref2P1 = null;
        }
      });
    } else if (_mod == EtkilesimModu.roiAlani) {
      setState(() {
        if (_roiP1 == null) {
          _roiP1 = Offset(nx, ny);
        } else {
          _roiNorm = Rect.fromPoints(_roiP1!, Offset(nx, ny));
          _roiP1 = null;
        }
      });
    } else if (_mod == EtkilesimModu.secDuzenle) {
      double minMesafe = 0.08;
      SeciliHedef hedef = SeciliHedef.hicbiri;
      int? enYakinIdx;

      if (_ref1Hazir) {
        final d = sqrt(pow(_ref1Center!.dx - nx, 2) + pow((_ref1Center!.dy - ny) * _invAspect, 2));
        if (d < minMesafe) {
          minMesafe = d;
          hedef = SeciliHedef.ref1;
        }
      }
      if (_ref2Hazir) {
        final d = sqrt(pow(_ref2Center!.dx - nx, 2) + pow((_ref2Center!.dy - ny) * _invAspect, 2));
        if (d < minMesafe) {
          minMesafe = d;
          hedef = SeciliHedef.ref2;
        }
      }
      for (int i = 0; i < _tomruklar.length; i++) {
        final d = sqrt(pow(_tomruklar[i].xNorm - nx, 2) + pow((_tomruklar[i].yNorm - ny) * _invAspect, 2));
        if (d < minMesafe) {
          minMesafe = d;
          hedef = SeciliHedef.tomruk;
          enYakinIdx = i;
        }
      }
      setState(() {
        _seciliHedef = hedef;
        _seciliTomrukIdx = hedef == SeciliHedef.tomruk ? enYakinIdx : null;
      });
    } else if (_mod == EtkilesimModu.tomrukEkle) {
      final sc = _olcekHesapla(nx, ny);
      final maxRNorm = _maksimumCakismasizYaricapNorm(nx, ny);
      final minRNorm = (sc != null && sc > 0) ? (6.0 / sc) / 2.0 : 0.015;

      if (maxRNorm < minRNorm) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu alan mevcut bir tomrukla çakışıyor; boş bir merkeze dokunun.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final istenenCapNorm = sc != null ? _varsayilanManuelCapCm / sc : 0.06;
      final gercekCapNorm = min(istenenCapNorm, maxRNorm * 2.0);
      final gercekCapCm = sc != null ? gercekCapNorm * sc : _varsayilanManuelCapCm;

      setState(() {
        _tomruklar.add(
          TespitEdilenTomruk(
            xNorm: nx,
            yNorm: ny,
            capNorm: gercekCapNorm,
            capCm: gercekCapCm,
          ),
        );
        _seciliHedef = SeciliHedef.tomruk;
        _seciliTomrukIdx = _tomruklar.length - 1;
      });
    }
  }

  double _netHacimHesapla(double capCm) {
    final int tamCapCm = capCm.floor();
    final rMetre = (tamCapCm / 100.0) / 2.0;
    return pi * rMetre * rMetre * _emvalBoyu;
  }

  Widget _yonTuslari() {
    const double adim = 0.004;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Merkez: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _merkezKaydir(-adim, 0),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_upward),
          onPressed: () => _merkezKaydir(0, -adim),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_downward),
          onPressed: () => _merkezKaydir(0, adim),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => _merkezKaydir(adim, 0),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Referans tomrukları da toplam adet ve hacme dahil et
    final List<double> tumCaplar = [
      if (_ref1Hazir) _ref1CapCm,
      if (_ref2Hazir) _ref2CapCm,
      ..._tomruklar.map((t) => t.capCm),
    ];
    final toplamHacim = tumCaplar.fold(0.0, (s, c) => s + _netHacimHesapla(c));
    final ince = tumCaplar.where((c) => c.floor() < 20).length;
    final orta = tumCaplar.where((c) => c.floor() >= 20 && c.floor() < 30).length;
    final kalin = tumCaplar.where((c) => c.floor() >= 30).length;

    final seciliTomruk = (_seciliHedef == SeciliHedef.tomruk &&
            _seciliTomrukIdx != null &&
            _seciliTomrukIdx! < _tomruklar.length)
        ? _tomruklar[_seciliTomrukIdx!]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => LisansServisi.yoneticiPaneliGoster(context),
          child: const Text('TomrukOlcumAI'),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          if (_roiNorm != null)
            IconButton(
              tooltip: 'Çerçeveyi Temizle',
              icon: const Icon(Icons.crop_free),
              onPressed: () => setState(() {
                _roiNorm = null;
                _roiP1 = null;
              }),
            ),
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
                                  ref1P1: _ref1P1,
                                  ref1Center: _ref1Center,
                                  ref1CapNorm: _ref1CapNorm,
                                  ref1CapCm: _ref1CapCm,
                                  ref1Secili: _seciliHedef == SeciliHedef.ref1,
                                  ref2P1: _ref2P1,
                                  ref2Center: _ref2Center,
                                  ref2CapNorm: _ref2CapNorm,
                                  ref2CapCm: _ref2CapCm,
                                  ref2Secili: _seciliHedef == SeciliHedef.ref2,
                                  roiP1: _roiP1,
                                  roiNorm: _roiNorm,
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
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<EtkilesimModu>(
                segments: const [
                  ButtonSegment(value: EtkilesimModu.ref1, label: Text('Ref-1')),
                  ButtonSegment(value: EtkilesimModu.ref2, label: Text('Ref-2')),
                  ButtonSegment(value: EtkilesimModu.roiAlani, label: Text('Alan')),
                  ButtonSegment(value: EtkilesimModu.secDuzenle, label: Text('Düzenle')),
                  ButtonSegment(value: EtkilesimModu.tomrukEkle, label: Text('Ekle')),
                ],
                selected: {_mod},
                onSelectionChanged: (s) => setState(() => _mod = s.first),
              ),
            ),
            // Ref-1 İnce Ayar Paneli
            if (_seciliHedef == SeciliHedef.ref1 && _ref1Hazir) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    children: [
                      Text(
                        'Ref-1 (Kırmızı - ${_ref1CapCm.floor()} cm) İnce Ayar',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      _yonTuslari(),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () => setState(() {
                              _ref1CapNorm = (_ref1CapNorm! - 0.003).clamp(0.015, 0.50);
                              _tumTomrukCaplariniGuncelle();
                            }),
                          ),
                          Expanded(
                            child: Slider(
                              activeColor: Colors.red,
                              value: _ref1CapNorm!.clamp(0.015, 0.50),
                              min: 0.015,
                              max: 0.50,
                              onChanged: (v) => setState(() {
                                _ref1CapNorm = v;
                                _tumTomrukCaplariniGuncelle();
                              }),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.red),
                            onPressed: () => setState(() {
                              _ref1CapNorm = (_ref1CapNorm! + 0.003).clamp(0.015, 0.50);
                              _tumTomrukCaplariniGuncelle();
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Ref-2 İnce Ayar Paneli
            if (_seciliHedef == SeciliHedef.ref2 && _ref2Hazir) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ref-2 (Turuncu - ${_ref2CapCm.floor()} cm) İnce Ayar',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() {
                              _ref2Center = null;
                              _ref2CapNorm = null;
                              _seciliHedef = SeciliHedef.hicbiri;
                              _tumTomrukCaplariniGuncelle();
                            }),
                          ),
                        ],
                      ),
                      _yonTuslari(),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline, color: Colors.orange.shade900),
                            onPressed: () => setState(() {
                              _ref2CapNorm = (_ref2CapNorm! - 0.003).clamp(0.015, 0.50);
                              _tumTomrukCaplariniGuncelle();
                            }),
                          ),
                          Expanded(
                            child: Slider(
                              activeColor: Colors.orange,
                              value: _ref2CapNorm!.clamp(0.015, 0.50),
                              min: 0.015,
                              max: 0.50,
                              onChanged: (v) => setState(() {
                                _ref2CapNorm = v;
                                _tumTomrukCaplariniGuncelle();
                              }),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle_outline, color: Colors.orange.shade900),
                            onPressed: () => setState(() {
                              _ref2CapNorm = (_ref2CapNorm! + 0.003).clamp(0.015, 0.50);
                              _tumTomrukCaplariniGuncelle();
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Seçili Tomruk İnce Ayar Paneli
            if (seciliTomruk != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() {
                              _tomruklar.removeAt(_seciliTomrukIdx!);
                              _seciliTomrukIdx = null;
                              _seciliHedef = SeciliHedef.hicbiri;
                            }),
                          ),
                        ],
                      ),
                      _yonTuslari(),
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
                  child: TextField(
                    controller: _ref1CapCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Ref-1 Çap (cm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final d = double.tryParse(v.replaceAll(',', '.'));
                      if (d != null && d >= 5 && d <= 200) {
                        setState(() {
                          _ref1CapCm = d;
                          _tumTomrukCaplariniGuncelle();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ref2CapCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Ref-2 Çap (Ops.)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final d = double.tryParse(v.replaceAll(',', '.'));
                      if (d != null && d >= 5 && d <= 200) {
                        setState(() {
                          _ref2CapCm = d;
                          _tumTomrukCaplariniGuncelle();
                        });
                      }
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
                  label: const Text('Say'),
                ),
              ],
            ),
          ] else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Başlamak için "Kamera ile Çek" veya "Galeriden Seç" butonuna basın.\n\n'
                  '1) Ref-1 modunda çapını bildiğiniz tomruğun 2 karşı kenarına dokunun (kırmızı çember).\n'
                  '2) (Opsiyonel) Uzak/diğer uçta Ref-2 işaretleyerek perspektif sapmasını düzeltin.\n'
                  '3) (Opsiyonel) Alan modunda 2 köşeye dokunup istifi çerçeveleyin.\n'
                  '4) "Say" butonuna basın.',
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
                  TextField(
                    controller: _emvalBoyuController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Emval Boyu (m)',
                      helperText: 'Klavyeden istediğiniz boyu metre cinsinden girin (örn: 2.5, 3.0, 4.2)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: _emvalBoyuDegisti,
                  ),
                  const Divider(height: 20),
                  Text(
                    'Toplam Adet: ${tumCaplar.length}',
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
  final Offset? ref1P1;
  final Offset? ref1Center;
  final double? ref1CapNorm;
  final double ref1CapCm;
  final bool ref1Secili;
  final Offset? ref2P1;
  final Offset? ref2Center;
  final double? ref2CapNorm;
  final double ref2CapCm;
  final bool ref2Secili;
  final Offset? roiP1;
  final Rect? roiNorm;
  final List<TespitEdilenTomruk> tomruklar;
  final int? seciliIdx;

  _OlcumOverlayPainter({
    required this.ref1P1,
    required this.ref1Center,
    required this.ref1CapNorm,
    required this.ref1CapCm,
    required this.ref1Secili,
    required this.ref2P1,
    required this.ref2Center,
    required this.ref2CapNorm,
    required this.ref2CapCm,
    required this.ref2Secili,
    required this.roiP1,
    required this.roiNorm,
    required this.tomruklar,
    required this.seciliIdx,
  });

  void _cizReferans(
    Canvas canvas,
    Size size,
    Offset? p1,
    Offset? centerNorm,
    double? capNorm,
    double capCm,
    Color renk,
    String etiket,
    bool secili,
  ) {
    if (centerNorm != null && capNorm != null) {
      final c = Offset(centerNorm.dx * size.width, centerNorm.dy * size.height);
      final r = max(4.0, (capNorm * size.width) / 2.0);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = renk
          ..strokeWidth = secili ? 3.5 : 2.5
          ..style = PaintingStyle.stroke,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '$etiket ${capCm.floor()}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            backgroundColor: renk,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    } else if (p1 != null) {
      canvas.drawCircle(
        Offset(p1.dx * size.width, p1.dy * size.height),
        5,
        Paint()..color = renk,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // İstif Çerçevesi (ROI - Mavi)
    if (roiNorm != null) {
      final rect = Rect.fromLTRB(
        roiNorm!.left * size.width,
        roiNorm!.top * size.height,
        roiNorm!.right * size.width,
        roiNorm!.bottom * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.lightBlueAccent
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    } else if (roiP1 != null) {
      canvas.drawCircle(
        Offset(roiP1!.dx * size.width, roiP1!.dy * size.height),
        5,
        Paint()..color = Colors.lightBlueAccent,
      );
    }

    // Ref-1 (Kırmızı) ve Ref-2 (Turuncu)
    _cizReferans(canvas, size, ref1P1, ref1Center, ref1CapNorm, ref1CapCm, Colors.redAccent, 'R1', ref1Secili);
    _cizReferans(canvas, size, ref2P1, ref2Center, ref2CapNorm, ref2CapCm, Colors.orange, 'R2', ref2Secili);

    // Tespit edilen tomruklar
    for (int i = 0; i < tomruklar.length; i++) {
      final t = tomruklar[i];
      final isSelected = i == seciliIdx;
      final center = Offset(t.xNorm * size.width, t.yNorm * size.height);
      final radius = max(3.0, (t.capNorm * size.width) / 2.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = isSelected ? Colors.cyanAccent : Colors.lightGreenAccent
          ..strokeWidth = isSelected ? 3.0 : 1.8
          ..style = PaintingStyle.stroke,
      );

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
