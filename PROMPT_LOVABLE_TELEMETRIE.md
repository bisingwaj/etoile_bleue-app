**Sujet : Mise à jour de la table "incidents" et du Dashboard (Lovable)**

Bonjour Lovable,

L'application mobile a été mise à jour avec de nouvelles fonctionnalités de suivi et d'optimisation. Afin que le Backend et le Dashboard Call Center soient parfaitement synchronisés avec ces nouveautés, voici les tâches à réaliser :

### 1. Mise à jour de la base de données (Supabase)
Veuillez ajouter les colonnes suivantes à la table `incidents` :
- `device_model` (texte) : Permet de stocker le modèle du téléphone du citoyen (ex: TECNO Spark 10).
- `battery_level` (texte) : Permet de stocker le niveau de batterie au moment de l'appel (ex: 85%).
- `network_state` (texte) : Permet de stocker la qualité du réseau au moment de l'appel (ex: Wi-Fi, Cellulaire, Faible).
- `recommended_actions` (texte, nullable) : Texte libre saisi par le dispatcher pour conseiller le patient en temps réel (ex: "Allongez le patient en PLS").
- `recommended_facility` (texte, nullable) : Nom de l'établissement de santé vers lequel l'unité ou le patient est orienté (ex: "Hôpital du Cinquantenaire").

### 2. Mise à jour du Dashboard (Call Center)
Dans l'interface détaillée d'un incident en cours :
- **Panneau "Télémétrie" (Lecture seule)** : Affichez dans un encart clair les valeurs de `device_model`, `battery_level`, et `network_state` transmises par le téléphone du citoyen. Si la batterie est très faible (< 15%), affichez une alerte visuelle pour que le régulateur ne perde pas de temps.
- **Formulaire de Recommandations (Édition)** : Ajoutez deux nouveaux champs de saisie pour l'agent (Dispatcher) :
    1. Un champ texte "Actions Recommandées" (relié à `recommended_actions`).
    2. Un champ texte ou liste déroulante "Structure de Santé Orientée" (relié à `recommended_facility`).
- Dès que le dispatcher met à jour ces champs, la base de données doit être mise à jour (`UPDATE`). L'application mobile est déjà configurée pour écouter ces champs en temps réel via Supabase et les affichera instantanément sur l'écran "Suivi SOS" du patient.

Merci de déployer ces changements pour assurer la continuité de service avec l'application mobile.