import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/emergency_call_screen.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/services/location_service.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/features/incidents/data/incident_repository.dart';

class SosVocalSheet extends ConsumerStatefulWidget {
  final VoidCallback onSent;
  const SosVocalSheet({super.key, required this.onSent});

  @override
  ConsumerState<SosVocalSheet> createState() => _SosVocalSheetState();
}

class _SosVocalSheetState extends ConsumerState<SosVocalSheet> with TickerProviderStateMixin {
  late final RecorderController _recorderController;
  late final PlayerController _playerController;
  
  bool _isRecording = false;
  bool _isReviewing = false;
  bool _isPlaying = false;
  
  int _recordDuration = 0;
  Timer? _timer;
  String? _audioPath;

  late AnimationController _pulseController;
  late AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _recorderController = RecorderController();

    _playerController = PlayerController();
    
    _playerController.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _playerController.onCompletion.listen((_) async {
      if (mounted) {
        setState(() => _isPlaying = false);
        await _playerController.seekTo(0);
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.85,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorderController.dispose();
    _playerController.dispose();
    _pulseController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorderController.checkPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        _audioPath = '${dir.path}/sos_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _recorderController.record(path: _audioPath!);

        setState(() {
          _isRecording = true;
          _isReviewing = false;
          _recordDuration = 0;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
          setState(() => _recordDuration++);
        });
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecording({required bool keepForReview}) async {
    _timer?.cancel();
    final path = await _recorderController.stop();
    if (path != null) {
      _audioPath = path;
    }
    
    setState(() {
      _isRecording = false;
    });

    if (keepForReview && _audioPath != null && _recordDuration >= 1) {
      setState(() {
        _isReviewing = true;
      });
      await _playerController.preparePlayer(
        path: _audioPath!, 
        noOfSamples: 100,
      );
    } else {
      _discardRecording();
    }
  }

  Future<void> _togglePlayPause() async {
    if (_audioPath == null) return;
    
    if (_isPlaying) {
      await _playerController.pausePlayer();
    } else {
      await _playerController.startPlayer();
    }
  }

  Future<void> _discardRecording() async {
    if (_audioPath != null) {
      final file = File(_audioPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    setState(() {
      _isReviewing = false;
      _recordDuration = 0;
      _audioPath = null;
    });
  }

  Future<void> _startLiveCall() async {
    try {
      await ref.read(callStateProvider.notifier).startSosCall();
      if (!mounted) return;
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (context) => const EmergencyCallScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('errors.detail'.tr(namedArgs: {'error': e.toString()}))),
        );
      }
    }
  }

  void _showCallChoiceDialog() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text(
          'Sélectionnez le type d\'appel',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        message: const Text(
          'Souhaitez-vous déclencher un appel d\'urgence interne (Vidéo) ou contacter les secours par réseau mobile classique ?',
        ),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(context);
              _startLiveCall();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.videocam_fill, color: AppColors.blue, size: 22),
                SizedBox(width: 8),
                Text('Appel Intégré (Recommandé)', style: TextStyle(color: AppColors.blue)),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _launchNormalCall();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.phone_fill, color: AppColors.blue, size: 22),
                SizedBox(width: 8),
                Text('Appel Numéro d\'Urgence (112)', style: TextStyle(color: AppColors.blue)),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('common.cancel'.tr()),
        ),
      ),
    );
  }

  Future<void> _launchNormalCall() async {
    // Remplacer "112" par le numéro approprié selon la région
    final Uri url = Uri(scheme: 'tel', path: '112'); 
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      debugPrint('Impossible d\'ouvrir l\'appel normal.');
    }
  }

  Future<void> _sendRecording() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    // 1. Position GPS
    Map<String, double>? gpsLocation;
    try {
      final locationService = ref.read(locationServiceProvider);
      gpsLocation = await locationService.getCurrentPosition().timeout(const Duration(seconds: 5));
    } catch (_) {}

    // 2. Upload et création dans la table incidents (Supabase) via le Repository
    try {
      if (_audioPath != null) {
        final file = File(_audioPath!);
        final incidentRepo = ref.read(incidentRepositoryProvider);
        await incidentRepo.submitIncident(
          file: file,
          isVideo: false, // c'est un audio, le repo utilise 'photo' ou 'video', mais on peut l'améliorer plus tard
          category: 'SOS Vocal',
          details: 'Alerte vocale émise depuis le bouton SOS',
          location: gpsLocation,
          incidentTimestamp: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('SOS Vocal Error: Impossible de créer l\'alerte: $e');
    }

    if (mounted) {
      Navigator.pop(context); // close loader
      widget.onSent();
      Navigator.pop(context); // close sheet
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 50),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            
            if (!_isReviewing) ...[
              const Icon(CupertinoIcons.mic_fill, size: 40, color: AppColors.blue),
              const SizedBox(height: 12),
              Text(
                'SOS Vocal',
                style: AppTextStyles.headlineLarge.copyWith(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Touchez le micro pour commencer l\'enregistrement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 24),

              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(animation),
                          child: FadeTransition(opacity: animation, child: child),
                        ),
                        child: Text(
                          _formatDuration(_recordDuration),
                          key: ValueKey<int>(_recordDuration),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w300,
                            color: Colors.red,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Colors.redAccent, Colors.orangeAccent],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ).createShader(bounds),
                              child: AudioWaveforms(
                                enableGesture: false,
                                size: Size(constraints.maxWidth, 48),
                                recorderController: _recorderController,
                                waveStyle: const WaveStyle(
                                  waveColor: Colors.white,
                                  extendWaveform: true,
                                  showMiddleLine: false,
                                  waveThickness: 4.0,
                                  spacing: 6.0,
                                ),
                              ),
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 24),

              const SizedBox(height: 32),

              GestureDetector(
                onPanDown: (_) => _pressController.reverse(),
                onPanCancel: () => _pressController.forward(),
                onPanEnd: (_) => _pressController.forward(),
                onTap: () {
                  _pressController.reverse().then((_) => _pressController.forward());
                  if (_isRecording) {
                    _stopRecording(keepForReview: true);
                  } else {
                    _startRecording();
                  }
                },
                child: ScaleTransition(
                  scale: _pressController,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final shadowOpacity = _isRecording ? (0.2 + (_pulseController.value * 0.3)) : 0.0;
                      final shadowRadius = _isRecording ? (10.0 + (_pulseController.value * 20.0)) : 10.0;
                      
                      return Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.red : AppColors.blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_isRecording ? Colors.red : AppColors.blue).withOpacity(_isRecording ? shadowOpacity : 0.3),
                              blurRadius: shadowRadius,
                              spreadRadius: _isRecording ? (_pulseController.value * 5.0) : 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isRecording ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              if (!_isRecording) ...[
                const Text('Appuyez et parlez', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 32),
                
                // NEW: Direct Call Button
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton.icon(
                    onPressed: _showCallChoiceDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue.withValues(alpha: 0.1),
                      foregroundColor: AppColors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    icon: const Icon(CupertinoIcons.phone_fill, size: 20),
                    label: const Text(
                      'Appel direct (Vidéo/Audio)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('common.cancel'.tr(), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ],
            ] else ...[
              // --- REVIEW STATE ---
              const Icon(CupertinoIcons.waveform, size: 40, color: AppColors.blue),
              const SizedBox(height: 12),
              Text(
                'Réécouter le message',
                style: AppTextStyles.headlineLarge.copyWith(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Votre message a été compressé pour un envoi rapide.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Playback UI
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 40,
                      color: AppColors.blue,
                      icon: Icon(_isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill),
                      onPressed: _togglePlayPause,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AudioFileWaveforms(
                        size: Size(MediaQuery.of(context).size.width - 160, 40),
                        playerController: _playerController,
                        enableSeekGesture: true,
                        waveformType: WaveformType.long,
                        playerWaveStyle: const PlayerWaveStyle(
                          fixedWaveColor: Colors.black26,
                          liveWaveColor: AppColors.blue,
                          spacing: 4,
                          waveThickness: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatDuration(_recordDuration),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.navyDeep),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  // Trash Button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 28,
                      color: Colors.grey[800],
                      icon: const Icon(CupertinoIcons.trash_fill),
                      onPressed: _discardRecording,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Send Button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      icon: const Icon(CupertinoIcons.paperplane_fill, size: 24),
                      label: const Text(
                        'Transmettre l\'urgence',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _sendRecording,
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
