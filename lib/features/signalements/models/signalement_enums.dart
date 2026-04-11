import 'package:easy_localization/easy_localization.dart';

/// Catégories de signalement — codes alignés sur le schéma Supabase §9.1
enum SignalementCategory {
  corruption('corruption'),
  detournementMedicaments('detournement_medicaments'),
  maltraitance('maltraitance'),
  surfacturation('surfacturation'),
  personnelFantome('personnel_fantome'),
  medicamentsPerimes('medicaments_perimes'),
  fauxDiplomes('faux_diplomes'),
  insalubrite('insalubrite'),
  violenceHarcelement('violence_harcelement'),
  discrimination('discrimination'),
  negligenceMedicale('negligence_medicale'),
  traficOrganes('trafic_organes'),
  racketUrgences('racket_urgences'),
  detournementAide('detournement_aide'),
  absenceInjustifiee('absence_injustifiee'),
  conditionsTravail('conditions_travail'),
  protocolesSanitaires('protocoles_sanitaires'),
  falsificationCertificats('falsification_certificats'),
  ruptureStock('rupture_stock'),
  exploitationStagiaires('exploitation_stagiaires'),
  abusSexuels('abus_sexuels'),
  obstructionEnquetes('obstruction_enquetes');

  const SignalementCategory(this.code);
  final String code;

  String get localizedLabel => 'signalement.cat_$code'.tr();

  static SignalementCategory fromCode(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => corruption);
}

/// Priorités — couleurs UI §9.3
enum SignalementPriority {
  critique('critique', 0xFFEF4444),
  haute('haute', 0xFFF59E0B),
  moyenne('moyenne', 0xFF3B82F6),
  basse('basse', 0xFF6B7280);

  const SignalementPriority(this.code, this.colorValue);
  final String code;
  final int colorValue;

  String get localizedLabel => 'signalement.priority_$code'.tr();

  static SignalementPriority fromCode(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => moyenne);
}

/// Statuts du workflow §9.2
enum SignalementStatus {
  nouveau('nouveau'),
  enCours('en_cours'),
  enquete('enquete'),
  resolu('resolu'),
  classe('classe'),
  transfere('transfere');

  const SignalementStatus(this.code);
  final String code;

  String get localizedLabel => 'signalement.status_$code'.tr();

  static SignalementStatus fromCode(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => nouveau);
}
