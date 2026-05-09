abstract class FaceScanState {
  const FaceScanState();
}

class FaceScanInitializing extends FaceScanState {}

class FaceScanScanning extends FaceScanState {}

class FaceScanBlinking extends FaceScanState {
  final int count;
  const FaceScanBlinking(this.count);
}

class FaceScanCapturing extends FaceScanState {}

class FaceScanVerifying extends FaceScanState {}

class FaceScanSuccess extends FaceScanState {
  final String markedAt;
  const FaceScanSuccess(this.markedAt);
}

class FaceScanFailed extends FaceScanState {
  final String reason;
  const FaceScanFailed(this.reason);
}
