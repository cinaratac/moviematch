import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/date_helper.dart';
import 'trivia_quiz_screen.dart';
import 'trivia_leaderboard_screen.dart'; // Birazdan oluşturacağız

class TriviaWelcomeScreen extends StatefulWidget {
  const TriviaWelcomeScreen({super.key});

  @override
  State<TriviaWelcomeScreen> createState() => _TriviaWelcomeScreenState();
}

class _TriviaWelcomeScreenState extends State<TriviaWelcomeScreen> {
  bool _checkingStatus = true;
  bool _alreadyPlayed = false;
  int _myScore = 0;

  @override
  void initState() {
    super.initState();
    _checkPlayStatus();
  }

  Future<void> _checkPlayStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final weekId = DateHelper.getCurrentWeekId();

    // Kullanıcının bu haftaki skorunu kontrol et
    final doc = await FirebaseFirestore.instance
        .collection('weekly_leaderboard')
        .doc(weekId)
        .collection('scores')
        .doc(user.uid)
        .get();

    if (mounted) {
      setState(() {
        _alreadyPlayed = doc.exists;
        if (doc.exists) {
          _myScore = doc.data()?['score'] ?? 0;
        }
        _checkingStatus = false;
      });
    }
  }

  void _startQuiz() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TriviaQuizScreen()),
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TriviaLeaderboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // Koyu tema
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: _checkingStatus
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // İkon
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emoji_events_rounded, size: 80, color: Colors.amber),
                  ),
                  const SizedBox(height: 32),
                  
                  // Başlık
                  const Text(
                    "Haftalık Sinema Yarışması",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (_alreadyPlayed) ...[
                    // ZATEN OYNADIYSA
                    Text(
                      "Bu haftaki hakkını kullandın!\nPuanın: $_myScore",
                      style: const TextStyle(fontSize: 18, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      onPressed: _openLeaderboard,
                      icon: const Icon(Icons.leaderboard),
                      label: const Text("Liderlik Tablosu"),
                    ),
                  ] else ...[
                    // HENÜZ OYNAMADIYSA KURALLAR
                    _buildRuleRow(Icons.refresh, "Yarışma her hafta yenilenir."),
                    _buildRuleRow(Icons.timer, "Her soru için 30 saniyen var."),
                    _buildRuleRow(Icons.quiz, "Toplam 10 soru."),
                    _buildRuleRow(Icons.star, "Her soru 10 puan değerinde."),
                    _buildRuleRow(Icons.block, "Sadece 1 kez katılabilirsin!"),
                    
                    const Spacer(),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _startQuiz,
                        child: const Text("YARIŞMAYA BAŞLA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildRuleRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 16))),
        ],
      ),
    );
  }
}