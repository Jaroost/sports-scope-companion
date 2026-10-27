import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Force Android à écrire les cookies du WebView sur disque.
///
/// Il ne le fait qu'avec retard : un processus tué juste après la connexion
/// (`flutter run`, appli balayée) perdait le cookie de session, alors que
/// `site_session.json` — écrit tout de suite — continuait d'annoncer « connecté ».
/// Ne lève jamais : une session perdue se refait, une exception ici ne rattrape rien.
Future<void> flushWebViewCookies() async {
  try {
    await const MethodChannel('sports_scope/cookies').invokeMethod<void>('flush');
  } catch (e) {
    debugPrint('[session] flush des cookies impossible : $e');
  }
}
