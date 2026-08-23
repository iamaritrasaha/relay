import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/model/ui/relay_transfer_vm.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// What the user reads matters as much as what the transport does — especially
/// for the size limit, which is a policy outcome and must never be presented as
/// a network failure.
void main() {
  RsTransfer transfer({
    String state = 'sending',
    int transferred = 0,
    int total = 100,
    String? error,
    double progress = 0.0,
  }) => RsTransfer(
    deviceId: 'device-a',
    transferId: 't1',
    filename: 'photo.jpg',
    totalBytes: BigInt.from(total),
    transferredBytes: BigInt.from(transferred),
    state: state,
    progress: progress,
    error: error,
  );

  test('an oversized remote file reads as an instruction, not an error', () {
    final vm = RelayTransferVm(transfer(state: 'requiresLocalConnection'));

    expect(vm.title, 'Local connection required');
    expect(vm.detail, contains('larger than 20 MB'));
    expect(vm.detail, contains('same local network'));
    expect(vm.requiresLocalConnection, isTrue);
    // Never phrased as a failure.
    expect(vm.detail.toLowerCase(), isNot(contains('error')));
    expect(vm.detail.toLowerCase(), isNot(contains('failed')));
  });

  test('no protocol vocabulary ever reaches the user', () {
    for (final state in [
      'preparing',
      'sending',
      'receiving',
      'completed',
      'failed',
      'cancelled',
      'requiresLocalConnection',
    ]) {
      final vm = RelayTransferVm(transfer(state: state));
      final text = '${vm.title} ${vm.detail}'.toLowerCase();
      for (final banned in ['kde', 'iroh', 'quic', 'wan', 'lan', 'payload', 'endpoint']) {
        expect(text, isNot(contains(banned)), reason: '"$banned" leaked in state $state');
      }
    }
  });

  test('progress is shown as bytes transferred against the total', () {
    final vm = RelayTransferVm(
      transfer(state: 'sending', transferred: 8400000, total: 14200000),
    );
    expect(vm.title, 'Sending photo.jpg');
    expect(vm.detail, '8.0 MB / 13.5 MB');
  });

  test('byte formatting picks a readable unit', () {
    expect(formatBytes(BigInt.from(512)), '512 B');
    expect(formatBytes(BigInt.from(2048)), '2.0 KB');
    expect(formatBytes(BigInt.from(5 * 1024 * 1024)), '5.0 MB');
    expect(formatBytes(BigInt.from(3 * 1024 * 1024 * 1024)), '3.0 GB');
    expect(formatBytes(BigInt.zero), '0 B');
  });

  test('terminal states are recognised so the UI can stop animating', () {
    expect(RelayTransferVm(transfer(state: 'sending')).isTerminal, isFalse);
    expect(RelayTransferVm(transfer(state: 'preparing')).isTerminal, isFalse);
    for (final state in ['completed', 'failed', 'cancelled', 'requiresLocalConnection']) {
      expect(RelayTransferVm(transfer(state: state)).isTerminal, isTrue, reason: state);
    }
  });

  test('a failure surfaces its reason when there is one', () {
    final vm = RelayTransferVm(transfer(state: 'failed', error: 'the transfer ended early'));
    expect(vm.title, 'Could not send photo.jpg');
    expect(vm.detail, 'the transfer ended early');
  });
}
