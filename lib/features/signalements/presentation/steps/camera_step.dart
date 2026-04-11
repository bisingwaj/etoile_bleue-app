import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/signalement_models.dart';
import '../../providers/signalement_draft_provider.dart';
import '../../data/signalement_media_processor.dart';

class CameraStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final bool isActive;

  const CameraStep({super.key, required this.onNext, this.isActive = true});

  @override
  ConsumerState<CameraStep> createState() => _CameraStepState();
}

class _CameraStepState extends ConsumerState<CameraStep> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  void _showLimit(String msg) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error, duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _takePhoto() async {
    if (_isProcessing) return;
    
    final draft = ref.read(signalementDraftProvider);
    if (draft.photoCount >= MediaLimits.maxPhotos) {
      _showLimit('signalement.limit_photos_exceeded'.tr(namedArgs: {'max': '${MediaLimits.maxPhotos}'}));
      return;
    }

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();
    try {
      final xFile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1920);
      if (xFile != null) {
        ref.read(signalementDraftProvider.notifier).addMedia(PendingMediaFile(
          file: File(xFile.path),
          type: 'image',
          originalFilename: xFile.name,
        ));
      }
    } catch (e) {
      debugPrint('[Signalement] Camera error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _startVideo() async {
    if (_isProcessing) return;
    
    final draft = ref.read(signalementDraftProvider);
    if (draft.videoCount >= MediaLimits.maxVideos) {
      _showLimit('signalement.limit_videos_exceeded'.tr(namedArgs: {'max': '${MediaLimits.maxVideos}'}));
      return;
    }

    setState(() => _isProcessing = true);
    HapticFeedback.heavyImpact();
    try {
      // Appel natif de la caméra vidéo
      final xFile = await _picker.pickVideo(source: ImageSource.camera, maxDuration: Duration(seconds: MediaLimits.maxVideoDuration));
      if (xFile != null) {
        ref.read(signalementDraftProvider.notifier).addMedia(PendingMediaFile(
          file: File(xFile.path),
          type: 'video',
          originalFilename: xFile.name,
          durationSeconds: 0, // Pas géré précisément par pickVideo natif (géré côté compresseur)
        ));
      }
    } catch (e) {
      debugPrint('[Signalement] Video error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                ListTile(
                  leading: const Icon(CupertinoIcons.photo_fill, color: AppColors.blue),
                  title: Text('signalement.camera_gallery_photos'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'photos'),
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.videocam_fill, color: AppColors.error),
                  title: Text('signalement.camera_gallery_video'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'video'),
                ),
              ],
            ),
          ),
        ),
      );

      if (source == null) return;

      if (source == 'video') {
        final draft = ref.read(signalementDraftProvider);
        if (draft.videoCount >= MediaLimits.maxVideos) {
          _showLimit('signalement.limit_videos_exceeded'.tr(namedArgs: {'max': '${MediaLimits.maxVideos}'}));
          return;
        }
        final video = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: Duration(seconds: MediaLimits.maxVideoDuration));
        if (video != null) {
          ref.read(signalementDraftProvider.notifier).addMedia(PendingMediaFile(
            file: File(video.path),
            type: 'video',
            originalFilename: video.name,
          ));
        }
      } else {
        final images = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
        for (final img in images) {
          final draft = ref.read(signalementDraftProvider);
          if (draft.photoCount >= MediaLimits.maxPhotos) break;
          ref.read(signalementDraftProvider.notifier).addMedia(PendingMediaFile(
            file: File(img.path),
            type: 'image',
            originalFilename: img.name,
          ));
        }
      }
    } catch (e) {
      debugPrint('[Signalement] Gallery picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('signalement.camera_gallery_error'.tr()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _glassButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    final draft = ref.watch(signalementDraftProvider);
    final mediaCount = draft.media.length;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Top Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _glassButton(CupertinoIcons.xmark, () => Navigator.of(context).maybePop()),
                  const Text(
                    "Preuves (Optionnel)",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.camera_viewfinder, size: 72, color: AppColors.blue.withValues(alpha: 0.8)).animate().scale(delay: 100.ms, duration: 400.ms, curve: Curves.easeOutBack),
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          "Ajoutez des photos ou de courtes vidéos pour aider les secours à mieux évaluer la situation.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 48),

                      _buildBigButton(
                        icon: CupertinoIcons.camera_fill,
                        label: "Prendre une photo",
                        color: AppColors.blue,
                        onTap: _takePhoto,
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
                      
                      const SizedBox(height: 16),
                      
                      _buildBigButton(
                        icon: CupertinoIcons.videocam_fill,
                        label: "Filmer la scène",
                        color: AppColors.error,
                        onTap: _startVideo,
                      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
                      
                      const SizedBox(height: 16),
                      
                      _buildBigButton(
                        icon: CupertinoIcons.photo_fill_on_rectangle_fill,
                        label: "Choisir dans la galerie",
                        color: Colors.white60,
                        onTap: _pickFromGallery,
                        isSecondary: true,
                      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mediaCount > 0 ? "$mediaCount média(s) ajouté(s)" : "Aucune preuve",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (mediaCount > 0)
                          const Text("Prêt à continuer", style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                         HapticFeedback.mediumImpact();
                         widget.onNext();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(mediaCount > 0 ? "Suivant" : "Passer", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 8),
                          const Icon(CupertinoIcons.arrow_right, size: 18),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBigButton({
    required IconData icon, 
    required String label, 
    required Color color, 
    required VoidCallback onTap,
    bool isSecondary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessing ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: color.withValues(alpha: 0.3),
          highlightColor: color.withValues(alpha: 0.1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: isSecondary ? Colors.transparent : color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: isSecondary ? 0.3 : 0.6), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isSecondary ? Colors.white70 : color, size: 24),
                const SizedBox(width: 12),
                Text(
                  label, 
                  style: TextStyle(
                    color: isSecondary ? Colors.white70 : Colors.white, 
                    fontSize: 16, 
                    fontWeight: FontWeight.w600
                  )
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
