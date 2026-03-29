import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/emergency_contacts_provider.dart';
import 'package:country_flags/country_flags.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/features/profile/data/profile_repository.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      await ref.read(profileImageProvider.notifier).setImage(File(picked.path));
    }
  }

  void _showPhotoMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('profile.profile_photo'.tr(), style: TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
            child: Text('profile.take_photo'.tr(), style: TextStyle(fontFamily: 'Marianne', color: AppColors.blue)),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
            child: Text('profile.choose_gallery'.tr(), style: TextStyle(fontFamily: 'Marianne', color: AppColors.blue)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          isDestructiveAction: true,
          child: const Text('Annuler', style: TextStyle(fontFamily: 'Marianne')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _profileImage = ref.watch(profileImageProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.grey[50],
              title: Text('profile.title'.tr(), style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
              centerTitle: true,
              floating: true,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    // Header Avatar
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () => _showPhotoMenu(context),
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.blue, width: 3),
                                image: DecorationImage(
                                  image: _profileImage != null 
                                      ? FileImage(_profileImage) as ImageProvider 
                                      : const NetworkImage('https://api.dicebear.com/7.x/notionists/png?seed=David&backgroundColor=e6f0fa'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                                  child: const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Consumer(
                            builder: (context, ref, _) {
                              final userAsync = ref.watch(userProvider);
                              final pdName = userAsync.when(
                                data: (data) => "${data?['first_name'] ?? ''} ${data?['last_name'] ?? ''}".trim(),
                                loading: () => "Chargement...",
                                error: (_, __) => "Utilisateur",
                              );
                              final pdPhone = userAsync.when(
                                data: (data) => data?['phone'] ?? '+243 ...',
                                loading: () => "...",
                                error: (_, __) => "...",
                              );
                              final pdMemberSince = userAsync.when(
                                data: (data) {
                                  final ts = data?['created_at'];
                                  if (ts == null) return 'profile.member_since'.tr();
                                  final date = DateTime.tryParse(ts.toString()) ?? DateTime.now();
                                  const months = ['Jan', 'Fév', 'Mars', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
                                  return 'Inscrit depuis ${months[date.month - 1]} ${date.year}';
                                },
                                loading: () => "...",
                                error: (_, __) => 'profile.member_since'.tr(),
                              );

                              return Column(
                                children: [
                                  Text(pdName.isEmpty ? 'Utilisateur' : pdName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyDeep)),
                                  const SizedBox(height: 4),
                                  Text(pdPhone, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                  const SizedBox(height: 2),
                                  Text(pdMemberSince, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                ],
                              );
                            }
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Sections
                    _buildSectionHeader('profile.medical_data'.tr()),
                    Consumer(
                      builder: (context, ref, _) {
                        final userData = ref.watch(userProvider).value;
                        final bloodType = userData?['blood_type'] as String? ?? 'Non renseigné';
                        final allergies = (userData?['allergies'] as List?)?.cast<String>() ?? [];
                        final medHistory = (userData?['medical_history'] as List?)?.cast<String>() ?? [];
                        return _buildCardGroup([
                          _buildListTile(context, icon: CupertinoIcons.heart_fill, color: AppColors.red,
                            title: 'profile.blood_group'.tr(), subtitle: bloodType,
                            onTap: () => _openSheet(context, _BloodTypeSheet(initial: bloodType))),
                          _buildListTile(context, icon: CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange,
                            title: 'profile.allergies'.tr(),
                            subtitle: allergies.isEmpty ? 'Non renseigné' : allergies.join(', '),
                            onTap: () => _openSheet(context, _TagsEditSheet(title: 'profile.allergies'.tr(), tags: allergies, fieldKey: 'allergies'))),
                          _buildListTile(context, icon: CupertinoIcons.bandage_fill, color: AppColors.blue,
                            title: 'profile.medical_history'.tr(),
                            subtitle: medHistory.isEmpty ? 'Non renseigné' : medHistory.join(', '),
                            isLast: true,
                            onTap: () => _openSheet(context, _TagsEditSheet(title: 'Antécédents Médicaux', tags: medHistory, fieldKey: 'medicalHistory'))),
                        ]);
                      },
                    ),

                    const SizedBox(height: 24),
                    _buildSectionHeader('profile.security_emergencies'.tr()),
                    _buildCardGroup([
                      _buildListTile(context, icon: CupertinoIcons.person_2_fill, color: AppColors.navy, title: 'profile.trusted_contacts'.tr(), subtitle: 'profile.configured_contacts'.tr(), onTap: () => _openSheet(context, const _ContactsSheet())),
                      _buildListTile(context, icon: CupertinoIcons.phone_fill, color: Colors.green, title: 'profile.phone_number'.tr(), subtitle: '+243 81 234 5678', onTap: () => _openSheet(context, const _PhoneEditSheet())),
                      _buildListTile(context, icon: CupertinoIcons.shield_lefthalf_fill, color: Colors.purple, title: 'profile.distress_pin'.tr(), subtitle: 'profile.disabled'.tr(), isLast: true, onTap: () {}),
                    ]),

                    const SizedBox(height: 24),
                    _buildSectionHeader('profile.account'.tr()),
                    _buildCardGroup([
                      _buildListTile(context, icon: CupertinoIcons.globe, color: AppColors.blue, title: 'profile.change_lang'.tr(), onTap: () => _openSheet(context, const _LanguageSheet())),
                      _buildListTile(context, icon: CupertinoIcons.settings, color: Colors.grey[700]!, title: 'profile.system_settings'.tr(), onTap: () {}),
                      _buildListTile(context, icon: CupertinoIcons.square_arrow_right, color: AppColors.red, title: 'profile.logout'.tr(), isLast: true, onTap: () {}),
                    ]),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1.2),
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildListTile(BuildContext context, {required IconData icon, required Color color, required String title, String? subtitle, bool isLast = false, required VoidCallback onTap}) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)) : null,
          trailing: const Icon(CupertinoIcons.chevron_right, color: Colors.grey, size: 18),
          onTap: onTap,
        ),
        if (!isLast) Divider(height: 1, indent: 64, color: Colors.grey[200]),
      ],
    );
  }

  void _openSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => sheet,
    );
  }
}

// ==========================================
// 1. BLOOD TYPE SHEET
// ==========================================
class _BloodTypeSheet extends ConsumerStatefulWidget {
  final String initial;
  const _BloodTypeSheet({this.initial = 'O+'});

  @override
  ConsumerState<_BloodTypeSheet> createState() => _BloodTypeSheetState();
}

class _BloodTypeSheetState extends ConsumerState<_BloodTypeSheet> {
  late String _selected;
  bool _saving = false;
  final List<String> types = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            Text('profile.blood_group'.tr(), style: TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
            const SizedBox(height: 8),
            Text('profile.select_blood'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 15, fontFamily: 'Marianne')),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: types.map((t) {
                final isSelected = _selected == t;
                return GestureDetector(
                  onTap: () => setState(() => _selected = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: (MediaQuery.of(context).size.width - 48 - 36) / 4,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.red : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? AppColors.red : Colors.grey[300]!, width: 2),
                    ),
                    child: Text(t, style: TextStyle(fontFamily: 'Marianne', fontSize: 18, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppColors.navyDeep)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                await ref.read(profileRepositoryProvider).saveBloodType(_selected);
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
              ),
              child: Text(_saving ? 'Enregistrement...' : 'profile.save_btn'.tr(), style: TextStyle(fontFamily: 'Marianne', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text('profile.cancel_btn'.tr(), style: TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. TAGS SHEET (Allergies / Antécédents)
// ==========================================
class _TagsEditSheet extends ConsumerStatefulWidget {
  final String title;
  final List<String> tags;
  final String fieldKey; // 'allergies' | 'medicalHistory' | 'medications'
  const _TagsEditSheet({required this.title, required this.tags, required this.fieldKey});

  @override
  ConsumerState<_TagsEditSheet> createState() => _TagsEditSheetState();
}

class _TagsEditSheetState extends ConsumerState<_TagsEditSheet> {
  late List<String> _currentTags;
  bool _saving = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentTags = List.from(widget.tags);
  }

  void _addTag() {
    if (_controller.text.trim().isNotEmpty) {
      setState(() {
        _currentTags.add(_controller.text.trim());
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            Text(widget.title, style: const TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _addTag(),
                    decoration: InputDecoration(
                      filled: true, fillColor: Colors.grey[100],
                      hintText: 'profile.add_tag'.tr(), hintStyle: const TextStyle(fontFamily: 'Marianne'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _addTag,
                  child: Container(
                    height: 52, width: 52,
                    decoration: BoxDecoration(color: AppColors.navyDeep, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(CupertinoIcons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_currentTags.isNotEmpty)
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _currentTags.map((t) => Chip(
                  label: Text(t, style: const TextStyle(fontFamily: 'Marianne', color: Colors.white, fontWeight: FontWeight.w600)),
                  backgroundColor: AppColors.navyDeep,
                  deleteIcon: const Icon(CupertinoIcons.clear_thick, size: 14, color: Colors.white70),
                  onDeleted: () => setState(() => _currentTags.remove(t)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none),
                )).toList(),
              ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      final repo = ref.read(profileRepositoryProvider);
                      switch (widget.fieldKey) {
                        case 'allergies':
                          await repo.saveAllergies(_currentTags);
                          break;
                        case 'medicalHistory':
                          await repo.saveMedicalHistory(_currentTags);
                          break;
                        case 'medications':
                          await repo.saveMedications(_currentTags);
                          break;
                      }
                      if (mounted) Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                _saving ? 'Enregistrement...' : 'profile.save_btn'.tr(),
                style: TextStyle(
                    fontFamily: 'Marianne',
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. CONTACTS SHEET
// ==========================================
class _ContactsSheet extends ConsumerStatefulWidget {
  const _ContactsSheet();

  @override
  ConsumerState<_ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends ConsumerState<_ContactsSheet> {
  bool _isAdding = false;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  Future<void> _addContact() async {
    if (_nameCtrl.text.trim().isNotEmpty && _phoneCtrl.text.trim().length >= 9) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('users_directory').update({
          'emergency_contact_name': _nameCtrl.text.trim(),
          'emergency_contact_phone': '+243 ${_phoneCtrl.text.trim()}',
        }).eq('auth_user_id', user.id);
        ref.invalidate(emergencyContactsProvider);
      }
      if (mounted) setState(() => _isAdding = false);
      _nameCtrl.clear();
      _phoneCtrl.clear();
    }
  }

  Future<void> _deleteContact(String contactId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await Supabase.instance.client.from('users_directory').update({
        'emergency_contact_name': null,
        'emergency_contact_phone': null,
      }).eq('auth_user_id', user.id);
      ref.invalidate(emergencyContactsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fix #3 : Utilisation du provider global — le stream n'est plus recréé à chaque rebuild
    final contactsStream = ref.watch(emergencyContactsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * (_isAdding ? 0.9 : 0.85),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            Text(_isAdding ? 'profile.new_contact'.tr() : 'profile.trusted_contacts'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
            const SizedBox(height: 8),
            Text(_isAdding ? 'profile.add_relative'.tr() : 'profile.auto_notified'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 15, fontFamily: 'Marianne')),
            const SizedBox(height: 24),
            if (!_isAdding) ...[
              Expanded(
                child: contactsStream.when(
                  loading: () => const Center(child: CupertinoActivityIndicator()),
                  error: (e, _) => Center(child: Text('Erreur: $e')),
                  data: (contact) {
                    final hasContact = contact['name'] != null && contact['name']!.isNotEmpty;
                    if (!hasContact) {
                      return Center(child: Text("Aucun contact d'urgence défini.", style: TextStyle(color: Colors.grey[600], fontFamily: 'Marianne')));
                    }
                    return ListView(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          leading: Container(width: 48, height: 48,
                            decoration: BoxDecoration(color: AppColors.navyDeep.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(CupertinoIcons.person_fill, color: AppColors.navyDeep)),
                          title: Text(contact['name'] ?? '', style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.navyDeep)),
                          subtitle: Text(contact['phone'] ?? '', style: TextStyle(fontFamily: 'Marianne', fontSize: 14, color: Colors.grey[600])),
                          trailing: IconButton(
                            icon: const Icon(CupertinoIcons.minus_circle_fill, color: Colors.red),
                            onPressed: () => _deleteContact('contact_1'),
                          ),
                        )
                      ],
                    );
                  },
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: GestureDetector(
                  onTap: () => setState(() => _isAdding = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.add_circled_solid, color: AppColors.blue),
                        const SizedBox(width: 8),
                        Text('profile.add_contact_btn'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, color: AppColors.blue, fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  filled: true, fillColor: Colors.grey[100],
                  hintText: 'profile.contact_name'.tr(),
                  prefixIcon: const Icon(CupertinoIcons.person_fill, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                       borderRadius: BorderRadius.circular(2),
                       child: SizedBox(
                         width: 22,
                         height: 16,
                         child: CountryFlag.fromCountryCode('CD'),
                       ),
                     ),
                          const SizedBox(width: 8),
                          const Text('+243', style: TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDeep)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 9, // Exactly 9 digits required
                        style: const TextStyle(fontFamily: 'Marianne', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0),
                        decoration: const InputDecoration(
                          hintText: '81 000 00 00',
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _addContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navyDeep, padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                ),
                child: Text('profile.save_btn'.tr(), style: TextStyle(fontFamily: 'Marianne', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => _isAdding = false),
                  child: Text('profile.cancel_btn'.tr(), style: TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. PHONE NUMBER & OTP SHEET
// ==========================================
class _PhoneEditSheet extends StatefulWidget {
  const _PhoneEditSheet();

  @override
  State<_PhoneEditSheet> createState() => _PhoneEditSheetState();
}

class _PhoneEditSheetState extends State<_PhoneEditSheet> {
  int _step = 1; // 1: Number, 2: OTP
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  Widget _buildStep1() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('profile.new_number'.tr(), style: TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
        const SizedBox(height: 8),
        Text('profile.sms_verification'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 15, fontFamily: 'Marianne')),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        width: 22, height: 16,
                        child: CountryFlag.fromCountryCode('CD'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('+243', style: TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDeep)),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 9, // Exactly 9 digits required
                  style: const TextStyle(fontFamily: 'Marianne', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0),
                  decoration: const InputDecoration(
                    hintText: '81 000 00 00',
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            if (_phoneCtrl.text.trim().length >= 9) {
              setState(() => _step = 2);
              Future.delayed(const Duration(milliseconds: 100), () => _otpFocusNode.requestFocus());
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
          ),
          child: Text('profile.send_code_btn'.tr(), style: TextStyle(fontFamily: 'Marianne', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('profile.glance_sms'.tr(), style: TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
        const SizedBox(height: 8),
        Text('Entrez le code à 4 chiffres envoyé au +243 ${_phoneCtrl.text}', style: TextStyle(color: Colors.grey[600], fontSize: 15, fontFamily: 'Marianne')),
        const SizedBox(height: 32),
        
        // Interactive OTP Input overlay
        GestureDetector(
          onTap: () => FocusScope.of(context).requestFocus(_otpFocusNode),
          child: SizedBox(
            height: 70,
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (index) {
                    final text = _otpCtrl.text;
                    final char = index < text.length ? text[index] : '';
                    final isCurrent = index == text.length;

                    return Container(
                      width: 60, height: 70,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isCurrent ? AppColors.blue : Colors.transparent, width: 2),
                      ),
                      child: Text(
                        char.isNotEmpty ? char : (isCurrent ? '|' : ''), 
                        style: TextStyle(fontSize: 24, color: isCurrent && char.isEmpty ? AppColors.blue : Colors.black, fontWeight: FontWeight.bold)
                      ),
                    );
                  }),
                ),
                Opacity(
                  opacity: 0.0,
                  child: TextField(
                    controller: _otpCtrl,
                    focusNode: _otpFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            if (_otpCtrl.text.length == 4) {
               Navigator.pop(context); // Simulate SUCCESS
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navyDeep, padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
          ),
          child: Text('profile.verify_btn'.tr(), style: TextStyle(fontFamily: 'Marianne', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _step = 1),
            child: Text('profile.edit_number'.tr(), style: TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            _step == 1 ? _buildStep1() : _buildStep2(),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. LANGUAGE SHEET
// ==========================================
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;
    final locales = [
      {'code': 'fr', 'name': 'Français'},
      {'code': 'en', 'name': 'Anglais'},
      {'code': 'sw', 'name': 'Swahili'},
      {'code': 'ln', 'name': 'Lingala'},
      {'code': 'kg', 'name': 'Kikongo'},
      {'code': 'lu', 'name': 'Tshiluba'},
    ];

    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 32),
            Text('profile.change_lang'.tr(), style: const TextStyle(fontFamily: 'Marianne', fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
            const SizedBox(height: 24),
            ...locales.map((l) {
              final isSelected = currentLocale.languageCode == l['code']!;
              return ListTile(
                title: Text(l['name']!, style: TextStyle(fontFamily: 'Marianne', fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? AppColors.blue : AppColors.navyDeep)),
                trailing: isSelected ? const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppColors.blue) : null,
                onTap: () async {
                  switch (l['code']) {
                    case 'en': await context.setLocale(const Locale('en', 'US')); break;
                    case 'sw': await context.setLocale(const Locale('sw', 'KE')); break;
                    case 'ln': await context.setLocale(const Locale('ln', 'CD')); break;
                    case 'kg': await context.setLocale(const Locale('kg', 'CD')); break;
                    case 'lu': await context.setLocale(const Locale('lu', 'CD')); break;
                    default: await context.setLocale(const Locale('fr', 'FR'));
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
