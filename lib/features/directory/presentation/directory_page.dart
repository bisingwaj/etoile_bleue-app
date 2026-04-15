import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

/// Clés stables pour filtrer les onglets (doivent correspondre à `directory.tab_<key>` dans les JSON).
const List<String> _tabCategoryKeys = [
  'hospitals',
  'centers',
  'dispensaries',
  'police',
  'rapid',
];

class Institution {
  /// Aligné sur [tab_hospitals], [tab_centers], etc. (sans préfixe `tab_`).
  final String categoryKey;
  /// Nom officiel tel qu’en base (non traduit).
  final String name;
  /// Clés `directory.*` pour type, adresse et spécialités.
  final String typeKey;
  final String addressKey;
  /// Spécialités séparées par `|` (chaîne unique traduite).
  final String specsKey;
  final double lat;
  final double lng;
  final String phone;
  final IconData icon;
  final Color color;
  final bool isAffiliated;

  double distanceInMeters = 0;

  Institution({
    required this.categoryKey,
    required this.name,
    required this.typeKey,
    required this.addressKey,
    required this.specsKey,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.icon,
    required this.color,
    this.isAffiliated = false,
  });

  String get _typeText => typeKey.tr();
  String get _addressText => addressKey.tr();

  List<String> get _specsList =>
      specsKey.tr().split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Texte agrégé pour recherche (nom brut + champs traduits).
  String get _searchBlob =>
      '${name.toLowerCase()} ${_typeText.toLowerCase()} ${_addressText.toLowerCase()} ${specsKey.tr().toLowerCase()}';
}

class DirectoryPage extends StatefulWidget {
  const DirectoryPage({super.key});

  @override
  DirectoryPageState createState() => DirectoryPageState();
}

class DirectoryPageState extends State<DirectoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoadingLocation = true;
  bool _hasLoadedGps = false;
  Position? _currentPosition;
  int _selectedDistanceFilter = 5;
  final List<int> _distanceOptions = [1, 5, 10, 20];

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Institution> _allInstitutions = [
    Institution(
      categoryKey: 'hospitals',
      name: 'Hôpital Général (Ex-Maman Yemo)',
      typeKey: 'directory.demo_maman_yemo_type',
      addressKey: 'directory.demo_maman_yemo_address',
      specsKey: 'directory.demo_maman_yemo_specs',
      lat: -4.310,
      lng: 15.315,
      phone: '112',
      icon: CupertinoIcons.building_2_fill,
      color: AppColors.blue,
      isAffiliated: true,
    ),
    Institution(
      categoryKey: 'centers',
      name: 'Centre Médical Diamant',
      typeKey: 'directory.demo_diamant_type',
      addressKey: 'directory.demo_diamant_address',
      specsKey: 'directory.demo_diamant_specs',
      lat: -4.312,
      lng: 15.310,
      phone: '112',
      icon: CupertinoIcons.heart_fill,
      color: AppColors.red,
      isAffiliated: true,
    ),
    Institution(
      categoryKey: 'police',
      name: 'Commissariat Provincial',
      typeKey: 'directory.demo_commissariat_gombe_type',
      addressKey: 'directory.demo_commissariat_gombe_address',
      specsKey: 'directory.demo_commissariat_gombe_specs',
      lat: -4.311,
      lng: 15.311,
      phone: '112',
      icon: CupertinoIcons.shield_fill,
      color: AppColors.navyDeep,
      isAffiliated: true,
    ),
    Institution(
      categoryKey: 'hospitals',
      name: 'Clinique Ngaliema',
      typeKey: 'directory.demo_ngaliema_type',
      addressKey: 'directory.demo_ngaliema_address',
      specsKey: 'directory.demo_ngaliema_specs',
      lat: -4.341,
      lng: 15.263,
      phone: '112',
      icon: CupertinoIcons.building_2_fill,
      color: AppColors.blue,
      isAffiliated: false,
    ),
    Institution(
      categoryKey: 'rapid',
      name: 'Croix-Rouge - Base Ngaliema',
      typeKey: 'directory.demo_croix_rouge_type',
      addressKey: 'directory.demo_croix_rouge_address',
      specsKey: 'directory.demo_croix_rouge_specs',
      lat: -4.345,
      lng: 15.260,
      phone: '112',
      icon: CupertinoIcons.heart_circle_fill,
      color: AppColors.red,
      isAffiliated: true,
    ),
    Institution(
      categoryKey: 'hospitals',
      name: 'HJ Hospitals',
      typeKey: 'directory.demo_hj_hospitals_type',
      addressKey: 'directory.demo_hj_hospitals_address',
      specsKey: 'directory.demo_hj_hospitals_specs',
      lat: -4.375,
      lng: 15.334,
      phone: '112',
      icon: CupertinoIcons.building_2_fill,
      color: AppColors.blue,
      isAffiliated: false,
    ),
    Institution(
      categoryKey: 'dispensaries',
      name: 'Centre de Santé Limete',
      typeKey: 'directory.demo_limete_css_type',
      addressKey: 'directory.demo_limete_css_address',
      specsKey: 'directory.demo_limete_css_specs',
      lat: -4.372,
      lng: 15.330,
      phone: '112',
      icon: CupertinoIcons.bandage_fill,
      color: Colors.green,
      isAffiliated: true,
    ),
    Institution(
      categoryKey: 'hospitals',
      name: 'Hôpital du Cinquantenaire',
      typeKey: 'directory.demo_hosp_cinq_type',
      addressKey: 'directory.demo_hosp_cinq_address',
      specsKey: 'directory.demo_hosp_cinq_specs',
      lat: -4.340,
      lng: 15.300,
      phone: '112',
      icon: CupertinoIcons.building_2_fill,
      color: AppColors.blue,
      isAffiliated: false,
    ),
    Institution(
      categoryKey: 'police',
      name: 'Sous-Commissariat Kalamu',
      typeKey: 'directory.demo_kalamu_police_type',
      addressKey: 'directory.demo_kalamu_police_address',
      specsKey: 'directory.demo_kalamu_police_specs',
      lat: -4.348,
      lng: 15.316,
      phone: '112',
      icon: CupertinoIcons.shield_fill,
      color: AppColors.navyDeep,
      isAffiliated: false,
    ),
  ];

  List<Institution> _filteredInstitutions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCategoryKeys.length, vsync: this);
    _currentPosition = Position(
      latitude: -4.316,
      longitude: 15.311,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _isLoadingLocation = false;
    _filterAndSortInstitutions();
  }

  void refreshLocation() {
    if (_hasLoadedGps) return;
    _hasLoadedGps = true;
    _getUserLocationAndFilter();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getUserLocationAndFilter() async {
    setState(() => _isLoadingLocation = true);

    final prefs = await SharedPreferences.getInstance();
    final bool hasCache = prefs.getBool('has_directory_cache') ?? false;
    if (!hasCache) {
      debugPrint("First load: caching directory...");
      await prefs.setBool('has_directory_cache', true);
    } else {
      debugPrint("Loaded from local cache instantly!");
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions denied.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied.');
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(accuracy: LocationAccuracy.high, forceLocationManager: true)
            : const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      debugPrint('Geolocation error: $e');
      _currentPosition = Position(
        latitude: -4.316,
        longitude: 15.311,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }

    _filterAndSortInstitutions();
  }

  void _filterAndSortInstitutions() {
    if (_currentPosition == null) return;

    List<Institution> withinRadius = [];

    for (var inst in _allInstitutions) {
      double distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        inst.lat,
        inst.lng,
      );

      inst.distanceInMeters = distance;

      if (distance <= (_selectedDistanceFilter * 1000)) {
        withinRadius.add(inst);
      }
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      withinRadius = withinRadius.where((inst) {
        return inst._searchBlob.contains(q);
      }).toList();
    }

    withinRadius.sort((a, b) {
      if (a.isAffiliated && !b.isAffiliated) return -1;
      if (!a.isAffiliated && b.isAffiliated) return 1;
      return a.distanceInMeters.compareTo(b.distanceInMeters);
    });

    setState(() {
      _filteredInstitutions = withinRadius;
      _isLoadingLocation = false;
    });
  }

  Future<void> _openGoogleMaps(String query) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatDistance(Institution inst) {
    if (inst.distanceInMeters < 1000) {
      return 'directory.distance_m'.tr(namedArgs: {
        'value': inst.distanceInMeters.toStringAsFixed(0),
      });
    }
    return 'directory.distance_km'.tr(namedArgs: {
      'value': (inst.distanceInMeters / 1000).toStringAsFixed(1),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 110,
        title: Padding(
          padding: const EdgeInsets.only(top: 20.0),
          child: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 18, color: AppColors.navyDeep),
                  decoration: InputDecoration(
                    hintText: 'directory.search_placeholder'.tr(),
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey[400]),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _filterAndSortInstitutions();
                    });
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'directory.title'.tr(),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Marianne',
                        color: AppColors.navyDeep,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _distanceOptions.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final distanceKm = _distanceOptions[index];
                          final isSelected = _selectedDistanceFilter == distanceKm;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDistanceFilter = distanceKm;
                                _filterAndSortInstitutions();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.blue : Colors.grey[200],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isSelected ? AppColors.blue : Colors.transparent),
                              ),
                              child: Text(
                                'directory.distance_radius_km'.tr(namedArgs: {
                                  'km': '$distanceKm',
                                }),
                                style: TextStyle(
                                  fontFamily: 'Marianne',
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _searchQuery = '';
                    _filterAndSortInstitutions();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isSearching ? AppColors.blue.withValues(alpha: 0.1) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: Icon(_isSearching ? CupertinoIcons.xmark : CupertinoIcons.search, size: 22, color: _isSearching ? AppColors.blue : Colors.black87),
              ),
            ),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[600],
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: AppColors.blue,
                boxShadow: [
                  BoxShadow(color: AppColors.blue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: const EdgeInsets.symmetric(horizontal: 20),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Marianne'),
              tabs: _tabCategoryKeys
                  .map((k) => Tab(text: 'directory.tab_$k'.tr()))
                  .toList(),
            ),
          ),
        ),
      ),
      body: _isLoadingLocation
          ? const Center(child: CupertinoActivityIndicator())
          : TabBarView(
              controller: _tabController,
              children: _tabCategoryKeys.map(_buildListForCategory).toList(),
            ),
    );
  }

  Widget _buildListForCategory(String categoryKey) {
    final list = _filteredInstitutions.where((i) => i.categoryKey == categoryKey).toList();

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.location_slash_fill, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'directory.no_results'.tr()
                  : 'directory.no_structures'.tr(),
              style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _openGoogleMaps(_searchQuery),
                icon: const Icon(CupertinoIcons.map_fill, size: 18),
                label: Text("directory.search_hint".tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
              ),
            ]
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return _buildInstitutionCard(inst: list[index]);
      },
    );
  }

  Widget _buildInstitutionCard({required Institution inst}) {
    final formattedDistance = _formatDistance(inst);
    final typeDisplay = inst._typeText;
    final addressDisplay = inst._addressText;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: inst.isAffiliated ? Border.all(color: AppColors.blue.withOpacity(0.3), width: 2) : Border.all(color: Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inst.isAffiliated)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.star_fill, size: 12, color: AppColors.blue),
                  const SizedBox(width: 4),
                  Text('directory.partner_badge'.tr(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.blue, letterSpacing: 1.0)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: inst.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(inst.icon, color: inst.color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              inst.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.location_fill, size: 10, color: Colors.grey[700]),
                                const SizedBox(width: 4),
                                Text(formattedDistance, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(typeDisplay, style: TextStyle(color: inst.color, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(CupertinoIcons.map_pin_ellipse, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(addressDisplay, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: inst._specsList
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border.all(color: Colors.grey[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s, style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[100]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20))),
                    ),
                    onPressed: () => _callNumber(inst.phone),
                    icon: const Icon(CupertinoIcons.phone_fill, color: Colors.black87, size: 18),
                    label: Text('directory.call'.tr(), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                  ),
                ),
                Container(width: 1, height: 30, color: Colors.grey[200]),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomRight: Radius.circular(20))),
                    ),
                    onPressed: () => _openGoogleMaps(inst.name),
                    icon: const Icon(CupertinoIcons.map_fill, color: AppColors.blue, size: 18),
                    label: Text('directory.route'.tr(), style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
