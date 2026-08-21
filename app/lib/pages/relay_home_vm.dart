import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/continuity/continuity_runtime.dart';
import 'package:relay_app/model/cross_file.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/model/state/send/send_session_state.dart';
import 'package:relay_app/model/state/server/receive_session_state.dart';
import 'package:relay_app/model/state/server/server_state.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/network/nearby_devices_provider.dart';
import 'package:relay_app/provider/network/send_provider.dart';
import 'package:relay_app/provider/network/server/server_provider.dart';
import 'package:relay_app/provider/relay_paired_routes_provider.dart';
import 'package:relay_app/provider/relay_remote_transfer_provider.dart';
import 'package:relay_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:relay_app/provider/selection/selected_sending_files_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/file_status.dart';
import 'package:relay_isolates/model/session_status.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

enum RelayPresence { offline, ready, discovering }

class RelayPayloadVm {
  final int fileCount;
  final int totalBytes;

  const RelayPayloadVm({required this.fileCount, required this.totalBytes});

  bool get isEmpty => fileCount == 0;
}

enum RelayTransferDirection { send, receive }

/// The one in-flight transfer (send or receive) the spatial scene and payload dock report on.
///
/// Everything here is read off the existing session state — it does
/// not introduce any transfer information the model does not already expose.
class RelayTransferVm {
  final String sessionId;
  final String targetAlias;
  final RelayTransferDirection direction;
  final double? progress;
  final bool remote;
  final String? origin;
  final String? deviceKey;
  final int fileCount;
  final RelayDevicePhase phase;

  const RelayTransferVm({
    required this.sessionId,
    required this.targetAlias,
    this.direction = RelayTransferDirection.send,
    required this.progress,
    this.remote = false,
    this.origin,
    this.deviceKey,
    this.fileCount = 1,
    this.phase = RelayDevicePhase.sending,
  });

  bool get isSend => direction == RelayTransferDirection.send;
  bool get isReceive => direction == RelayTransferDirection.receive;
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
    List<RelayPairedAddress> pairedRoutes = const [],
    Map<String, RelayRemoteTransfer> remoteTransfers = const {},
    Map<String, RelayVerifiedLanDevice> verifiedLanDevices = const {},
    RelayContinuityState continuity = const RelayContinuityState(),
    List<RsKdeConnectDevice> kdeConnectDevices = const [],
  }) {
    final selection = RelayPayloadVm(
      fileCount: selectedFiles.length,
      totalBytes: selectedFiles.fold(0, (total, file) => total + file.size),
    );
    final pairedByRelayId = {for (final route in pairedRoutes) route.relayId: route};
    final verifiedByFingerprint = {
      for (final verified in verifiedLanDevices.values) verified.device.fingerprint: verified,
    };
    final devices =
        <RelayDeviceVm>[
          for (final device in nearby.allDevices.values)
            if (!verifiedByFingerprint.containsKey(device.fingerprint))
              _deviceVm(
                device: device,
                session: sendSessions.values.firstWhereOrNull((session) => session.target.fingerprint == device.fingerprint),
                transfers: transfers,
              ),
          for (final verified in verifiedLanDevices.values)
            if (nearby.allDevices.containsKey(verified.device.fingerprint))
              _verifiedDeviceVm(
                continuity: continuity,
                verified: verified,
                route: pairedByRelayId.remove(verified.relayId),
                transfer: remoteTransfers.values.firstWhereOrNull((entry) => entry.relayId == verified.relayId),
                session: sendSessions.values.firstWhereOrNull((session) => session.target.fingerprint == verified.device.fingerprint),
                transfers: transfers,
              ),
          for (final route in pairedByRelayId.values)
            _pairedDeviceVm(route, remoteTransfers.values.firstWhereOrNull((entry) => entry.relayId == route.relayId), continuity),
          for (final device in kdeConnectDevices) _kdeConnectDeviceVm(device),
        ]..sort((a, b) {
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
      activeTransfer: _activeTransfer(
        sendSessions: sendSessions,
        transfers: transfers,
        remoteTransfers: remoteTransfers,
        server: server,
      ),
    );
  }

  static RelayDevicePhase _receivePhase(ReceiveSessionState session) {
    if (session.status == SessionStatus.canceledBySender || session.status == SessionStatus.canceledByReceiver) {
      return RelayDevicePhase.cancelled;
    }
    if (session.status == SessionStatus.finished) {
      return RelayDevicePhase.success;
    }
    if (_isFailedTerminalStatus(session.status)) {
      return RelayDevicePhase.failed;
    }
    return switch (session.status) {
      SessionStatus.waiting => RelayDevicePhase.waiting,
      SessionStatus.sending => RelayDevicePhase.sending,
      _ => RelayDevicePhase.idle,
    };
  }

  static RelayTransferVm? _activeTransfer({
    required Map<String, SendSessionState> sendSessions,
    required FileTransferNotifier transfers,
    required Map<String, RelayRemoteTransfer> remoteTransfers,
    required ServerState? server,
  }) {
    // 1. Prioritize in-flight send/receive sessions
    for (final session in sendSessions.values) {
      final hasTransferFailure = transfers.getStatuses(session.sessionId).contains(FileStatus.failed);
      final phase = _phaseFor(session, hasTransferFailure);
      if (phase == RelayDevicePhase.sending || phase == RelayDevicePhase.waiting || phase == RelayDevicePhase.verifying) {
        return RelayTransferVm(
          sessionId: session.sessionId,
          targetAlias: session.target.alias,
          direction: RelayTransferDirection.send,
          progress: phase == RelayDevicePhase.sending ? _progressFor(session, transfers) : null,
          origin: 'Local',
          deviceKey: session.target.fingerprint,
          fileCount: session.files.length,
          phase: phase,
        );
      }
    }
    for (final transfer in remoteTransfers.values) {
      if (transfer.phase == RelayRemoteTransferPhase.preparing || transfer.phase == RelayRemoteTransferPhase.sending) {
        return RelayTransferVm(
          sessionId: transfer.sessionId,
          targetAlias: transfer.alias,
          direction: RelayTransferDirection.send,
          progress: transfer.totalBytes == 0 ? null : (transfer.bytes / transfer.totalBytes).clamp(0.0, 1.0),
          remote: true,
          origin: switch (transfer.origin) {
            'direct' => 'Direct',
            'relay' => 'Relayed',
            _ => null,
          },
          deviceKey: 'relay:${transfer.relayId}',
          fileCount: 1,
          phase: transfer.phase == RelayRemoteTransferPhase.preparing ? RelayDevicePhase.verifying : RelayDevicePhase.sending,
        );
      }
    }
    if (server?.session != null) {
      final receiveSession = server!.session!;
      if (receiveSession.status == SessionStatus.sending || receiveSession.status == SessionStatus.waiting) {
        final files = receiveSession.files.values.toList();
        final totalBytes = files.fold<int>(0, (total, file) => total + file.file.size);
        double? progress;
        if (totalBytes > 0 && receiveSession.status == SessionStatus.sending) {
          final currentBytes = files.fold<double>(
            0,
            (total, file) => total + transfers.getProgress(sessionId: receiveSession.sessionId, fileId: file.file.id).clamp(0, 1) * file.file.size,
          );
          progress = (currentBytes / totalBytes).clamp(0, 1);
        }
        return RelayTransferVm(
          sessionId: receiveSession.sessionId,
          targetAlias: receiveSession.senderAlias,
          direction: RelayTransferDirection.receive,
          progress: progress,
          origin: 'Local',
          deviceKey: receiveSession.sender.fingerprint,
          fileCount: files.length,
          phase: receiveSession.status == SessionStatus.sending ? RelayDevicePhase.sending : RelayDevicePhase.waiting,
        );
      }
    }

    // 2. Next check for terminal transitions (success, failed, cancelled) so presentation layer receives them
    for (final session in sendSessions.values) {
      final hasTransferFailure = transfers.getStatuses(session.sessionId).contains(FileStatus.failed);
      final phase = _phaseFor(session, hasTransferFailure);
      if (phase == RelayDevicePhase.success || phase == RelayDevicePhase.failed || phase == RelayDevicePhase.cancelled) {
        return RelayTransferVm(
          sessionId: session.sessionId,
          targetAlias: session.target.alias,
          direction: RelayTransferDirection.send,
          progress: phase == RelayDevicePhase.success ? 1.0 : _progressFor(session, transfers),
          origin: 'Local',
          deviceKey: session.target.fingerprint,
          fileCount: session.files.length,
          phase: phase,
        );
      }
    }
    for (final transfer in remoteTransfers.values) {
      final phase = _pairedPhase(transfer);
      if (phase == RelayDevicePhase.success || phase == RelayDevicePhase.failed || phase == RelayDevicePhase.cancelled) {
        return RelayTransferVm(
          sessionId: transfer.sessionId,
          targetAlias: transfer.alias,
          direction: RelayTransferDirection.send,
          progress: phase == RelayDevicePhase.success
              ? 1.0
              : (transfer.totalBytes == 0 ? null : (transfer.bytes / transfer.totalBytes).clamp(0.0, 1.0)),
          remote: true,
          origin: switch (transfer.origin) {
            'direct' => 'Direct',
            'relay' => 'Relayed',
            _ => null,
          },
          deviceKey: 'relay:${transfer.relayId}',
          fileCount: 1,
          phase: phase,
        );
      }
    }
    if (server?.session != null) {
      final receiveSession = server!.session!;
      final phase = _receivePhase(receiveSession);
      if (phase == RelayDevicePhase.success || phase == RelayDevicePhase.failed || phase == RelayDevicePhase.cancelled) {
        final files = receiveSession.files.values.toList();
        return RelayTransferVm(
          sessionId: receiveSession.sessionId,
          targetAlias: receiveSession.senderAlias,
          direction: RelayTransferDirection.receive,
          progress: phase == RelayDevicePhase.success ? 1.0 : null,
          origin: 'Local',
          deviceKey: receiveSession.sender.fingerprint,
          fileCount: files.length,
          phase: phase,
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
      connectionType: RelayConnectionType.local,
      securityState: RelaySecurityState.localSendCompatible,
      ip: device.ip,
      port: device.port,
      deviceModel: device.deviceModel,
    );
  }

  /// The capability gating for a KDE Connect peer, exposed so the directional
  /// rules can be tested against real advertised capability sets.
  @visibleForTesting
  static RelayDeviceVm kdeDeviceVm(RsKdeConnectDevice device) => _kdeConnectDeviceVm(device);

  static RelayDeviceVm _kdeConnectDeviceVm(RsKdeConnectDevice device) {
    final detail = device.connected && device.paired
        ? 'Connected'
        : device.paired
        ? 'Paired'
        : 'Nearby';
    return RelayDeviceVm(
      key: 'kdeconnect:${device.deviceId}',
      alias: device.name,
      deviceType: switch (device.deviceType) {
        'phone' || 'smartphone' => DeviceType.mobile,
        'tablet' => DeviceType.mobile,
        'tv' => DeviceType.desktop,
        'laptop' => DeviceType.desktop,
        _ => DeviceType.desktop,
      },
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: detail,
      targetKind: RelayDeviceTargetKind.kdeConnect,
      connectionType: RelayConnectionType.local,
      securityState: RelaySecurityState.unauthenticated,
      battery: RelayBatteryVm(
        percentage: device.batteryPercentage,
        isCharging: device.batteryIsCharging ?? false,
        isFull: device.batteryPercentage == 100 && (device.batteryIsCharging ?? false),
        isStale: !device.connected && device.batteryPercentage != null,
      ),
      networkType: device.networkType,
      signalLevel: device.signalLevel,
      connectivityStale: device.connectivityStale,
      canPing: _kdePeerAccepts(device, 'kdeconnect.ping'),
      canFindDevice: _kdePeerAccepts(device, 'kdeconnect.findmyphone.request'),
      canSendSms: _kdePeerAccepts(device, 'kdeconnect.sms.request'),
      canMuteRinger: _kdePeerAccepts(device, 'kdeconnect.telephony.request_mute'),
      capabilities: {
        RelayCapability.files: CapabilityStatus.unavailable,
        RelayCapability.clipboard: device.paired ? CapabilityStatus.available : CapabilityStatus.unavailable,
        RelayCapability.battery: device.paired ? CapabilityStatus.available : CapabilityStatus.unavailable,
        RelayCapability.messages: _kdePeerAccepts(device, 'kdeconnect.sms.request_conversations')
            ? CapabilityStatus.available
            : CapabilityStatus.unavailable,
        RelayCapability.notifications: device.paired ? CapabilityStatus.available : CapabilityStatus.unavailable,
        RelayCapability.phone:
            (device.paired &&
                (device.outgoingCapabilities.contains('kdeconnect.telephony') || _kdePeerAccepts(device, 'kdeconnect.telephony.request_mute')))
            ? CapabilityStatus.available
            : CapabilityStatus.unavailable,
      },
      ip: device.ip,
      port: device.port,
    );
  }

  static bool _kdePeerAccepts(RsKdeConnectDevice device, String packetType) =>
      device.paired && device.connected && device.incomingCapabilities.contains(packetType);

  static RelayDeviceVm _idle(Device device) => RelayDeviceVm(
    key: device.fingerprint,
    alias: device.alias,
    deviceType: device.deviceType,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
    connectionType: RelayConnectionType.local,
    securityState: RelaySecurityState.localSendCompatible,
    ip: device.ip,
    port: device.port,
    deviceModel: device.deviceModel,
  );

  static RelayDeviceVm _pairedDeviceVm(
    RelayPairedAddress route,
    RelayRemoteTransfer? transfer,
    RelayContinuityState continuity,
  ) => RelayDeviceVm(
    key: 'relay:${route.relayId}',
    alias: route.displayLabel ?? 'Relay device',
    deviceType: DeviceType.desktop,
    phase: _pairedPhase(transfer),
    progress: transfer == null || transfer.totalBytes == 0 ? null : transfer.bytes / transfer.totalBytes,
    detail: _pairedDetail(transfer),
    targetKind: RelayDeviceTargetKind.pairedRelay,
    relayId: route.relayId,
    // A live continuity session knows the path it actually runs over, so it
    // decides how this device is reported. A past transfer's origin is only a
    // fallback for a device with no session right now.
    connectionType: switch (continuity.deviceFor(route.relayId)) {
      final device when device.connected && device.localPath => RelayConnectionType.local,
      final device when device.connected && device.directPath => RelayConnectionType.direct,
      _ => switch (transfer?.origin) {
        'direct' => RelayConnectionType.direct,
        'relay' => RelayConnectionType.relayed,
        _ => RelayConnectionType.relayed,
      },
    },
    securityState: RelaySecurityState.verifiedRelay,
    battery: _batteryFor(continuity, route.relayId),
    capabilities: _capabilitiesFor(continuity, route.relayId),
    continuityConnected: continuity.deviceFor(route.relayId).connected,
  );

  static RelayDeviceVm _verifiedDeviceVm({
    required RelayContinuityState continuity,
    required RelayVerifiedLanDevice verified,
    required RelayPairedAddress? route,
    required RelayRemoteTransfer? transfer,
    required SendSessionState? session,
    required FileTransferNotifier transfers,
  }) {
    final lan = _deviceVm(device: verified.device, session: session, transfers: transfers);
    final useLanState = session != null || transfer == null;
    return RelayDeviceVm(
      key: 'relay:${verified.relayId}',
      alias: route?.displayLabel ?? verified.device.alias,
      deviceType: verified.device.deviceType,
      phase: useLanState ? lan.phase : _pairedPhase(transfer),
      progress: useLanState
          ? lan.progress
          : transfer.totalBytes == 0
          ? null
          : transfer.bytes / transfer.totalBytes,
      detail: useLanState ? lan.detail : _pairedDetail(transfer),
      targetKind: RelayDeviceTargetKind.verifiedRelay,
      relayId: verified.relayId,
      lanFingerprint: verified.device.fingerprint,
      connectionType: RelayConnectionType.local,
      securityState: RelaySecurityState.verifiedRelay,
      ip: verified.device.ip,
      port: verified.device.port,
      deviceModel: verified.device.deviceModel,
      battery: _batteryFor(continuity, verified.relayId),
      capabilities: _capabilitiesFor(continuity, verified.relayId),
      continuityConnected: continuity.deviceFor(verified.relayId).connected,
    );
  }

  /// The peer's last reported battery, marked stale rather than dropped when it
  /// is old.
  static RelayBatteryVm _batteryFor(RelayContinuityState continuity, String relayId) {
    final battery = continuity.deviceFor(relayId).battery;
    if (battery == null) {
      return const RelayBatteryVm();
    }
    return RelayBatteryVm(
      percentage: battery.percentage,
      isCharging: battery.isCharging,
      isFull: battery.isFull,
      isStale: battery.isStale(DateTime.now()),
    );
  }

  /// Folds three separate facts into one status per capability: what the user
  /// enabled here, whether a session is live, and what the peer advertised.
  static Map<RelayCapability, CapabilityStatus> _capabilitiesFor(RelayContinuityState continuity, String relayId) {
    final settings = continuity.settingsFor(relayId);
    final device = continuity.deviceFor(relayId);
    final result = <RelayCapability, CapabilityStatus>{};
    for (final kind in ContinuityCapabilityKind.values) {
      final capability = _capabilityOf(kind);
      if (!settings.isEnabled(kind)) {
        result[capability] = CapabilityStatus.disabled;
        continue;
      }
      final remote = device.remoteCapabilities[kind];
      result[capability] = switch (remote) {
        null => device.connected ? CapabilityStatus.available : CapabilityStatus.disabled,
        final state when state.needsPermission => CapabilityStatus.permissionRequired,
        final state when state.isLimited => CapabilityStatus.limited,
        final state when state.isAvailable => CapabilityStatus.available,
        _ => CapabilityStatus.unavailable,
      };
    }
    return result;
  }

  static RelayCapability _capabilityOf(ContinuityCapabilityKind kind) => switch (kind) {
    ContinuityCapabilityKind.battery => RelayCapability.battery,
    ContinuityCapabilityKind.clipboard => RelayCapability.clipboard,
    ContinuityCapabilityKind.notifications => RelayCapability.notifications,
    ContinuityCapabilityKind.messages => RelayCapability.messages,
    ContinuityCapabilityKind.phone => RelayCapability.phone,
  };

  static RelayDevicePhase _pairedPhase(RelayRemoteTransfer? transfer) => switch (transfer?.phase) {
    null => RelayDevicePhase.idle,
    RelayRemoteTransferPhase.preparing => RelayDevicePhase.verifying,
    RelayRemoteTransferPhase.sending => RelayDevicePhase.sending,
    RelayRemoteTransferPhase.completed => RelayDevicePhase.success,
    RelayRemoteTransferPhase.cancelled => RelayDevicePhase.cancelled,
    RelayRemoteTransferPhase.failed => RelayDevicePhase.failed,
  };

  static String _pairedDetail(RelayRemoteTransfer? transfer) => switch (transfer?.phase) {
    null || RelayRemoteTransferPhase.preparing => 'Ready',
    RelayRemoteTransferPhase.sending => 'Sending',
    RelayRemoteTransferPhase.completed => switch (transfer?.origin) {
      'direct' => 'Direct',
      'relay' => 'Relayed',
      _ => 'Sent',
    },
    RelayRemoteTransferPhase.failed => 'Could not send',
    RelayRemoteTransferPhase.cancelled => 'Cancelled',
  };

  static RelayDevicePhase _phaseFor(SendSessionState session, bool hasTransferFailure) {
    if (session.hashedFileCount < session.files.length) {
      return RelayDevicePhase.verifying;
    }
    if (session.status == SessionStatus.canceledBySender || session.status == SessionStatus.canceledByReceiver) {
      return RelayDevicePhase.cancelled;
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
    SessionStatus.recipientBusy || SessionStatus.declined || SessionStatus.tooManyAttempts || SessionStatus.finishedWithErrors => true,
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
    RelayDevicePhase.cancelled => 'Cancelled',
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
    pairedRoutes: ref.watch(relayPairedRoutesProvider),
    remoteTransfers: ref.watch(relayRemoteTransfersProvider),
    verifiedLanDevices: ref.watch(relayVerifiedLanDevicesProvider),
    continuity: ref.watch(continuityProvider),
    kdeConnectDevices: ref.watch(kdeConnectProvider.select((state) => state.devices)),
  );
}, debugLabel: 'relayHomeVmProvider');
