import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_helper.dart'; // <--- BU IMPORT ÇOK ÖNEMLİ

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
  
  // EKSİK OLAN DEĞİŞKEN BUYDU:
  bool _uploadForNextWeek = false; 

  // JSON verisi
  final String _jsonRawData = '''
  [
    {
      "question": "Sinema tarihinde çekilen ilk uzun metrajlı film hangisi olarak kabul edilir?",
      "options": ["A Trip to the Moon", "The Story of the Kelly Gang", "Birth of a Nation", "Metropolis"],
      "correctIndex": 1,
      "difficulty": "medium",
      "isActive": true
    },
    {
      "question": "Oscar tarihinde En İyi Film ödülünü kazanan ilk film hangisidir?",
      "options": ["Wings", "Gone with the Wind", "Sunrise", "All Quiet on the Western Front"],
      "correctIndex": 0,
      "difficulty": "medium",
      "isActive": true
    },
    {
      "question": "Alfred Hitchcock’un hiç görünmediği (cameo yapmadığı) tek filmi hangisidir?",
      "options": ["Psycho", "The Birds", "Rebecca", "Lifeboat"],
      "correctIndex": 2,
      "difficulty": "hard",
      "isActive": true
    },
    {
      "question": "Hangi film 'Rosebud' kelimesiyle özdeşleşmiştir?",
      "options": ["Casablanca", "Citizen Kane", "Vertigo", "Rear Window"],
      "correctIndex": 1,
      "difficulty": "easy",
      "isActive": true
    },
    {
      "question": "IMAX formatında çekilen ilk Hollywood filmi hangisidir?",
      "options": ["The Dark Knight", "Avatar", "Interstellar", "Transformers"],
      "correctIndex": 0,
      "difficulty": "medium",
      "isActive": true
    },
    {
      "question": "Stanley Kubrick’in '2001: A Space Odyssey' filmi hangi yılda gösterime girmiştir?",
      "options": ["1965", "1968", "1971", "1975"],
      "correctIndex": 1,
      "difficulty": "easy",
      "isActive": true
    },
    {
      "question": "En çok Oscar kazanan film rekorunu (11 ödül) paylaşan filmlerden biri değildir?",
      "options": ["Titanic", "Ben-Hur", "The Lord of the Rings: The Return of the King", "Schindler’s List"],
      "correctIndex": 3,
      "difficulty": "medium",
      "isActive": true
    },
    {
      "question": "Sessiz sinema döneminin en ikonik komedyenlerinden biri değildir?",
      "options": ["Charlie Chaplin", "Buster Keaton", "Harold Lloyd", "Marlon Brando"],
      "correctIndex": 3,
      "difficulty": "easy",
      "isActive": true
    },
    {
      "question": "Quentin Tarantino’nun yönettiği ilk uzun metrajlı film hangisidir?",
      "options": ["Pulp Fiction", "Reservoir Dogs", "Jackie Brown", "Kill Bill"],
      "correctIndex": 1,
      "difficulty": "easy",
      "isActive": true
    },
    {
      "question": "Hangi yönetmen aynı yıl içinde En İyi Yönetmen Oscar’ını iki farklı filmle aday olarak alan ilk kişidir?",
      "options": ["Steven Spielberg", "Francis Ford Coppola", "Michael Curtiz", "Alfred Hitchcock"],
      "correctIndex": 2,
      "difficulty": "hard",
      "isActive": true
    }
  ]
  ''';

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    // Hangi hafta için?
    String targetWeekId;
    if (_uploadForNextWeek) {
      final nextWeekDate = DateTime.now().add(const Duration(days: 7));
      targetWeekId = DateHelper.getWeekIdFor(nextWeekDate);
    } else {
      targetWeekId = DateHelper.getCurrentWeekId();
    }

    await FirebaseFirestore.instance.collection('trivia_questions').add({
      'question': _questionCtrl.text.trim(),
      'options': _optionsCtrl.map((c) => c.text.trim()).toList(),
      'correctIndex': _correctIndex,
      'createdAt': FieldValue.serverTimestamp(),
      'weekId': targetWeekId, // YENİ SİSTEM
    });

    if (!mounted) return; // BuildContext hatası için kontrol
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soru eklendi!')));
    
    _questionCtrl.clear();
    for (var c in _optionsCtrl) c.clear();
    setState(() => _correctIndex = 0);
  }

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

    // --- GÜVENLİK KONTROLÜ BAŞLIYOR ---
    // Yükleme yapmadan önce veritabanına soruyoruz:
    final existingDocs = await FirebaseFirestore.instance
        .collection('trivia_questions')
        .where('weekId', isEqualTo: targetWeekId)
        .get();

    final currentCount = existingDocs.docs.length;
    final newCount = dataList.length;

    // Kural: Bir haftada toplam en fazla 10 soru olabilir.
    if (currentCount >= 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('HATA: $targetWeekId haftası için zaten $currentCount soru var. Kota dolu!'),
          backgroundColor: Colors.red,
        ),
      );
      return; // İşlemi iptal et
    }

    if (currentCount + newCount > 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('HATA: İçeride $currentCount soru var. $newCount tane daha eklerseniz 10 sınırını aşarsınız.'),
          backgroundColor: Colors.orange,
        ),
      );
      return; // İşlemi iptal et
    }
    // --- GÜVENLİK KONTROLÜ BİTTİ ---

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
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('BAŞARILI: $newCount soru $targetWeekId haftasına yüklendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yükleme Hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bilgilendirme için ID'leri hesapla
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

              TextFormField(
                controller: _questionCtrl,
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
                onPressed: _saveQuestion,
                child: const Text('Tek Soru Kaydet'),
              ),
              const SizedBox(height: 30),
              const Divider(thickness: 2),
              const SizedBox(height: 10),
              
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: _bulkUpload,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('HAZIR LİSTEYİ YÜKLE (10 Soru)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}