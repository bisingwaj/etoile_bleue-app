import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/utils/dynamic_island_toast.dart';
import 'package:etoile_bleue_mobile/core/services/location_service.dart';
import 'package:etoile_bleue_mobile/features/incidents/data/incident_repository.dart';
import 'incident_success_page.dart';

class IncidentCameraPage extends ConsumerStatefulWidget {
  const IncidentCameraPage({super.key});

  @override
  ConsumerState<IncidentCameraPage> createState() => _IncidentCameraPageState();
}

class _IncidentCameraPageState extends ConsumerState<IncidentCameraPage> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  
  bool _isInit = false;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  
  String _selectedCategory = 'Abus hospitalier';
  final List<Map<String, dynamic>> _categories = [
    {'name': 'Abus hospitalier', 'icon': CupertinoIcons.building_2_fill},
    {'name': 'Frais illégaux', 'icon': CupertinoIcons.money_dollar_circle_fill},
    {'name': 'Négligence', 'icon': CupertinoIcons.exclamationmark_triangle_fill},
    {'name': 'Accident', 'icon': CupertinoIcons.car_detailed},
    {'name': 'Incendie', 'icon': CupertinoIcons.flame_fill},
    {'name': 'Agression', 'icon': CupertinoIcons.shield_fill},
    {'name': 'Autre', 'icon': CupertinoIcons.question_circle_fill},
  ];

  late AnimationController _pulseController;
  
  // Preview Mode
  bool _showPreview = false;
  int _currentStep = 0; // 0 = Preview, 1 = Lieu, 2 = Temps, 3 = Détails
  
  // Step 1: Lieu
  String _locationOption = 'sur_place'; // 'sur_place' or 'manuel'
  final TextEditingController _addressController = TextEditingController();
  
  // Step 2: Temps
  String _timeOption = 'maintenant'; // 'maintenant' or 'manuel'
  DateTime _selectedDate = DateTime.now();

  final TextEditingController _detailsController = TextEditingController();
  
  bool _isDetailsAudio = false;
  late final RecorderController _detailsRecorderController;
  late final PlayerController _detailsPlayerController;
  bool _isRecordingDetails = false;
  String? _detailsAudioPath;

  File? _mediaFile;
  bool _isVideo = false;
  VideoPlayerController? _videoController;

  bool _isCompressing = false;
  double _compressionProgress = 0.0;
  bool _isSending = false;
  Subscription? _subscription;

  @override
  void initState() {
    super.initState();
    _detailsRecorderController = RecorderController();
    _detailsPlayerController = PlayerController();
    
    _detailsPlayerController.onCompletion.listen((_) async {
      if (mounted) {
        await _detailsPlayerController.seekTo(0);
        setState(() {}); // Actualise l'icône
      }
    });

    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _initCamera();
    
    _subscription = VideoCompress.compressProgress$.subscribe((progress) {
      if (mounted) setState(() => _compressionProgress = progress / 100);
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _setCamera(_cameras![_selectedCameraIndex]);
      } else {
        if (mounted) DynamicIslandToast.showError(context, "Aucune caméra trouvée.");
      }
    } catch (e) {
      if (mounted) DynamicIslandToast.showError(context, "Erreur d'accès à la caméra.");
    }
  }

  Future<void> _setCamera(CameraDescription description) async {
    _cameraController?.dispose();
    _cameraController = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );
    try {
      await _cameraController!.initialize();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      if (mounted) DynamicIslandToast.showError(context, "Erreur caméra : $e");
    }
  }

  void _switchCamera() {
    if (_cameras == null || _cameras!.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    _isInit = false;
    setState(() {});
    _setCamera(_cameras![_selectedCameraIndex]);
  }

  @override
  void dispose() {
    try {
      _detailsRecorderController.dispose();
    } catch (_) {}
    try {
      _detailsPlayerController.dispose();
    } catch (_) {}
    _detailsController.dispose();
    _recordTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    _videoController?.dispose();
    _subscription?.unsubscribe();
    super.dispose();
  }

  // --- CAPTURE METHODS --- //
  
  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isRecording) return;
    HapticFeedback.mediumImpact();
    try {
      final XFile pic = await _cameraController!.takePicture();
      _loadPreview(File(pic.path), false);
    } catch (e) {
      DynamicIslandToast.showError(context, "Erreur lors de la capture.");
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isRecording) return;
    HapticFeedback.lightImpact();
    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordDuration++);
        if (_recordDuration >= 30) {
          _stopVideoRecording(); // Auto stop at 30s
        }
      });
    } catch (e) {
      DynamicIslandToast.showError(context, "Erreur d'enregistrement vidéo.");
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo) return;
    _recordTimer?.cancel();
    HapticFeedback.heavyImpact();
    try {
      final XFile video = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
      });
      _loadPreview(File(video.path), true);
    } catch (e) {
      setState(() => _isRecording = false);
      DynamicIslandToast.showError(context, "Erreur d'arrêt vidéo.");
    }
  }

  // --- PREVIEW & SEND METHODS --- //

  Future<void> _loadPreview(File file, bool isVideo) async {
    setState(() {
      _showPreview = true;
      _mediaFile = file;
      _isVideo = isVideo;
    });

    if (isVideo) {
      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {});
          _videoController!.setLooping(true);
          _videoController!.play();
        });
    }
  }

  void _discardPreview() {
    _videoController?.dispose();
    _videoController = null;
    if (_mediaFile != null && _mediaFile!.existsSync()) {
      _mediaFile!.deleteSync();
    }
    setState(() {
      _showPreview = false;
      _mediaFile = null;
      _isVideo = false;
    });
  }

  Future<void> _compressAndSend() async {
    if (_mediaFile == null) return;
    
    setState(() {
      _isCompressing = true;
      _compressionProgress = 0.0;
    });

    File finalFile = _mediaFile!;

    try {
      // 1. Compression locale
      if (_isVideo) {
        final mediaInfo = await VideoCompress.compressVideo(
          _mediaFile!.path,
          quality: VideoQuality.Res640x480Quality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (mediaInfo?.file != null) finalFile = mediaInfo!.file!;
      } else {
        final dir = await getTemporaryDirectory();
        final targetPath = '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        setState(() => _compressionProgress = 0.3);
        final compressed = await FlutterImageCompress.compressAndGetFile(
          _mediaFile!.absolute.path,
          targetPath,
          quality: 70,
          minWidth: 1080,
          minHeight: 1080,
        );
        if (compressed != null) finalFile = File(compressed.path);
        setState(() => _compressionProgress = 0.5);
      }

      setState(() {
        _isCompressing = false;
        _isSending = true;
        _compressionProgress = 0.0;
      });

      // 2. Récupérer la position GPS
      final locationService = ref.read(locationServiceProvider);
      final gpsPosition = await locationService.getCurrentPosition();

      // 3. Upload Firebase Storage + Création Firestore
      final repo = ref.read(incidentRepositoryProvider);
      final result = await repo.submitIncident(
        file: finalFile,
        isVideo: _isVideo,
        category: _selectedCategory,
        details: _detailsController.text.trim().isNotEmpty
            ? _detailsController.text.trim()
            : null,
        location: gpsPosition,
        incidentTimestamp:
            _timeOption == 'maintenant' ? DateTime.now() : _selectedDate,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _compressionProgress = 0.5 + (progress * 0.5));
          }
        },
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => IncidentSuccessPage(
              category: _selectedCategory,
              mediaUrl: result.mediaUrl,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCompressing = false;
          _isSending = false;
        });
        DynamicIslandToast.showError(context, 'Erreur d\'envoi : $e');
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _getDetailsPrompt() {
    switch (_selectedCategory) {
      case 'Abus hospitalier':
        return 'Quel hôpital ? Précisez les faits.';
      case 'Frais illégaux':
        return 'Montant exigé et par qui ?';
      case 'Négligence':
        return 'Décrivez le manquement médical observé.';
      case 'Accident':
        return 'Y a-t-il des blessés graves ?';
      case 'Agression':
        return 'Les agresseurs sont-ils sur place ?';
      case 'Incendie':
        return 'Y a-t-il un risque de propagation ?';
      default:
        return 'Avez-vous d\'autres détails à transmettre ?';
    }
  }

  // --- UI BUILDING --- //

  Widget _buildTopLogoAndControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back Button
            Container(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            
            // App Logo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(6)),
                    child: const Icon(CupertinoIcons.star_fill, color: Colors.white, size: 12),
                  ),
                  const SizedBox(width: 8),
                  const Text('SIGNALEMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0)),
                ],
              ),
            ),
            
            // Switch Camera Button
            Container(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(CupertinoIcons.camera_rotate_fill, color: Colors.white, size: 24),
                onPressed: _switchCamera,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat['name'];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedCategory = cat['name'] as String);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.blue : Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.15)),
                boxShadow: isSelected ? [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 10)] : [],
              ),
              child: Row(
                children: [
                  Icon(cat['icon'] as IconData, color: isSelected ? Colors.white : Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    cat['name'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _takePicture,
      onLongPress: _startVideoRecording,
      onLongPressEnd: (_) => _stopVideoRecording(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isRecording ? 90 : 80,
        height: _isRecording ? 90 : 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 6),
          color: Colors.transparent,
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isRecording ? 40 : 64,
            height: _isRecording ? 40 : 64,
            decoration: BoxDecoration(
              color: _isRecording ? AppColors.red : Colors.white,
              borderRadius: BorderRadius.circular(_isRecording ? 10 : 32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulseController,
            child: Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_recordDuration),
            style: const TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.w600, 
              fontSize: 18, 
              fontFeatures: [FontFeature.tabularFigures()]
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showPreview) return _buildPreviewScreen();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Live Feed
          if (_isInit && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            const Center(child: CupertinoActivityIndicator(color: Colors.white)),

          // 2. Gradient overlays for better text visibility
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
                stops: const [0.0, 0.2, 0.6, 1.0],
              ),
            ),
          ),

          // 3. Top UI
          Positioned(
            top: 0, left: 0, right: 0,
            child: Column(
              children: [
                _buildTopLogoAndControls(),
                if (!_isRecording) _buildCategorySelector(),
              ],
            ),
          ),

          // 4. Bottom Capture Area
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRecording) _buildRecordingIndicator(),
                _buildCaptureButton(),
                const SizedBox(height: 16),
                const Text('Appui = Photo • Maintien = Vidéo', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- PREVIEW SCREEN --- //
  Widget _buildPreviewScreen() {
    final bool isBusy = _isCompressing || _isSending;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Media Source
          if (_isVideo && _videoController != null && _videoController!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            )
          else if (!_isVideo && _mediaFile != null)
            Image.file(_mediaFile!, fit: BoxFit.cover)
          else
            const Center(child: CupertinoActivityIndicator(color: Colors.white)),

          // Dark Overlay
          Container(color: Colors.black.withValues(alpha: 0.4)),

          // Header
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
                      child: Text(_selectedCategory, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                    ),
                    if (_isVideo)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.video_camera_solid, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('VIDÉO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 40, left: 24, right: 24,
            child: Row(
              children: [
                // Retake Button
                GestureDetector(
                  onTap: isBusy ? null : _discardPreview,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(CupertinoIcons.arrow_2_squarepath, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Send Button
                Expanded(
                  child: GestureDetector(
                    onTap: isBusy ? null : () => setState(() => _currentStep = 1),
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: isBusy ? Colors.grey[800] : AppColors.blue,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.arrow_right, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text('Continuer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (_currentStep > 0) _buildWizardOverlay(),
        ],
      ),
    );
  }

  Widget _buildWizardOverlay() {
    final bool isBusy = _isCompressing || _isSending;
    
    Widget content;
    String title;
    String getNextLabel() => _currentStep == 3 ? (isBusy ? 'Envoi...' : 'Confirmer l\'envoi') : 'Suivant';
    
    switch (_currentStep) {
      case 1:
        title = 'Où cela se passe-t-il ?';
        content = Column(
          children: [
            _buildOptionCard(
              title: 'Je suis sur place',
              subtitle: 'Utiliser ma position GPS actuelle',
              icon: CupertinoIcons.location_fill,
              isSelected: _locationOption == 'sur_place',
              onTap: () => setState(() => _locationOption = 'sur_place'),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              title: 'Saisir l\'adresse',
              subtitle: 'Préciser manuellement le lieu',
              icon: CupertinoIcons.map_pin_ellipse,
              isSelected: _locationOption == 'manuel',
              onTap: () => setState(() => _locationOption = 'manuel'),
            ),
            if (_locationOption == 'manuel') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: Croisement Boulevard du 30 juin...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ]
          ],
        );
        break;
      case 2:
        title = 'Quand cela se passe-t-il ?';
        content = Column(
          children: [
            _buildOptionCard(
              title: 'C\'est en cours (À l\'instant)',
              subtitle: 'L\'incident se déroule sous mes yeux',
              icon: CupertinoIcons.timer,
              isSelected: _timeOption == 'maintenant',
              onTap: () => setState(() => _timeOption = 'maintenant'),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              title: 'Plus tôt / Autre moment',
              subtitle: 'Définir une date et une heure',
              icon: CupertinoIcons.calendar,
              isSelected: _timeOption == 'manuel',
              onTap: () => setState(() => _timeOption = 'manuel'),
            ),
            if (_timeOption == 'manuel') ...[
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Localizations.override(
                  context: context,
                  locale: const Locale('fr', 'FR'),
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    child: StatefulBuilder(
                      builder: (context, setPickerState) {
                        return CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.dateAndTime,
                          initialDateTime: _selectedDate,
                          maximumDate: DateTime.now(),
                          use24hFormat: true,
                          onDateTimeChanged: (DateTime newDateTime) {
                            setPickerState(() {
                               _selectedDate = newDateTime;
                            });
                          },
                        );
                      }
                    ),
                  ),
                ),
              ),
            ]
          ],
        );
        break;
      case 3:
      default:
        title = 'Détails Optionnels';
        content = Column(
          children: [
            Text(
              _getDetailsPrompt(),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isDetailsAudio = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: !_isDetailsAudio ? AppColors.blue : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                        child: Center(child: Text('Texte', style: TextStyle(color: !_isDetailsAudio ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isDetailsAudio = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: _isDetailsAudio ? AppColors.blue : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                        child: Center(child: Text('Vocal', style: TextStyle(color: _isDetailsAudio ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (!_isDetailsAudio)
              TextField(
                controller: _detailsController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Tapez votre message ou ajoutez une note vocale.',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              )
            else
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Center(
                  child: _isRecordingDetails
                    ? Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: AudioWaveforms(
                              size: const Size(double.infinity, 40),
                              recorderController: _detailsRecorderController,
                              waveStyle: const WaveStyle(waveColor: Colors.red, extendWaveform: true, showMiddleLine: false, waveThickness: 4),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(CupertinoIcons.stop_circle_fill, color: Colors.red, size: 40),
                            onPressed: () async {
                              final path = await _detailsRecorderController.stop();
                              if (path != null) {
                                _detailsAudioPath = path;
                                await _detailsPlayerController.preparePlayer(path: path, noOfSamples: 100);
                              }
                              setState(() => _isRecordingDetails = false);
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      )
                    : _detailsAudioPath != null
                      ? Row(
                          children: [
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                _detailsPlayerController.playerState == PlayerState.playing 
                                    ? CupertinoIcons.pause_circle_fill 
                                    : CupertinoIcons.play_circle_fill, 
                                color: AppColors.blue, size: 36
                              ),
                              onPressed: () async {
                                if (_detailsPlayerController.playerState == PlayerState.playing) {
                                  await _detailsPlayerController.pausePlayer();
                                } else {
                                  await _detailsPlayerController.startPlayer();
                                }
                                setState(() {});
                              },
                            ),
                            Expanded(
                              child: AudioFileWaveforms(
                                size: const Size(double.infinity, 40),
                                playerController: _detailsPlayerController,
                                enableSeekGesture: true,
                                waveformType: WaveformType.long,
                                playerWaveStyle: const PlayerWaveStyle(fixedWaveColor: Colors.white54, liveWaveColor: AppColors.blue),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.trash, color: Colors.white54),
                              onPressed: () => setState(() {
                                _detailsAudioPath = null;
                              }),
                            ),
                          ],
                        )
                      : GestureDetector(
                          onTap: () async {
                              if (await _detailsRecorderController.checkPermission()) {
                                final dir = await getApplicationDocumentsDirectory();
                                _detailsAudioPath = '${dir.path}/details_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
                                await _detailsRecorderController.record(path: _detailsAudioPath!);
                                setState(() => _isRecordingDetails = true);
                              }
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.2), shape: BoxShape.circle),
                                child: const Icon(CupertinoIcons.mic_fill, size: 32, color: AppColors.blue),
                              ),
                              const SizedBox(height: 8),
                              const Text('Appuyez pour enregistrer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                            ],
                          ),
                        ),
                ),
              ),
          ],
        );
        break;
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.back, color: Colors.white),
                    onPressed: isBusy ? null : () {
                      setState(() {
                         _currentStep--;
                      });
                    },
                  ),
                  Text('Étape $_currentStep sur 3', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 48), // balance back button
                ],
              ),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              
              Expanded(
                child: SingleChildScrollView(
                  child: content,
                ),
              ),
              
              // Bottom Next/Send Button
              GestureDetector(
                onTap: isBusy ? null : () {
                  if (_currentStep < 3) {
                     setState(() => _currentStep++);
                  } else {
                     _compressAndSend();
                  }
                },
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: isBusy ? Colors.grey[800] : AppColors.blue,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      if (_isCompressing && _currentStep == 3)
                        FractionallySizedBox(
                          widthFactor: _compressionProgress.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      Center(
                        child: isBusy && _currentStep == 3
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                const SizedBox(width: 12),
                                Text(_isCompressing ? '${(_compressionProgress * 100).toInt()}% Comp...' : 'Envoi...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            )
                          : Text(getNextLabel(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({required String title, required String subtitle, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.blue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.blue : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isSelected ? AppColors.blue : Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppColors.blue, size: 28),
          ],
        ),
      ),
    );
  }
}
