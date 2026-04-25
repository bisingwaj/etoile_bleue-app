import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:easy_localization/easy_localization.dart';

class ErrorUtils {
  /// Mappe une erreur Agora RTC vers une clé de traduction conviviale.
  static String getAgoraErrorMessage(dynamic error) {
    if (error is int) {
      return _mapErrorCodeToKey(error).tr();
    }
    if (error is AgoraRtcException) {
      return _mapErrorCodeToKey(error.code).tr();
    }
    
    final errorStr = error.toString().toUpperCase();
    
    // Si c'est une ErrorCodeType (enum), on essaie de mapper via son nom
    if (error.runtimeType.toString().contains('ErrorCodeType')) {
      if (errorStr.contains('INVALIDAPPID')) return 'errors.agora_service_unavailable'.tr();
      if (errorStr.contains('INVALIDTOKEN')) return 'errors.agora_invalid_token'.tr();
      if (errorStr.contains('TOKENEXPIRED')) return 'errors.agora_token_expired'.tr();
      if (errorStr.contains('INVALIDCHANNELNAME')) return 'errors.agora_invalid_params'.tr();
      if (errorStr.contains('JOINCHANNELREJECTED')) return 'errors.agora_uid_conflict'.tr();
      if (errorStr.contains('BANNED')) return 'errors.agora_banned'.tr();
    }
    
    if (errorStr.contains('PERMISSION_DENIED') || errorStr.contains('NOTALLOWEDERROR')) {
      return 'errors.agora_mic_denied'.tr();
    }
    if (errorStr.contains('DEVICE_NOT_FOUND') || errorStr.contains('NOTFOUNDERROR')) {
      return 'errors.agora_mic_not_found'.tr();
    }
    if (errorStr.contains('NOT_READABLE') || errorStr.contains('NOTREADABLEERROR')) {
      return 'errors.agora_mic_occupied'.tr();
    }
    if (errorStr.contains('NETWORK_ERROR') || errorStr.contains('CAN_NOT_GET_GATEWAY_SERVER') || errorStr.contains('TIMEOUT')) {
      return 'errors.agora_service_unavailable'.tr();
    }
    if (errorStr.contains('WS_') || errorStr.contains('ABORT') || errorStr.contains('FAILED')) {
      return 'errors.agora_service_unavailable'.tr();
    }
    if (errorStr.contains('UID_CONFLICT')) {
      return 'errors.agora_uid_conflict'.tr();
    }
    if (errorStr.contains('BANNED')) {
      return 'errors.agora_banned'.tr();
    }

    return 'errors.agora_service_unavailable'.tr();
  }

  static String _mapErrorCodeToKey(int code) {
    switch (code) {
      case 101: // errInvalidAppId
        return 'errors.agora_service_unavailable';
      case 110: // errInvalidToken
        return 'errors.agora_invalid_token';
      case 109: // errTokenExpired
        return 'errors.agora_token_expired';
      case 102: // errInvalidChannelName
        return 'errors.agora_invalid_params';
      case 2:   // errInvalidParams (sometimes errInvalidArgument)
        return 'errors.agora_invalid_params';
      case 17:  // errJoinChannelRejected
        return 'errors.agora_uid_conflict';
      case 5:   // errRefused
        return 'errors.agora_service_unavailable';
      case 119: // errClientIsBannedByServer
        return 'errors.agora_banned';
      default:
        return 'errors.agora_service_unavailable';
    }
  }

  /// Nettoie un message d'exception générique pour l'utilisateur.
  static String getFriendlyErrorMessage(dynamic e) {
    final errorStr = e.toString();
    
    if (errorStr.contains('CANCELED_BY_USER')) {
      return ''; // Devra être ignoré par l'appelant
    }
    
    if (errorStr.contains('AgoraRtcException') || errorStr.contains('code:')) {
      return getAgoraErrorMessage(e);
    }
    
    // Nettoyage du préfixe technique "Exception: "
    return errorStr.replaceAll('Exception: ', '');
  }
}
