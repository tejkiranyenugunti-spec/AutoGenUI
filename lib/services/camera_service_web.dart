import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'camera_service.dart';

/// Web implementation of [CameraService] using `getUserMedia` + a `<video>`
/// element rendered into Flutter via a platform view (`HtmlElementView`).
///
/// The platform-view factory is registered once (per instance) against a
/// container `<div>`; on [start] a `<video>` is created and appended to that
/// div so the live preview shows wherever `HtmlElementView(viewType:)` is
/// placed. [capture] draws the current frame to a canvas and returns a JPEG
/// data URL ready to send to a vision model.
class WebCameraService implements CameraService {
  WebCameraService() {
    _viewTypeId = 'guardian-camera-${identityHashCode(this)}';
    _container = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#000';
    // Register once; the factory always returns the same container, and we
    // add/remove the <video> child as the stream starts/stops.
    ui_web.platformViewRegistry.registerViewFactory(
      _viewTypeId,
      (int _) => _container!,
    );
  }

  late final String _viewTypeId;
  late final html.DivElement _container;
  html.MediaStream? _stream;
  html.VideoElement? _video;
  bool _active = false;

  @override
  String get viewTypeId => _viewTypeId;

  @override
  bool get isActive => _active;

  @override
  Future<bool> start() async {
    if (_active) return true;
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) return false;
      _stream = await mediaDevices.getUserMedia({'video': true, 'audio': false});

      final video = html.VideoElement()
        ..autoplay = true
        ..muted = true // autoplay requires muted
        ..setAttribute('playsinline', '')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';
      try {
        video.srcObject = _stream;
      } catch (_) {
        // Older browsers: fall back to an object URL.
        video.src = html.Url.createObjectUrlFromStream(_stream!);
      }
      await video.play().catchError((_) {});

      _video = video;
      _container.children.clear();
      _container.append(video);
      _active = true;
      return true;
    } catch (e) {
      _active = false;
      return false;
    }
  }

  @override
  Future<String?> capture() async {
    final video = _video;
    if (video == null || !_active) return null;
    try {
      final vw = video.videoWidth;
      final vh = video.videoHeight;
      if (vw == 0 || vh == 0) return null;
      final canvas = html.CanvasElement(width: vw, height: vh);
      canvas.context2D.drawImage(video, 0, 0);
      return canvas.toDataUrl('image/jpeg', 0.6);
    } catch (_) {
      return null;
    }
  }

  @override
  void stop() {
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    _video?.remove();
    _video = null;
    _active = false;
  }

  @override
  void dispose() => stop();
}

CameraService createCameraServiceImpl() => WebCameraService();
