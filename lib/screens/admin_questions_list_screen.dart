import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AdminQuestionsListScreen extends StatefulWidget {
  const AdminQuestionsListScreen({super.key});

  @override
  State<AdminQuestionsListScreen> createState() => _AdminQuestionsListScreenState();
}

class _AdminQuestionsListScreenState extends State<AdminQuestionsListScreen> {
  final Stream<QuerySnapshot> _questionsStream = FirebaseFirestore.instance
      .collection('trivia_questions')
      .orderBy('createdAt', descending: true)
      .snapshots();

  final ImagePicker _picker = ImagePicker();

  // --- SORU SİLME ---
  Future<void> _deleteQuestion(String docId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Soruyu Sil"),
        content: const Text("Bu soruyu kalıcı olarak silmek istediğine emin misin?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("SİL", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await FirebaseFirestore.instance.collection('trivia_questions').doc(docId).delete();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Soru silindi.")));
    }
  }

  // --- RESİM YÜKLEME YARDIMCISI ---
  Future<String?> _uploadImage(File file) async {
    try {
      String fileName = "trivia_edit_${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference ref = FirebaseStorage.instance.ref().child('trivia_images').child(fileName);
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Resim yükleme hatası: $e");
      return null;
    }
  }

  // --- SORU DÜZENLEME DİYALOĞU ---
  void _showEditDialog(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      
      // --- GÜVENLİ VERİ OKUMA ---
      final String qText = data['question']?.toString() ?? "";
      final TextEditingController questionCtrl = TextEditingController(text: qText);
      
      // Seçenekler listesini güvenli bir şekilde al
      List<dynamic> rawOptions = (data['options'] is List) ? data['options'] : [];
      // Eğer liste boşsa veya eksikse tamamla
      while (rawOptions.length < 4) {
        rawOptions.add("");
      }
      
      final List<TextEditingController> optionsCtrl = rawOptions
          .map((e) => TextEditingController(text: e.toString()))
          .toList();

      final String wId = data['weekId']?.toString() ?? "";
      final TextEditingController weekIdCtrl = TextEditingController(text: wId);
      
      // Sayısal değerleri güvenli al
      int correctIndex = 0;
      if (data['correctIndex'] is int) {
        correctIndex = data['correctIndex'];
      }
      
      bool isActive = true;
      if (data['isActive'] is bool) {
        isActive = data['isActive'];
      }
      
      // Resim verisini güvenli al
      String? currentImageUrl;
      if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) {
        currentImageUrl = data['imageUrl'].toString();
      }

      // Değişkenler
      File? newImageFile;
      bool isUploading = false;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text("Soruyu Düzenle"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch, // DÜZELTME: İçeriği yatayda yay
                    children: [
                      // --- RESİM ALANI BAŞLANGIÇ ---
                      GestureDetector(
                        onTap: () async {
                          try {
                            final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                            if (image != null) {
                              setStateDialog(() {
                                newImageFile = File(image.path);
                              });
                            }
                          } catch (e) {
                            debugPrint("Resim seçme hatası: $e");
                          }
                        },
                        child: Container(
                          height: 150,
                          // width: double.infinity, // DÜZELTME: Bu satır kaldırıldı (Hatanın sebebiydi)
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 1. Yeni seçilen resim varsa
                              if (newImageFile != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    newImageFile!, 
                                    fit: BoxFit.cover, 
                                    height: 150,
                                    width: double.maxFinite, // DÜZELTME: infinity yerine maxFinite
                                  ),
                                )
                              // 2. Eskiden yüklenmiş resim varsa
                              else if (currentImageUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(
                                    imageUrl: currentImageUrl!,
                                    fit: BoxFit.cover,
                                    height: 150,
                                    width: double.maxFinite, // DÜZELTME: infinity yerine maxFinite
                                    placeholder: (c, u) => const Center(child: CircularProgressIndicator()),
                                    errorWidget: (c, u, e) => const Icon(Icons.error, color: Colors.red),
                                  ),
                                )
                              // 3. Hiç resim yoksa
                              else
                                const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                                    Text("Görsel Ekle", style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              
                              // Resmi Kaldır / İptal Et Butonu
                              if (newImageFile != null || currentImageUrl != null)
                                Positioned(
                                  top: 5,
                                  right: 5,
                                  child: CircleAvatar(
                                    backgroundColor: Colors.red,
                                    radius: 16,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.close, size: 20, color: Colors.white),
                                      onPressed: () {
                                        setStateDialog(() {
                                          newImageFile = null;
                                          currentImageUrl = null;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      // --- RESİM ALANI BİTİŞ ---

                      // Soru Metni
                      TextField(
                        controller: questionCtrl,
                        decoration: const InputDecoration(labelText: "Soru Metni", border: OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      
                      // Şıklar
                      ...List.generate(4, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Radio<int>(
                                value: index,
                                groupValue: correctIndex,
                                onChanged: (val) {
                                  setStateDialog(() => correctIndex = val!);
                                },
                              ),
                              Expanded(
                                child: TextField(
                                  controller: optionsCtrl[index],
                                  decoration: InputDecoration(
                                    labelText: "${String.fromCharCode(65 + index)} Şıkkı",
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 10),
                      TextField(
                        controller: weekIdCtrl,
                        decoration: const InputDecoration(
                          labelText: "Hafta ID", 
                          border: OutlineInputBorder(),
                          helperText: "Örn: 2024-42"
                        ),
                      ),

                      SwitchListTile(
                        title: const Text("Soru Yayında mı?"),
                        value: isActive,
                        onChanged: (val) => setStateDialog(() => isActive = val),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isUploading ? null : () => Navigator.pop(context), 
                    child: const Text("İptal")
                  ),
                  ElevatedButton(
                    onPressed: isUploading ? null : () async {
                      setStateDialog(() => isUploading = true);

                      try {
                        String? finalImageUrl = currentImageUrl;

                        // Eğer yeni bir resim seçildiyse yükle
                        if (newImageFile != null) {
                          final uploadedUrl = await _uploadImage(newImageFile!);
                          if (uploadedUrl != null) {
                            finalImageUrl = uploadedUrl;
                          }
                        }

                        // Veritabanını Güncelle
                        await FirebaseFirestore.instance.collection('trivia_questions').doc(doc.id).update({
                          'question': questionCtrl.text.trim(),
                          'options': optionsCtrl.map((c) => c.text.trim()).toList(),
                          'correctIndex': correctIndex,
                          'weekId': weekIdCtrl.text.trim(),
                          'isActive': isActive,
                          'imageUrl': finalImageUrl, 
                          'updatedAt': FieldValue.serverTimestamp(),
                        });

                        if(mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Soru güncellendi!")));
                        }
                      } catch (e) {
                        debugPrint("Güncelleme hatası: $e");
                        setStateDialog(() => isUploading = false);
                        if(mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
                        }
                      }
                    },
                    child: isUploading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Kaydet"),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint("Dialog açma hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Düzenleme penceresi açılamadı: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tüm Sorular & Düzenle")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _questionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Bir hata oluştu"));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) return const Center(child: Text("Hiç soru bulunamadı."));

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final question = data['question']?.toString() ?? '';
              final weekId = data['weekId']?.toString() ?? '?';
              final imageUrl = data['imageUrl'];
              final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;
              final isActive = (data['isActive'] is bool) ? data['isActive'] : true;
              final int correctIndex = (data['correctIndex'] is int) ? data['correctIndex'] : 0;

              return Card(
                color: isActive ? null : Colors.grey.shade300,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  // Sol tarafta küçük resim önizlemesi
                  leading: hasImage 
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl.toString(), 
                            width: 50, 
                            height: 50, 
                            fit: BoxFit.cover,
                            placeholder: (c, u) => Container(color: Colors.grey[300]),
                            errorWidget: (c, u, e) => const Icon(Icons.error),
                          ),
                        )
                      : const Icon(Icons.help_outline, size: 40, color: Colors.grey),
                  title: Text(
                    question, 
                    maxLines: 2, 
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(decoration: isActive ? null : TextDecoration.lineThrough),
                  ),
                  subtitle: Text("Hafta: $weekId | Doğru: ${String.fromCharCode(65 + correctIndex)}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        onPressed: () => _showEditDialog(doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteQuestion(doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}