import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/features/directory/data/health_structures_repository.dart';

/// Types `health_structures.type` côté API (voir PATIENT_APP_STRUCTURES_PROXIMITY.md).
const List<String> _tabCategoryKeys = [
  'hopital',
  'centre_sante',
  'maternite',
  'pharmacie',
  'police',
  'pompier',
];

String _tabTranslationKey(String categoryKey) {
  return switch (categoryKey) {
    'hopital' => 'directory.tab_hospitals',
    'centre_sante' => 'directory.tab_centers',
    'maternite' => 'directory.tab_maternite',
    'pharmacie' => 'directory.tab_pharmacies',
    'police' => 'directory.tab_police',
    'pompier' => 'directory.tab_fire',
    _ => 'directory.tab_hospitals',
  };
}

String _categoryKeyFromApiType(String? type) {
  return switch (type) {
    'hopital' => 'hopital',
    'centre_sante' => 'centre_sante',
    'pharmacie' => 'pharmacie',
    'police' => 'police',
    'maternite' => 'maternite',
    'pompier' => 'pompier',
    _ => 'centre_sante',
  };
}

(IconData, Color) _iconAndColorForCategory(String categoryKey) {
  return switch (categoryKey) {
    'hopital' => (CupertinoIcons.building_2_fill, AppColors.blue),
    'centre_sante' => (CupertinoIcons.heart_fill, AppColors.red),
    'maternite' => (CupertinoIcons.person_2_fill, Colors.pink),
    'pharmacie' => (CupertinoIcons.capsule_fill, Colors.teal),
    'police' => (CupertinoIcons.shield_fill, AppColors.navyDeep),
    'pompier' => (CupertinoIcons.flame_fill, Colors.deepOrange),
    _ => (CupertinoIcons.building_2_fill, AppColors.blue),
  };
}

class Institution {
  final String id;
  final String categoryKey;
  final String name;
  final String rawType;
  final String address;
  final List<String> specs;
  final double? lat;
  final double? lng;
  final String phone;
  final IconData icon;
  final Color color;
  final bool isAffiliated;

  double distanceInMeters = 0;

  Institution({
    required this.id,
    required this.categoryKey,
    required this.name,
    required this.rawType,
    required this.address,
    required this.specs,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.icon,
    required this.color,
    required this.isAffiliated,
  });

  bool get hasValidCoords => lat != null && lng != null;

  String get _typeLabel {
    final key = 'directory.structure_type_$rawType';
    final t = key.tr();
    if (t == key) return rawType;
    return t;
  }

  String get _searchBlob =>
      '${name.toLowerCase()} ${address.toLowerCase()} ${rawType.toLowerCase()} ${specs.join(' ').toLowerCase()}';

  factory Institution.fromApiRow(Map<String, dynamic> row) {
    final rawType = (row['type'] as String?) ?? 'centre_sante';
    final cat = _categoryKeyFromApiType(rawType);
    final (icon, color) = _iconAndColorForCategory(cat);

    final specsRaw = row['specialties'];
    final specs = <String>[];
    if (specsRaw is List) {
      for (final e in specsRaw) {
        if (e != null && e.toString().trim().isNotEmpty) {
          specs.add(e.toString());
        }
      }
    }

    final n = (row['name'] as String?)?.trim();
    final official = (row['official_name'] as String?)?.trim();
    final displayName = (n != null && n.isNotEmpty) ? n : (official ?? '');

    final lat = _parseDouble(row['lat']);
    final lng = _parseDouble(row['lng']);
    final phone = (row['phone'] as String?)?.trim() ?? '';

    final linked = row['linked_user_id'];
    final isAffiliated = linked != null;

    return Institution(
      id: '${row['id'] ?? ''}',
      categoryKey: cat,
      name: displayName.isEmpty ? '—' : displayName,
      rawType: rawType,
      address: (row['address'] as String?)?.trim() ?? '',
      specs: specs,
      lat: lat,
      lng: lng,
      phone: phone,
      icon: icon,
      color: color,
      isAffiliated: isAffiliated,
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class DirectoryPage extends StatefulWidget {
  const DirectoryPage({super.key});

  @override
  DirectoryPageState createState() => DirectoryPageState();
}

class DirectoryPageState extends State<DirectoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoadingLocation = true;
  Position? _currentPosition;
  int _selectedDistanceFilter = 5;
  final List<int> _distanceOptions = [1, 5, 10, 20];

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final HealthStructuresRepository _structuresRepo = HealthStructuresRepository();

  List<Institution> _allInstitutions = [];
  List<Institution> _filteredInstitutions = [];
  String? _structuresError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCategoryKeys.length, vsync: this);
    _loadInitialData();
  }

  /// Ne relance pas le chargement Supabase ; met seulement à jour le GPS (voir [PATIENT_APP_STRUCTURES_PROXIMITY.md]).
  void refreshLocation() {
    Future.microtask(() async {
      if (!mounted || _allInstitutions.isEmpty) return;
      await _refreshGpsAndRecalculateDistances();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingLocation = true;
      _structuresError = null;
    });

    try {
      final posFuture = _obtainPosition();
      final rowsFuture = _structuresRepo.fetchAllOpenStructures();
      final out = await Future.wait([posFuture, rowsFuture]);
      final pos = out[0] as Position;
      final rows = out[1] as List<Map<String, dynamic>>;

      _currentPosition = pos;
      _structuresRepo.sortByProximity(rows, userLat: pos.latitude, userLng: pos.longitude);

      _allInstitutions = rows.map(Institution.fromApiRow).toList();
      _applyDistancesFromPosition(pos);
      _filterAndSortInstitutions();
    } catch (e, st) {
      debugPrint('Directory load error: $e\n$st');
      setState(() {
        _structuresError = e.toString();
        _allInstitutions = [];
        _filteredInstitutions = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  /// Met à jour le GPS sans relancer la récupération des structures (filtre km inchangé côté API).
  Future<void> _refreshGpsAndRecalculateDistances() async {
    if (_allInstitutions.isEmpty) return;
    setState(() => _isLoadingLocation = true);
    try {
      final pos = await _obtainPosition();
      _currentPosition = pos;
      _applyDistancesFromPosition(pos);
      _filterAndSortInstitutions();
    } catch (e) {
      debugPrint('Directory GPS refresh: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<Position> _obtainPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled.');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied.');
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(accuracy: LocationAccuracy.high, forceLocationManager: true)
            : const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      debugPrint('Geolocation fallback: $e');
      return Position(
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
  }

  void _applyDistancesFromPosition(Position pos) {
    for (final inst in _allInstitutions) {
      if (inst.hasValidCoords) {
        inst.distanceInMeters = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          inst.lat!,
          inst.lng!,
        );
      } else {
        inst.distanceInMeters = double.infinity;
      }
    }
  }

  void _filterAndSortInstitutions() {
    if (_currentPosition == null) return;

    final radiusM = _selectedDistanceFilter * 1000.0;

    final withCoordsInRadius = <Institution>[];
    final withoutCoords = <Institution>[];

    for (final inst in _allInstitutions) {
      if (inst.hasValidCoords) {
        if (inst.distanceInMeters <= radiusM) {
          withCoordsInRadius.add(inst);
        }
      } else {
        withoutCoords.add(inst);
      }
    }

    var combined = [...withCoordsInRadius, ...withoutCoords];

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      combined = combined.where((inst) => inst._searchBlob.contains(q)).toList();
    }

    combined.sort((a, b) {
      if (a.hasValidCoords && !b.hasValidCoords) return -1;
      if (!a.hasValidCoords && b.hasValidCoords) return 1;
      if (!a.hasValidCoords && !b.hasValidCoords) return a.name.compareTo(b.name);
      return a.distanceInMeters.compareTo(b.distanceInMeters);
    });

    setState(() {
      _filteredInstitutions = combined;
    });
  }

  Future<void> _openGoogleMaps(String query) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _callNumber(String number) async {
    if (number.trim().isEmpty) return;
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatDistance(Institution inst) {
    if (!inst.hasValidCoords) {
      return 'directory.distance_unknown'.tr();
    }
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
    if (_structuresError != null && _allInstitutions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text('directory.title'.tr(), style: const TextStyle(color: AppColors.navyDeep)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.exclamationmark_triangle, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'directory.load_structures_error'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loadInitialData,
                  child: Text('directory.retry'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                  BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: const EdgeInsets.symmetric(horizontal: 20),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Marianne'),
              tabs: _tabCategoryKeys.map((k) => Tab(text: _tabTranslationKey(k).tr())).toList(),
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
              _searchQuery.isNotEmpty ? 'directory.no_results'.tr() : 'directory.no_structures'.tr(),
              style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _openGoogleMaps(_searchQuery),
                icon: const Icon(CupertinoIcons.map_fill, size: 18),
                label: Text('directory.search_hint'.tr()),
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
    final typeDisplay = inst._typeLabel;
    final addressDisplay = inst.address.isEmpty ? '—' : inst.address;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: inst.isAffiliated ? Border.all(color: AppColors.blue.withValues(alpha: 0.3), width: 2) : Border.all(color: Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
                color: AppColors.blue.withValues(alpha: 0.1),
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
                    color: inst.color.withValues(alpha: 0.1),
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
          if (inst.specs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: inst.specs
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
          if (inst.specs.isNotEmpty) const SizedBox(height: 20),
          if (inst.specs.isEmpty) const SizedBox(height: 8),
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
                    onPressed: inst.phone.trim().isEmpty ? null : () => _callNumber(inst.phone),
                    icon: Icon(CupertinoIcons.phone_fill, color: inst.phone.trim().isEmpty ? Colors.grey : Colors.black87, size: 18),
                    label: Text(
                      'directory.call'.tr(),
                      style: TextStyle(color: inst.phone.trim().isEmpty ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold),
                    ),
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
