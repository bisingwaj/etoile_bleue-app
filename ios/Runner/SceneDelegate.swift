import Flutter
import UIKit
import FirebaseAuth

class SceneDelegate: FlutterSceneDelegate {
  /// Phone Auth (reCAPTCHA) revient par URL ; avec UIScene il faut forwarder ici aussi.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      _ = Auth.auth().canHandle(context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
