import 'package:collection/collection.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum RelayPresence { offline, ready, discovering }

class RelayPayloadVm {
  final int fileCount;
  final int totalBytes;

  const RelayPayloadVm({required this.fileCount, required this.totalBytes});

  bool get isEmpty => fileCount == 0;
}

/// The one in-flight send the payload dock reports on.
///
/// Everything here is read off the existing send session state — the dock does
/// not introduce any transfer information the model does not already expose.
class RelayTransferVm {
  final String sessionId;
  final String targetAlias;
  final double? progress;

  const RelayTransferVm({required this.sessionId, required this.targetAlias, required this.progress});
}

class RelayIncomingVm {
  final bool hasActiveRequest;

  const RelayIncomingVm({required this.hasActiveRequest});
}

class RelayHomeIntents {
  final bool canSelectPayload;
  final bool canChooseTarget;

  const RelayHomeIntents({required this.canSelectPayload, required this.canChooseTarget});
}

/// Derived presentation state for the review-only Relay home surface.
///
/// This adapter owns no backend state and does not dispatch any backend actions.
class RelayHomeVm {
  final String selfAlias;
  final DeviceType selfDeviceType;
  final RelayPresence presence;
  final RelayPayloadVm selection;
  final List<RelayDeviceVm> devices;
  final RelayIncomingVm incoming;
  final RelayHomeIntents intents;
  final RelayTransferVm? activeTransfer;

  const RelayHomeVm({
    required this.selfAlias,
    required this.selfDeviceType,
    required this.presence,
    required this.selection,
    required this.devices,
    required this.incoming,
    required this.intents,
    this.activeTransfer,
  });

  factory RelayHomeVm.fromState({
    required String configuredAlias,
    required DeviceType selfDeviceType,
    required ServerState? server,
    required NearbyDevicesState nearby,
    required Map<String, SendSessionState> sendSessions,
    required FileTransferNotifier transfers,
    required List<CrossFile> selectedFiles,
  }) {
    final selection = RelayPayloadVm(
      fileCount: selectedFiles.length,
      totalBytes: selectedFiles.fold(0, (total, file) => total + file.size),
    );
    final devices =
        nearby.allDevices.values
            .map(
              (device) => _deviceVm(
                device: device,
                session: sendSessions.values.firstWhereOrNull((session) => session.target.fingerprint == device.fingerprint),
                transfers: transfers,
              ),
            )
            .toList()
          ..sort((a, b) {
            final aliasComparison = a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
            return aliasComparison != 0 ? aliasComparison : a.key.compareTo(b.key);
          });

    return RelayHomeVm(
      selfAlias: server?.alias ?? configuredAlias,
      selfDeviceType: selfDeviceType,
      presence: server == null
          ? RelayPresence.offline
          : nearby.runningFavoriteScan || nearby.runningIps.isNotEmpty
          ? RelayPresence.discovering
          : RelayPresence.ready,
      selection: selection,
      devices: devices,
      incoming: RelayIncomingVm(hasActiveRequest: server?.session != null),
      intents: RelayHomeIntents(canSelectPayload: true, canChooseTarget: !selection.isEmpty),
      activeTransfer: _activeTransfer(sendSessions: sendSessions, transfers: transfers),
    );
  }

  static RelayTransferVm? _activeTransfer({
    required Map<String, SendSessionState> sendSessions,
    required FileTransferNotifier transfers,
  }) {
    for (final session in sendSessions.values) {
      final hasTransferFailure = transfers.getStatuses(session.sessionId).contains(FileStatus.failed);
      final phase = _phaseFor(session, hasTransferFailure);
      if (phase == RelayDevicePhase.sending || phase == RelayDevicePhase.waiting || phase == RelayDevicePhase.verifying) {
        return RelayTransferVm(
          sessionId: session.sessionId,
          targetAlias: session.target.alias,
          progress: phase == RelayDevicePhase.sending ? _progressFor(session, transfers) : null,
        );
      }
    }
    return null;
  }

  static RelayDeviceVm _deviceVm({
    required Device device,
    required SendSessionState? session,
    required FileTransferNotifier transfers,
  }) {
    if (session == null) {
      return _idle(device);
    }

    final statuses = transfers.getStatuses(session.sessionId).toList();
    final hasTransferFailure = statuses.contains(FileStatus.failed);
    final phase = _phaseFor(session, hasTransferFailure);
    return RelayDeviceVm(
      key: device.fingerprint,
      alias: device.alias,
      deviceType: device.deviceType,
      phase: phase,
      progress: phase == RelayDevicePhase.sending
          ? _progressFor(session, transfers)
          : phase == RelayDevicePhase.success
          ? 1
          : null,
      detail: _detailFor(phase),
    );
  }

  static RelayDeviceVm _idle(Device device) => RelayDeviceVm(
    key: device.fingerprint,
    alias: device.alias,
    deviceType: device.deviceType,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
  );

  static RelayDevicePhase _phaseFor(SendSessionState session, bool hasTransferFailure) {
    if (session.hashedFileCount < session.files.length) {
      return RelayDevicePhase.verifying;
    }
    if (hasTransferFailure || session.errorMessage != null || _isFailedTerminalStatus(session.status)) {
      return RelayDevicePhase.failed;
    }
    return switch (session.status) {
      SessionStatus.waiting => RelayDevicePhase.waiting,
      SessionStatus.sending => RelayDevicePhase.sending,
      SessionStatus.finished => RelayDevicePhase.success,
      _ => RelayDevicePhase.failed,
    };
  }

  static bool _isFailedTerminalStatus(SessionStatus status) => switch (status) {
    SessionStatus.recipientBusy ||
    SessionStatus.declined ||
    SessionStatus.tooManyAttempts ||
    SessionStatus.finishedWithErrors ||
    SessionStatus.canceledBySender ||
    SessionStatus.canceledByReceiver => true,
    _ => false,
  };

  static double? _progressFor(SendSessionState session, FileTransferNotifier transfers) {
    final files = session.files.values.toList();
    final totalBytes = files.fold<int>(0, (total, file) => total + file.file.size);
    if (totalBytes == 0) {
      return null;
    }
    final currentBytes = files.fold<double>(
      0,
      (total, file) => total + transfers.getProgress(sessionId: session.sessionId, fileId: file.file.id).clamp(0, 1) * file.file.size,
    );
    return (currentBytes / totalBytes).clamp(0, 1);
  }

  static String _detailFor(RelayDevicePhase phase) => switch (phase) {
    RelayDevicePhase.idle => 'Nearby',
    RelayDevicePhase.waiting => 'Waiting',
    RelayDevicePhase.verifying => 'Preparing',
    RelayDevicePhase.sending => 'Sending',
    RelayDevicePhase.success => 'Sent',
    RelayDevicePhase.failed => 'Could not send',
  };
}

final relayHomeVmProvider = ViewProvider<RelayHomeVm>((ref) {
  return RelayHomeVm.fromState(
    configuredAlias: ref.watch(settingsProvider.select((state) => state.alias)),
    selfDeviceType: ref.watch(deviceInfoProvider.select((state) => state.deviceType)),
    server: ref.watch(serverProvider),
    nearby: ref.watch(nearbyDevicesProvider),
    sendSessions: ref.watch(sendProvider),
    transfers: ref.watch(fileTransferProvider),
    selectedFiles: ref.watch(selectedSendingFilesProvider),
  );
}, debugLabel: 'relayHomeVmProvider');
