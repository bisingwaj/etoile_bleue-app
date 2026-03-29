abstract class CallRepository {
  /// Initialise le moteur Agora (sans pour autant rejoindre un canal)
  Future<void> initializeEngine();

  /// Demande les permissions et rejoint le canal
  Future<void> joinCall({
    required String channelId,
    required String role,
    required String uid, // Optionnel, Agora assigne 0 par défaut si non fourni
  });

  /// Quitte le canal proprement et libère les ressources
  Future<void> leaveCall();

  /// Sourdine/Désourdine le microphone
  Future<void> toggleAudio(bool isEnabled);

  /// Active/Désactive la caméra locale
  Future<void> toggleVideo(bool isEnabled);

  /// Active/Désactive le haut-parleur
  Future<void> toggleSpeaker(bool isEnabled);

  /// Bascule entre la caméra avant et arrière
  Future<void> switchCamera();

  /// Stream exposant l'état mis à jour de la session
  Stream<Map<String, dynamic>> get agoraEventsStream;
}
