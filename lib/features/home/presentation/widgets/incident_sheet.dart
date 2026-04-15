import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/utils/dynamic_island_toast.dart';

class IncidentSheet extends StatefulWidget {
  final VoidCallback onSent;
  const IncidentSheet({super.key, required this.onSent});

  @override
  State<IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<IncidentSheet> {
  final ImagePicker _picker = ImagePicker();
  File? _mediaFile;
  bool _isVideo = false;
  
  VideoPlayerController? _videoController;
  
  String _selectedType = 'accident';
  bool _isCompressing = false;
  double _compressionProgress = 0.0;
  bool _isSending = false;
  
  // To track subscription for video_compress progress
  Subscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = VideoCompress.compressProgress$.subscribe((progress) {
      if (mounted) {
        setState(() {
          _compressionProgress = progress / 100;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.only(top: 16, bottom: 40, left: 24, right: 24),
        decoration: const BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.vertical(top: Radius.circular(36))
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 32),
              Text('incident_sheet.source_title'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: AppColors.navyDeep)),
              const SizedBox(height: 8),
              Text('incident_sheet.source_subtitle'.tr(), style: TextStyle(color: Colors.grey, fontSize: 15, fontFamily: 'Marianne')),
              const SizedBox(height: 32),
              
              // Camera
              _buildCleanListTile(
                icon: CupertinoIcons.camera_fill, 
                title: 'incident_sheet.take_photo_title'.tr(), 
                subtitle: 'incident_sheet.take_photo_sub'.tr(), 
                color: AppColors.blue, 
                onTap: () async {
                  Navigator.pop(ctx);
                  final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                  if (photo != null) _loadMedia(File(photo.path), false);
                }
              ),
              const Padding(padding: EdgeInsets.only(left: 64), child: Divider(height: 1, color: Color(0xFFEEEEEE))),
              
              // Video
              _buildCleanListTile(
                icon: CupertinoIcons.video_camera_solid, 
                title: 'incident_sheet.record_video_title'.tr(), 
                subtitle: 'incident_sheet.record_video_sub'.tr(), 
                color: AppColors.red, 
                onTap: () async {
                  Navigator.pop(ctx);
                  final XFile? video = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
                  if (video != null) _loadMedia(File(video.path), true);
                }
              ),
              const Padding(padding: EdgeInsets.only(left: 64), child: Divider(height: 1, color: Color(0xFFEEEEEE))),

              // Galerie
              _buildCleanListTile(
                icon: CupertinoIcons.photo_on_rectangle, 
                title: 'incident_sheet.gallery_title'.tr(), 
                subtitle: 'incident_sheet.gallery_sub'.tr(), 
                color: AppColors.navyDeep, 
                onTap: () async {
                  Navigator.pop(ctx);
                  final XFile? media = await _picker.pickMedia();
                  if (media != null) {
                    final isVid = media.path.toLowerCase().endsWith('.mp4') || media.path.toLowerCase().endsWith('.mov');
                    _loadMedia(File(media.path), isVid);
                  }
                }
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCleanListTile({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navyDeep)),
      subtitle: Text(subtitle, style: TextStyle(fontFamily: 'Marianne', fontSize: 13, color: Colors.grey[600])),
      trailing: Icon(CupertinoIcons.chevron_right, size: 18, color: Colors.grey[400]),
    );
  }

  Future<void> _loadMedia(File file, bool isVideo) async {
    setState(() {
      _mediaFile = file;
      _isVideo = isVideo;
    });

    if (isVideo) {
      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {});
          _videoController!.setLooping(true);
          _videoController!.play();
          
          // Automatic compression and sending logic after init
          _compressAndSend();
        });
    } else {
      // Automatic compression and sending logic immediately for images
      _compressAndSend();
    }
  }

  Future<File?> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 1080,
      minHeight: 1080,
    );
    return result != null ? File(result.path) : null;
  }

  Future<File?> _compressVideo(File file) async {
    final info = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.Res640x480Quality,
      deleteOrigin: false,
      includeAudio: true,
    );
    return info?.file;
  }

  Future<void> _compressAndSend() async {
    if (_mediaFile == null) return;
    
    setState(() {
      _isCompressing = true;
      _compressionProgress = 0.0;
    });

    File? compressedFile;
    
    try {
      if (_isVideo) {
        compressedFile = await _compressVideo(_mediaFile!);
      } else {
        // Image compression is usually instant, so we fake a small progress for UX
        setState(() => _compressionProgress = 0.5);
        compressedFile = await _compressImage(_mediaFile!);
        setState(() => _compressionProgress = 1.0);
      }

      setState(() {
        _isCompressing = false;
        _isSending = true;
      });

      // Simulate sending to dispatch
      if (compressedFile != null) {
        debugPrint('Sending compressed file: ${compressedFile.path}');
      }
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        widget.onSent();
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isCompressing = false;
        _isSending = false;
      });
      if (mounted) {
        DynamicIslandToast.showError(context, 'incident_sheet.compression_error'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  Widget _buildMediaPreview() {
    return Container(
      height: 280,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Media
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

          // Premium Dark Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),

          // Top Info Overlay
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'incident_sheet.type_${_selectedType}'.tr().toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                if (_isVideo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.video_camera_solid, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text('incident_sheet.video_badge'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Action Overlay
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              children: [
                // Replace button
                GestureDetector(
                  onTap: _isCompressing || _isSending ? null : _pickMedia,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(CupertinoIcons.arrow_2_squarepath, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Big Send Button with integrated Progress
                Expanded(
                  child: GestureDetector(
                    onTap: _isCompressing || _isSending ? null : _compressAndSend,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: _isCompressing || _isSending ? Colors.grey[800] : AppColors.blue,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          if (!_isCompressing && !_isSending)
                            BoxShadow(color: AppColors.blue.withValues(alpha: 0.5), blurRadius: 15, offset: const Offset(0, 5))
                        ],
                      ),
                      child: Stack(
                        children: [
                          if (_isCompressing)
                            FractionallySizedBox(
                              widthFactor: _compressionProgress.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.blue.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          Center(
                            child: _iscompressingOrSending()
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                      const SizedBox(width: 12),
                                      Text(
                                        _isCompressing
                                            ? 'incident_sheet.compression'.tr(namedArgs: {'percent': '${(_compressionProgress * 100).toInt()}'})
                                            : 'incident_sheet.sending'.tr(),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 18),
                                      const SizedBox(width: 10),
                                      Text(
                                        'incident_sheet.send_now'.tr(),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  bool _iscompressingOrSending() => _isCompressing || _isSending;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 32),
            
            if (_mediaFile == null) ...[
              Text('incident_sheet.report_headline'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 36, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1.0, color: AppColors.navyDeep)),
              const SizedBox(height: 12),
              Text('incident_sheet.report_subtitle'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 15, fontFamily: 'Marianne')),
              const SizedBox(height: 32),

              // Type Dropdown
              Text('incident_sheet.nature_label'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedType,
                    isExpanded: true,
                    icon: const Icon(CupertinoIcons.chevron_down, color: AppColors.navyDeep, size: 20),
                    items: ['accident', 'robbery', 'fire', 'riot', 'other']
                        .map((String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text('incident_sheet.type_$value'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navyDeep)),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedType = val!),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Media Picker Button
              Text('incident_sheet.media_label'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickMedia,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                        child: const Icon(CupertinoIcons.camera_fill, size: 24, color: AppColors.blue),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('incident_sheet.add_media_title'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.blue)),
                            const SizedBox(height: 4),
                            Text('incident_sheet.add_media_sub'.tr(), style: TextStyle(fontFamily: 'Marianne', fontSize: 13, color: Colors.grey[600]))
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Cancel text
              Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Text('incident_sheet.cancel'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)),
                ),
              ),
            ] else ...[
              // PREVIEW MODE WITH PREMIUM DESIGN OVERLAY
              Text('incident_sheet.preview_title'.tr(), textAlign: TextAlign.center, style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.w900, fontSize: 24)),
              const SizedBox(height: 8),
              Text('incident_sheet.preview_hint'.tr(), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 15)),
              const SizedBox(height: 24),
              _buildMediaPreview(),
            ]
          ],
        ),
      ),
    );
  }
}
