/// Re-exports the face scan screen from the face_scan feature module.
///
/// This file exists for backward compatibility with the router
/// which previously imported FaceScanScreen from this location.
/// The canonical implementation is now in features/face_scan/.
library;

export '../face_scan/face_scan_screen.dart';
