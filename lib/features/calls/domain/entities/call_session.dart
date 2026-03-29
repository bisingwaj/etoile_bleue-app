import 'package:freezed_annotation/freezed_annotation.dart';

part 'call_session.freezed.dart';

/// Représente l'état précis de la connexion de l'appel
enum CallStatus {
  idle,                 // Repos, aucun appel en cours
  requestingPermissions,// Demande d'accès caméra/micro
  connecting,           // Génération token + joinChannel en cours
  ringing,              // Connecté au canal, on attend l'autre participant
  active,               // Les deux participants sont là, flux établis
  reconnecting,         // Perte de paquet/réseau, Agora tente de reconnecter
  error,                // Échec (permissions, token invalide, réseau KO)
  ended                 // Appel terminé avec succès
}

/// Entité immuable représentant la session d'appel en cours
@freezed
abstract class CallSession with _$CallSession {
  const CallSession._();

  const factory CallSession({
    required CallStatus status,
    required String channelId,
    required String role, // 'Citizen', 'Rescuer', 'Dispatcher'
    required bool isVideoEnabled,
    required bool isAudioEnabled,
    required bool isSpeakerEnabled,
    required bool isFrontCamera,
    int? localUid,
    int? remoteUid,
    String? errorMessage,
  }) = _CallSession;

  factory CallSession.initial({
    required String channelId,
    required String role,
  }) => CallSession(
    status: CallStatus.idle,
    channelId: channelId,
    role: role,
    isVideoEnabled: false, // Default to audio-only for emergency
    isAudioEnabled: true,
    isSpeakerEnabled: true, // Auto-speaker on for emergencies (hands-free)
    isFrontCamera: true,
  );
}
