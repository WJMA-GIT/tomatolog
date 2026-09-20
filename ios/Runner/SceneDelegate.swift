import Flutter
import UIKit

class TimerFlutterViewController: FlutterViewController {
  private var landscapeTimerActive = false

  override var prefersHomeIndicatorAutoHidden: Bool {
    landscapeTimerActive
  }

  func setLandscapeTimerActive(_ active: Bool) {
    landscapeTimerActive = active
    setNeedsUpdateOfHomeIndicatorAutoHidden()
  }
}

class SceneDelegate: FlutterSceneDelegate {

}
