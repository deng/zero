import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Capture the URL that launched the scene (if any).
    if let urlContext = connectionOptions.urlContexts.first {
      (UIApplication.shared.delegate as? AppDelegate)?.handleURL(urlContext.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
      (UIApplication.shared.delegate as? AppDelegate)?.handleURL(context.url)
    }
  }
}