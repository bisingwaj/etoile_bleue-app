import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../../core/theme/app_theme.dart';

class QuizPage extends StatefulWidget {
  final String title;
  final Color themeColor;

  const QuizPage({super.key, required this.title, required this.themeColor});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int _currentQuestionIndex = 0;
  int? _selectedAnswerIndex;
  bool _isFinished = false;

  final List<Map<String, dynamic>> _questions = [
    {
      'question': "Quel est le premier réflexe face à une victime d'arrêt cardiaque ?",
      'options': [
        'Lui donner à boire',
        'Vérifier la respiration et appeler les secours',
        'La mettre en Position Latérale de Sécurité',
      ],
      'correct': 1
    },
    {
      'question': 'À quel rythme doit-on effectuer le massage cardiaque ?',
      'options': [
        '60 compressions par minute',
        '100 à 120 compressions par minute',
        'Le plus vite possible sans compter',
      ],
      'correct': 1
    },
    {
      'question': 'Où place-t-on les mains pour réaliser un massage cardiaque chez un adulte ?',
      'options': [
        'Sur le ventre',
        'Sur la moitié inférieure du sternum',
        'Côté gauche, près du cœur',
      ],
      'correct': 1
    },
  ];

  void _submitAnswer() {
    if (_selectedAnswerIndex == null) return;

    if (_selectedAnswerIndex == _questions[_currentQuestionIndex]['correct']) {
      if (_currentQuestionIndex < _questions.length - 1) {
        setState(() {
          _currentQuestionIndex++;
          _selectedAnswerIndex = null;
        });
      } else {
        setState(() {
          _isFinished = true;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mauvaise réponse, réessayez !'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFinished) {
      return _buildSuccessScreen();
    }

    final question = _questions[_currentQuestionIndex];
    final double progress = (_currentQuestionIndex) / _questions.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.clear, color: Colors.grey),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Quiz : ${widget.title}',
          style: const TextStyle(color: AppColors.navyDeep, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(widget.themeColor),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 32),
              
              Text(
                'Question ${_currentQuestionIndex + 1}/${_questions.length}',
                style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                question['question'],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navyDeep, height: 1.3),
              ),
              const SizedBox(height: 48),

              ...List.generate(
                (question['options'] as List).length,
                (index) {
                  final bool isSelected = _selectedAnswerIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAnswerIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? widget.themeColor.withValues(alpha: 0.1) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? widget.themeColor : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: isSelected ? widget.themeColor : Colors.grey[400]!, width: 2),
                              color: isSelected ? widget.themeColor : Colors.transparent,
                            ),
                            child: isSelected ? const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Colors.white) : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              question['options'][index],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected ? widget.themeColor : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const Spacer(),
              ElevatedButton(
                onPressed: _selectedAnswerIndex != null ? _submitAnswer : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.themeColor,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('VALIDER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: widget.themeColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.white, size: 120),
                const SizedBox(height: 32),
                const Text(
                  'Félicitations !',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vous avez validé le module et obtenu le badge :',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.heart_fill, color: widget.themeColor, size: 32),
                      const SizedBox(width: 12),
                      Text(
                        'Héros ${widget.title}',
                        style: TextStyle(color: widget.themeColor, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                ElevatedButton(
                  onPressed: () {
                    // Pop Quiz and CourseDetails to go back to Training Hub
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: widget.themeColor,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("RETOUR À L'ACADÉMIE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
