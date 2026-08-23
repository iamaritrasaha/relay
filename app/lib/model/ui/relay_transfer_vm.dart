import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// User-facing presentation of a file transfer.
///
/// Deliberately free of protocol vocabulary: a person sending a photo should
/// never read the words KDE, Iroh, QUIC, WAN or LAN. The remote size limit in
/// particular is phrased as an instruction they can act on rather than as an
/// error, because nothing went wrong — the file simply needs a local network.
class RelayTransferVm {
  final RsTransfer transfer;

  const RelayTransferVm(this.transfer);

  String get filename => transfer.filename;

  bool get isTerminal => const {
    'completed',
    'failed',
    'cancelled',
    'requiresLocalConnection',
  }.contains(transfer.state);

  /// True when the file could not be sent remotely because of its size.
  bool get requiresLocalConnection => transfer.state == 'requiresLocalConnection';

  /// Headline line, e.g. "Sending photo.jpg".
  String get title => switch (transfer.state) {
    'preparing' => 'Preparing ${transfer.filename}',
    'sending' => 'Sending ${transfer.filename}',
    'receiving' => 'Receiving ${transfer.filename}',
    'completed' => 'Sent ${transfer.filename}',
    'cancelled' => 'Cancelled ${transfer.filename}',
    'requiresLocalConnection' => 'Local connection required',
    _ => 'Could not send ${transfer.filename}',
  };

  /// Secondary line: byte progress, or an explanation for a terminal state.
  String get detail => switch (transfer.state) {
    'sending' || 'receiving' =>
      '${formatBytes(transfer.transferredBytes)} / ${formatBytes(transfer.totalBytes)}',
    'completed' => formatBytes(transfer.totalBytes),
    'requiresLocalConnection' =>
      'This file is larger than 20 MB. Connect both devices to the same local '
          'network to send it.',
    'failed' => transfer.error ?? 'The transfer did not finish.',
    'cancelled' => 'Stopped before finishing.',
    _ => '',
  };

  double get progress => transfer.progress;
}

/// Formats a byte count the way a person reads it.
///
/// Uses MB/GB rather than MiB/GiB: the limit is documented to users as "20 MB",
/// and mixing units in the same sentence would be worse than the small
/// imprecision.
String formatBytes(BigInt bytes) {
  final value = bytes.toDouble();
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (value >= gb) return '${(value / gb).toStringAsFixed(1)} GB';
  if (value >= mb) return '${(value / mb).toStringAsFixed(1)} MB';
  if (value >= kb) return '${(value / kb).toStringAsFixed(1)} KB';
  return '${value.toInt()} B';
}
