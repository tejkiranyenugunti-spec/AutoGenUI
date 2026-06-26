import 'camera_service_stub.dart'
    if (dart.library.html) 'camera_service_web.dart' as _impl;

/// Webcam access for Guardian HUD's "show me what's happening" vision flow.
///
/// Web-only in practice: the real implementation (in `camera_service_web.dart`)
/// drives `getUserMedia` and a `<video>` element rendered through a platform
/// view; the stub (selected on non-web targets) is a silent no-op so the rest
/// of the app compiles and runs everywhere. Callers should treat `start()`
/// returning `false` / `capture()` returning `null` as "camera unavailable".
abstract class CameraService {
  /// Requests camera access and starts the live stream. Returns true if the
  /// stream is live and a preview can be rendered.
  Future<bool> start();

  /// The platform-view type id to pass to `HtmlElementView` to render the live
  /// `<video>` preview. Stable for the life of this service instance.
  String get viewTypeId;

  /// Captures the current video frame as a JPEG data URL
  /// (`data:image/jpeg;base64,…`), or null if no frame is available.
  Future<String?> capture();

  /// Stops the stream (releases the camera) but keeps the service reusable.
  void stop();

  void dispose();

  /// True while a stream is live.
  bool get isActive;
}

/// Constructs the platform-appropriate [CameraService].
CameraService createCameraService() => _impl.createCameraServiceImpl();
