import 'dart:convert'; // <--- JSON İÇİN BU GEREKLİ
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/date_helper.dart';
import 'admin_questions_list_screen.dart'; // Tüm sorular ekranı için

class AdminTriviaScreen extends StatefulWidget {
  const AdminTriviaScreen({super.key});

  @override
  State<AdminTriviaScreen> createState() => _AdminTriviaScreenState();
}

class _AdminTriviaScreenState extends State<AdminTriviaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionsCtrl = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int _correctIndex = 0;
  bool _uploadForNextWeek = false;
  
  // --- RESİM İÇİN DEĞİŞKENLER ---
  File? _selectedImage;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  // --- HAZIR JSON VERİSİ ---
  final String _jsonRawData = '''
[
  {
    "question": "Titanic filminde Rose'un üzerine çıktığı o meşhur tahta kapıya Jack sığabilir miydi?",
    "options": ["Hayır, batardı", "Evet, sığardı (Kanıtlandı)", "Jack yüzmeyi seviyordu", "Kapı değil o, piyano kapağı"],
    "correctIndex": 1,
    "difficulty": "kolay"
  },
  {
    "question": "G.O.R.A filminde Komutan Logar'a sürekli yapılan o meşhur uyarı nedir?",
    "options": ["Komutanım, yemek hazır", "Komutan Logar, bir cisim yaklaşıyor", "Dikkat etsene be!", "Alev topu geliyor"],
    "correctIndex": 1,
    "difficulty": "kolay"
  },
  {
    "question": "Terminator 2 filminde Arnold Schwarzenegger'in geri döneceğini söylediği o ikonik replik?",
    "options": ["I will come again", "I'll be back", "See you later alligator", "Bye bye baby"],
    "correctIndex": 1,
    "difficulty": "kolay"
  },
  {
    "question": "Yüzüklerin Efendisi'nde Boromir'in (Sean Bean) internette 'meme' olan meşhur repliği nedir?",
    "options": ["You shall not pass!", "One does not simply walk into Mordor", "My precious!", "Run you fools"],
    "correctIndex": 1,
    "difficulty": "orta"
  },
  {
    "question": "Harry Potter filminde Dumbledore'un kitapta 'sakin' sorduğu ama filmde bağırarak söylediği o cümle?",
    "options": ["Harry, adını kadehe sen mi attın?!", "Voldemort döndü mü?!", "Slytherin kazandı mı?!", "Asanı düşürdün mü?!"],
    "correctIndex": 0,
    "difficulty": "orta"
  },
  {
    "question": "John Wick'in yüzlerce kişiyi öldürerek intikam almasının (seriyi başlatan) asıl sebebi neydi?",
    "options": ["Arabasının çizilmesi", "Köpeğinin öldürülmesi", "Kahvesinin dökülmesi", "Evine yanlış pizza gelmesi"],
    "correctIndex": 1,
    "difficulty": "kolay"
  },
  {
    "question": "Fight Club (Dövüş Kulübü) filminin 1. kuralı nedir?",
    "options": ["Asla kaybetme", "Dövüş Kulübü hakkında konuşma", "Gömleksiz dövüşülmez", "Herkes sırayla dövüşür"],
    "correctIndex": 1,
    "difficulty": "kolay"
  },
  {
    "question": "Avengers: Endgame filminde Thor'un göbekli, pasaklı ve depresif haline verilen resmi isim nedir?",
    "options": ["Fat Thor", "Lebowski Thor", "Bro Thor", "Sad Thor"],
    "correctIndex": 2,
    "difficulty": "orta"
  },
  {
    "question": "Matrix filminde Neo'ya sunulan hapların renkleri hangileridir?",
    "options": ["Mor ve Turuncu", "Siyah ve Beyaz", "Kırmızı ve Mavi", "Yeşil ve Sarı"],
    "correctIndex": 2,
    "difficulty": "kolay"
  },
  {
    "question": "Hangi filmde Tom Hanks bir voleybol topuna yüz çizip ona 'Wilson' diye seslenir?",
    "options": ["Cast Away (Yeni Hayat)", "Forrest Gump", "Truman Show", "Lost"],
    "correctIndex": 0,
    "difficulty": "kolay"
  }
]
    
  ''';

  // --- RESİM SEÇME ---
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  // --- RESİM YÜKLEME ---
  Future<String?> _uploadImageToStorage() async {
    if (_selectedImage == null) return null;
    try {
      String fileName = "trivia_${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference ref = FirebaseStorage.instance.ref().child('trivia_images').child(fileName);
      
      UploadTask uploadTask = ref.putFile(_selectedImage!);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Resim yükleme hatası: $e");
      return null;
    }
  }

  // --- TEK SORU KAYDETME ---
  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUploading = true);

    String targetWeekId;
    if (_uploadForNextWeek) {
      final nextWeekDate = DateTime.now().add(const Duration(days: 7));
      targetWeekId = DateHelper.getWeekIdFor(nextWeekDate);
    } else {
      targetWeekId = DateHelper.getCurrentWeekId();
    }

    // 1. Önce resmi yükle (varsa)
    String? imageUrl;
    if (_selectedImage != null) {
      imageUrl = await _uploadImageToStorage();
    }

    // 2. Veriyi kaydet
    await FirebaseFirestore.instance.collection('trivia_questions').add({
      'question': _questionCtrl.text.trim(),
      'options': _optionsCtrl.map((c) => c.text.trim()).toList(),
      'correctIndex': _correctIndex,
      'createdAt': FieldValue.serverTimestamp(),
      'weekId': targetWeekId,
      'imageUrl': imageUrl,
      'isActive': true,
    });

    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soru ve resim eklendi!')));
    
    _questionCtrl.clear();
    for (var c in _optionsCtrl) c.clear();
    setState(() {
      _correctIndex = 0;
      _selectedImage = null;
      _isUploading = false;
    });
  }

  // --- TOPLU YÜKLEME (BULK UPLOAD) ---
  // Bu fonksiyon JSON verisini veritabanına yazar
  Future<void> _bulkUpload() async {
    // 1. JSON Listesini Hazırla
    List<dynamic> dataList;
    try {
      dataList = json.decode(_jsonRawData);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON formatı hatalı!')));
      return;
    }

    // 2. Hedef Haftayı Belirle
    String targetWeekId;
    if (_uploadForNextWeek) {
      final nextWeekDate = DateTime.now().add(const Duration(days: 7));
      targetWeekId = DateHelper.getWeekIdFor(nextWeekDate);
    } else {
      targetWeekId = DateHelper.getCurrentWeekId();
    }

    // --- GÜVENLİK KONTROLÜ ---
    final existingDocs = await FirebaseFirestore.instance
        .collection('trivia_questions')
        .where('weekId', isEqualTo: targetWeekId)
        .get();

    final currentCount = existingDocs.docs.length;
    final newCount = dataList.length;

    if (currentCount >= 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HATA: $targetWeekId haftası için kota dolu! ($currentCount soru var)'), backgroundColor: Colors.red),
      );
      return;
    }

    if (currentCount + newCount > 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HATA: 10 soru sınırını aşıyorsunuz.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection('trivia_questions');

      for (var item in dataList) {
        var docRef = collection.doc();
        batch.set(docRef, {
          'question': item['question'],
          'options': item['options'],
          'correctIndex': item['correctIndex'],
          'difficulty': item['difficulty'],
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'weekId': targetWeekId,
          // Toplu yüklemede resim yok varsayıyoruz
          'imageUrl': null, 
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BAŞARILI: $newCount soru yüklendi.'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yükleme Hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentW = DateHelper.getCurrentWeekId();
    final nextW = DateHelper.getWeekIdFor(DateTime.now().add(const Duration(days: 7)));

    return Scaffold(
      appBar: AppBar(title: const Text('Soru Ekleme Paneli')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // HAFTA SEÇİCİ
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _uploadForNextWeek ? Colors.orange.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _uploadForNextWeek ? Colors.orange : Colors.green),
                ),
                child: Column(
                  children: [
                    const Text("Hangi Hafta İçin Yüklüyorsun?", style: TextStyle(fontWeight: FontWeight.bold)),
                    SwitchListTile(
                      title: Text(_uploadForNextWeek ? "Gelecek Hafta ($nextW)" : "Bu Hafta ($currentW)"),
                      subtitle: Text(_uploadForNextWeek 
                        ? "Bu sorular PAZARTESİ'den itibaren görünür." 
                        : "Bu sorular HEMEN görünür."),
                      value: _uploadForNextWeek,
                      activeColor: Colors.orange,
                      onChanged: (val) => setState(() => _uploadForNextWeek = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // RESİM EKLEME ALANI
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                    image: _selectedImage != null 
                      ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                      : null
                  ),
                  child: _selectedImage == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                            Text("Soru Görseli Ekle (İsteğe Bağlı)", style: TextStyle(color: Colors.grey)),
                          ],
                        )
                      : null,
                ),
              ),
              if (_selectedImage != null)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedImage = null),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text("Resmi Kaldır", style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _questionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Soru Metni', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Boş bırakma' : null,
              ),
              const SizedBox(height: 16),
              const Text("Şıklar:"),
              ...List.generate(4, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Radio<int>(
                        value: index,
                        groupValue: _correctIndex,
                        onChanged: (val) => setState(() => _correctIndex = val!),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _optionsCtrl[index],
                          decoration: InputDecoration(labelText: '${String.fromCharCode(65 + index)} Şıkkı'),
                          validator: (v) => v!.isEmpty ? 'Şık giriniz' : null,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),
              
              ElevatedButton(
                onPressed: _isUploading ? null : _saveQuestion,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isUploading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Soruyu ve Resmi Kaydet', style: TextStyle(fontSize: 16)),
              ),
              
              const SizedBox(height: 30),
              const Divider(thickness: 2),
              const SizedBox(height: 10),
              
              // --- HAZIR LİSTE BUTONU (Artık Çalışıyor) ---
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: _isUploading ? null : _bulkUpload, // Fonksiyon bağlandı
                icon: const Icon(Icons.cloud_upload),
                label: const Text('HAZIR LİSTEYİ YÜKLE (10 Soru)'),
              ),

              const SizedBox(height: 10),

              // --- TÜM SORULARI DÜZENLEME BUTONU ---
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  side: const BorderSide(color: Colors.blue, width: 2),
                ),
                onPressed: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => const AdminQuestionsListScreen())
                  );
                },
                icon: const Icon(Icons.list_alt, color: Colors.blue),
                label: const Text('TÜM SORULARI GÖR & DÜZENLE', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}