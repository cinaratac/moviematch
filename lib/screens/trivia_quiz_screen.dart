import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_helper.dart'; // <--- BU IMPORT ÇOK ÖNEMLİ
import 'trivia_result_screen.dart'; 

class TriviaQuizScreen extends StatefulWidget {
  const TriviaQuizScreen({super.key});

  @override
  State<TriviaQuizScreen> createState() => _TriviaQuizScreenState();
}

class _TriviaQuizScreenState extends State<TriviaQuizScreen> {
  int _currentIndex = 0;
  int _score = 0;
  List<QueryDocumentSnapshot> _questions = [];
  bool _isLoading = true;

  // Zamanlayıcı
  Timer? _timer;
  int _timeLeft = 30; 
  static const int _questionDuration = 30;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    // GÜNCEL HAFTANIN SORULARINI ÇEK
    final currentWeekId = DateHelper.getCurrentWeekId();

    final snap = await FirebaseFirestore.instance
        .collection('trivia_questions')
        .where('weekId', isEqualTo: currentWeekId)
        .limit(20) 
        .get();
    
    var list = snap.docs.toList();
    list.shuffle(); // Karıştır
    
    if (list.length > 10) {
      list = list.sublist(0, 10);
    }

    if (mounted) {
      setState(() {
        _questions = list;
        _isLoading = false;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timeLeft = _questionDuration);
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        _answerQuestion(-1); // Süre bitti
      }
    });
  }

  void _answerQuestion(int selectedIndex) {
    _timer?.cancel(); 

    final currentQ = _questions[_currentIndex].data() as Map<String, dynamic>;
    final correctIndex = currentQ['correctIndex'] as int;

    if (selectedIndex == correctIndex) {
      _score += 10;
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_currentIndex < _questions.length - 1) {
        setState(() {
          _currentIndex++;
        });
        _startTimer();
      } else {
        _finishQuiz();
      }
    });
  }

  void _finishQuiz() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TriviaResultScreen(score: _score, totalQuestions: _questions.length),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    if (_questions.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("Bu hafta için henüz soru eklenmemiş.")),
      );
    }

    final data = _questions[_currentIndex].data() as Map<String, dynamic>;
    final options = List<String>.from(data['options']);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Soru ${_currentIndex + 1}/10", style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        automaticallyImplyLeading: false, 
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: _timeLeft / _questionDuration,
              color: _timeLeft < 10 ? Colors.red : Colors.amber,
              backgroundColor: Colors.white10,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 10),
            Text("Süre: $_timeLeft sn", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
            
            const SizedBox(height: 30),
            
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                data['question'],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            
            ...List.generate(options.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E2E42),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => _answerQuestion(index),
                  child: Text(
                    "${String.fromCharCode(65 + index)})  ${options[index]}",
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}