import 'camera_service.dart';

/// Non-web stub: camera is unavailable. Keeps the app compilable and runnable
/// on targets where `getUserMedia` doesn't exist.
class _StubCameraService implements CameraService {
  @override
  Future<bool> start() async => false;

  @override
  String get viewTypeId => 'guardian-camera-stub';

  @override
  Future<String?> capture() async => null;

  @override
  void stop() {}

  @override
  void dispose() {}

  @override
  bool get isActive => false;
}

CameraService createCameraServiceImpl() => _StubCameraService();
