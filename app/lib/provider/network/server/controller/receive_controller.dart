import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:relay_app/model/state/server/receive_session_state.dart';
import 'package:relay_app/model/state/server/receiving_file.dart';
import 'package:relay_app/pages/home_page.dart';
import 'package:relay_app/pages/home_page_controller.dart';
import 'package:relay_app/pages/progress_page.dart';
import 'package:relay_app/pages/receive_page.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/favorites_provider.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/provider/http_provider.dart';
import 'package:relay_app/provider/logging/discovery_logs_provider.dart';
import 'package:relay_app/provider/network/send_provider.dart';
import 'package:relay_app/provider/network/server/server_provider.dart';
import 'package:relay_app/provider/network/server/server_utils.dart';
import 'package:relay_app/provider/receive_history_provider.dart';
import 'package:relay_app/provider/security_provider.dart';
import 'package:relay_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:relay_app/provider/selection/selected_sending_files_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/native/directories.dart';
import 'package:relay_app/util/native/platform_check.dart';
import 'package:relay_app/util/native/tray_helper.dart';
import 'package:relay_app/widget/dialogs/open_file_dialog.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/dto/file_dto.dart';
import 'package:relay_isolates/model/file_status.dart';
import 'package:relay_isolates/model/file_type.dart';
import 'package:relay_isolates/model/session_status.dart';
import 'package:relay_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;
import 'package:relay_isolates/rust/api/server.dart' show SessionEndReasonV2;
import 'package:relay_isolates/util/rust.dart';
import 'package:relay_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger('ReceiveController');

/// Handles all server events for receiving files.
/// The HTTP requests themselves are served by the Rust server which emits
/// the events handled here.
class ReceiveController {
  final ServerUtils server;
  final Map<String, _AnywherePendingReceive> _anywherePending = {};

  ReceiveController(this.server);

  /// A device registered itself on this server.
  Future<void> onRegister(HttpServerRegisterEvent event) async {
    if (event.info.fingerprint == server.ref.read(securityProvider).certificateHash) {
      // "I talked to myself lol"
      return;
    }

    // Feed the device into the discovery store; it comes back (and is
    // registered) via the [StartDiscoveryListener] stream.
    server.ref.redux(parentIsolateProvider).dispatch(IsolateDiscoveryAddDeviceAction(device: event.info.toDevice(event.ip, withChannel: true)));
    server.ref.notifier(discoveryLoggerProvider).addLog('[DISCOVER/TCP] Received "/register" HTTP request: ${event.info.alias} (${event.ip})');
  }

  /// A sender requests to upload files.
  /// The Rust server already checked the PIN and enforces that only one
  /// session can be active at a time.
  Future<void> onPrepareUpload(HttpServerPrepareUploadEvent event) async {
    if (server.getStateOrNull()?.session != null) {
      // The Rust server is the authority on the single-session invariant:
      // a new request means the old session is over (e.g. finished but still
      // displayed, or aborted while waiting).
      closeSession();
    }

    final settings = server.ref.read(settingsProvider);
    final destinationDir = settings.destination ?? await getDefaultDestinationDirectory();
    final cacheDir = await getCacheDirectory();
    final sessionId = event.sessionId;
    final files = {
      for (final entry in event.files.entries) entry.key: entry.value.toDart(),
    };

    // The fingerprint of the sender's mTLS certificate cannot be spoofed, unlike the
    // self-reported fingerprint in the JSON payload which is only used as fallback
    // when encryption is disabled.
    final senderFingerprint = event.certFingerprint ?? event.info.fingerprint;

    _logger.info('Session Id: $sessionId');
    _logger.info('Destination Directory: $destinationDir');

    server.setState(
      (oldState) => oldState?.copyWith(
        session: ReceiveSessionState(
          sessionId: sessionId,
          status: SessionStatus.waiting,
          sender: event.info.toDevice(event.ip, withChannel: false).copyWith(fingerprint: senderFingerprint),
          senderAlias: server.ref.read(favoritesProvider).firstWhereOrNull((e) => e.fingerprint == senderFingerprint)?.alias ?? event.info.alias,
          files: {
            for (final file in files.values)
              file.id: ReceivingFile(
                file: file,
                token: null,
                desiredName: null,
                path: null,
                savedToGallery: false,
                errorMessage: null,
              ),
          },
          startTime: null,
          endTime: null,
          destinationDirectory: destinationDir,
          cacheDirectory: cacheDir,
          saveToGallery: checkPlatformWithGallery() && settings.saveToGallery && files.values.every((f) => !f.fileName.contains('/')),
          createdDirectories: {},
        ),
      ),
    );

    server.ref
        .notifier(fileTransferProvider)
        .setStatuses(
          sessionId: sessionId,
          statuses: {for (final file in files.values) file.id: FileStatus.queue},
        );

    bool quickSave = settings.quickSave && server.getState().session?.message == null;
    final quickSaveFromFavorites = settings.quickSaveFromFavorites && server.getState().session?.message == null;
    if (quickSaveFromFavorites) {
      final bool isFavorite = server.ref.read(favoritesProvider).any((e) => e.fingerprint == senderFingerprint);
      if (isFavorite) {
        quickSave = true;
      }
    }
    if (server.getState().webUpload && settings.receiveViaLinkAutoAccept && server.getState().session?.message == null) {
      // The upload page (receive via link) is being served and requests should be accepted automatically.
      quickSave = true;
    }

    if (quickSave) {
      // Push before accepting: the permission request in [acceptFileRequest] may block for a while.
      // ignore: use_build_context_synchronously, unawaited_futures
      Routerino.context.pushImmediately(
        () => ProgressPage(
          showAppBar: false,
          closeSessionOnClose: true,
          sessionId: sessionId,
        ),
      );

      // accept all files
      await acceptFileRequest({
        for (final f in files.values) f.id: f.fileName,
      });
      return;
    }

    if (checkPlatformHasTray() && (await windowManager.isMinimized() || !(await windowManager.isVisible()) || !(await windowManager.isFocused()))) {
      await showFromTray();
    }

    final message = server.getState().session?.message;
    if (message != null) {
      // Message already received
      await server.ref
          .redux(receiveHistoryProvider)
          .dispatchAsync(
            AddHistoryEntryAction(
              entryId: const Uuid().v4(),
              fileName: message,
              fileType: FileType.text,
              path: null,
              savedToGallery: false,
              isMessage: true,
              fileSize: utf8.encode(message).length,
              senderAlias: server.getState().session!.senderAlias,
              timestamp: DateTime.now().toUtc(),
            ),
          );
    }

    await _presentReceivePage(files);
  }

  /// Shows the one normal receive decision UI for any transport. The backing
  /// response is chosen by [acceptFileRequest]/[declineFileRequest], never by
  /// the page: LAN replies to its server isolate while Anywhere replies to its
  /// exact authenticated session and transfer id.
  Future<void> _presentReceivePage(Map<String, FileDto> files) async {
    final message = server.getState().session?.message;
    final receiveProvider = ViewProvider((ref) {
      // No select: comparing the selected session runs the dart_mappable deep equality
      // over the whole files map on every state change.
      final session = ref.watch(serverProvider)?.session;
      return ReceivePageVm(
        status: session?.status,
        sender: session?.sender ?? Device.empty,
        showSenderInfo: true,
        files: session?.files.values.map((f) => f.file).toList() ?? [],
        message: message,
        onAccept: () async {
          if (message != null) {
            // accept nothing
            await ref.notifier(serverProvider).acceptFileRequest({});
            return;
          }

          final sessionId = ref.read(serverProvider)?.session?.sessionId;
          if (sessionId == null) {
            return;
          }

          final selectedFiles = ref.read(selectedReceivingFilesProvider);

          // Push before accepting: the permission request in [acceptFileRequest] may block for a while.
          unawaited(
            Routerino.context.pushAndRemoveUntilImmediately(
              removeUntil: ReceivePage,
              builder: () => ProgressPage(
                showAppBar: false,
                closeSessionOnClose: true,
                sessionId: sessionId,
              ),
            ),
          );

          await ref.notifier(serverProvider).acceptFileRequest(selectedFiles);
        },
        onDecline: () {
          ref.notifier(serverProvider).declineFileRequest();
        },
        onClose: () {
          ref.notifier(serverProvider).closeSession();
        },
      );
    });

    server.ref.notifier(selectedReceivingFilesProvider).setFiles(files.values.toList());

    // ignore: use_build_context_synchronously, unawaited_futures
    Routerino.context.push(() => ReceivePage(receiveProvider));
  }

  /// Delivers an authenticated Anywhere prepare-upload through the mature
  /// normal receive UI. A remote RelayId is deliberately not written to the
  /// trust directory; this is only the session-scoped receive identity.
  Future<void> onAnywhereIncoming({
    required BigInt sessionId,
    required BigInt transferId,
    required String remoteRelayId,
    required List<rust_relay_anywhere.RsRelayIncomingFile> incomingFiles,
  }) async {
    if (server.getStateOrNull()?.session != null) {
      final active = server.getStateOrNull()!.session!;
      final activeAnywhere = _anywherePending[active.sessionId];
      if (activeAnywhere != null) {
        if (active.status == SessionStatus.waiting) {
          _declineAnywhere(activeAnywhere);
        } else {
          _cancelAnywhere(active, activeAnywhere);
        }
      }
      closeSession();
    }

    final settings = server.ref.read(settingsProvider);
    final destinationDir = settings.destination ?? await getDefaultDestinationDirectory();
    final cacheDir = await getCacheDirectory();
    final localSessionId = 'relay-anywhere:$sessionId:$transferId';
    final files = {
      for (final incoming in incomingFiles)
        incoming.id: FileDto(
          id: incoming.id,
          fileName: incoming.name,
          size: incoming.size.toInt(),
          fileType: decodeFromMime(incoming.fileType),
          hash: incoming.sha256,
          preview: null,
          metadata: null,
        ),
    };
    if (files.isEmpty) {
      rust_relay_anywhere.relayAnywhereRespond(
        sessionId: sessionId,
        transferId: transferId,
        accept: false,
      );
      return;
    }

    final sender = Device(
      signalingId: null,
      ip: null,
      version: '2.2',
      port: 0,
      https: true,
      fingerprint: remoteRelayId,
      alias: 'Relay device',
      deviceModel: null,
      deviceType: DeviceType.desktop,
      download: false,
      channels: const [],
    );
    _anywherePending[localSessionId] = _AnywherePendingReceive(
      sessionId: sessionId,
      transferId: transferId,
      remoteRelayId: remoteRelayId,
    );
    server.setState(
      (oldState) => oldState?.copyWith(
        session: ReceiveSessionState(
          sessionId: localSessionId,
          status: SessionStatus.waiting,
          sender: sender,
          senderAlias: 'Relay device',
          files: {
            for (final file in files.values)
              file.id: ReceivingFile(
                file: file,
                token: null,
                desiredName: null,
                path: null,
                savedToGallery: false,
                errorMessage: null,
              ),
          },
          startTime: null,
          endTime: null,
          destinationDirectory: destinationDir,
          cacheDirectory: cacheDir,
          saveToGallery: checkPlatformWithGallery() && settings.saveToGallery && files.values.every((file) => !file.fileName.contains('/')),
          createdDirectories: {},
        ),
      ),
    );
    server.ref
        .notifier(fileTransferProvider)
        .setStatuses(
          sessionId: localSessionId,
          statuses: {for (final file in files.values) file.id: FileStatus.queue},
        );
    await _presentReceivePage(files);
  }

  /// Applies canonical authenticated-transfer progress to the same normal
  /// progress and foreground-notification state used by LAN receive.
  void onAnywhereProgress({required BigInt sessionId, required BigInt bytes, required BigInt total}) {
    final entry = _anywherePending.entries.firstWhereOrNull((entry) => entry.value.sessionId == sessionId);
    final session = server.getStateOrNull()?.session;
    if (entry == null || session == null || session.sessionId != entry.key || session.status != SessionStatus.sending) {
      return;
    }

    var remaining = bytes.toInt().clamp(0, total.toInt());
    for (final file in session.files.values) {
      if (file.desiredName == null) {
        continue;
      }
      final transferred = remaining.clamp(0, file.file.size);
      final progress = file.file.size == 0 ? 1.0 : transferred / file.file.size;
      server.ref.notifier(fileTransferProvider).setProgress(sessionId: session.sessionId, fileId: file.file.id, progress: progress);
      if (transferred > 0) {
        server.ref.notifier(fileTransferProvider).setStatus(sessionId: session.sessionId, fileId: file.file.id, status: FileStatus.sending);
      }
      remaining -= transferred;
    }
    _updateForegroundServiceProgress(session);
  }

  /// Completes the normal receive/save/history flow after the core v2 writer
  /// has verified every accepted file. Gallery post-processing is intentionally
  /// kept in the existing platform layer, not in the transport adapter.
  Future<void> onAnywhereCompleted({required BigInt sessionId}) async {
    final match = _anywherePending.entries.firstWhereOrNull((entry) => entry.value.sessionId == sessionId);
    final session = server.getStateOrNull()?.session;
    if (match == null || session == null || session.sessionId != match.key) {
      return;
    }
    final anywhere = match.value;
    bool hasError = false;
    for (final receiving in session.files.values) {
      final prepared = anywhere.targets[receiving.file.id];
      if (prepared == null || receiving.desiredName == null) {
        continue;
      }
      String? path;
      bool savedToGallery = false;
      String? error;
      try {
        if (prepared.saveToGallery) {
          (savedToGallery, path) = await saveCachedFileToGallery(
            cachedPath: prepared.target.displayPath,
            destinationDirectory: session.destinationDirectory,
            fileName: prepared.desiredName,
            isImage: prepared.fileType == FileType.image,
            createdDirectories: session.createdDirectories,
          );
        } else {
          path = prepared.target.displayPath;
        }
        await server.ref
            .redux(receiveHistoryProvider)
            .dispatchAsync(
              AddHistoryEntryAction(
                entryId: receiving.file.id,
                fileName: prepared.desiredName,
                fileType: prepared.fileType,
                path: path,
                savedToGallery: savedToGallery,
                isMessage: false,
                fileSize: receiving.file.size,
                senderAlias: session.senderAlias,
                timestamp: DateTime.now().toUtc(),
              ),
            );
      } catch (exception, stackTrace) {
        _logger.warning('Could not finish Relay receive save target', exception, stackTrace);
        error = exception.humanErrorMessage;
        hasError = true;
      }
      server.ref
          .notifier(fileTransferProvider)
          .setStatus(
            sessionId: session.sessionId,
            fileId: receiving.file.id,
            status: error == null ? FileStatus.finished : FileStatus.failed,
          );
      server.ref.notifier(fileTransferProvider).setProgress(sessionId: session.sessionId, fileId: receiving.file.id, progress: 1);
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session?.fileFinished(
            fileId: receiving.file.id,
            path: path,
            savedToGallery: savedToGallery,
            errorMessage: error,
          ),
        ),
      );
    }
    _anywherePending.remove(match.key);
    TransferNotification.stop(session.sessionId);
    server.setState(
      (oldState) => oldState?.copyWith(
        session: oldState.session?.copyWith(
          status: hasError ? SessionStatus.finishedWithErrors : SessionStatus.finished,
          endTime: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void onAnywhereTerminal({required BigInt sessionId, required bool cancelled}) {
    final match = _anywherePending.entries.firstWhereOrNull((entry) => entry.value.sessionId == sessionId);
    final session = server.getStateOrNull()?.session;
    if (match == null || session == null || session.sessionId != match.key) {
      return;
    }
    _anywherePending.remove(match.key);
    TransferNotification.stop(session.sessionId);
    if (cancelled) {
      _cancelBySender(server);
      return;
    }
    server.ref
        .notifier(fileTransferProvider)
        .setStatuses(
          sessionId: session.sessionId,
          statuses: {
            for (final file in session.files.values)
              if (file.desiredName != null) file.file.id: FileStatus.failed,
          },
        );
    server.setState(
      (oldState) => oldState?.copyWith(
        session: oldState.session?.copyWith(
          status: SessionStatus.finishedWithErrors,
          endTime: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  /// An accepted file started being uploaded.
  /// The server isolate receives and saves the file on its own
  /// ([HttpServerReceiveConfig] was sent with the accept decision);
  /// only the session state is updated here.
  void onFileUpload(HttpServerFileUploadEvent event) {
    final receiveState = server.getStateOrNull()?.session;
    const allowedStates = {SessionStatus.sending, SessionStatus.finishedWithErrors};
    if (receiveState == null || receiveState.sessionId != event.sessionId || !allowedStates.contains(receiveState.status)) {
      _logger.warning('Failing upload of file ${event.fileId}: no matching active session');
      // Fail the upload (and any further ones) by cancelling the session on the Rust side.
      server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerCancelSessionAction(sessionId: event.sessionId));
      return;
    }

    final fileId = event.fileId;
    final receivingFile = receiveState.files[fileId];
    if (receivingFile == null || receivingFile.desiredName == null) {
      _logger.warning('Unexpected fileId: $fileId');
      server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerCancelSessionAction(sessionId: event.sessionId));
      return;
    }

    // begin of actual file transfer
    server.ref.notifier(fileTransferProvider).setStatus(sessionId: event.sessionId, fileId: fileId, status: FileStatus.sending);
    if (receiveState.startTime == null || receiveState.status != SessionStatus.sending) {
      server.setState(
        (oldState) => oldState?.copyWith(
          session: receiveState.copyWith(
            startTime: receiveState.startTime ?? DateTime.now().millisecondsSinceEpoch,
            status: SessionStatus.sending, // in case it was finishedWithErrors and user retries a failed file
          ),
        ),
      );
    }
  }

  /// The receive progress of a file reported by the server isolate.
  void onFileUploadProgress(HttpServerFileUploadProgressEvent event) {
    final receiveState = server.getStateOrNull()?.session;
    if (receiveState == null || receiveState.sessionId != event.sessionId) {
      return;
    }

    server.ref
        .notifier(fileTransferProvider)
        .setProgress(
          sessionId: event.sessionId,
          fileId: event.fileId,
          progress: event.progress,
        );

    _updateForegroundServiceProgress(receiveState);
  }

  /// Reports the total session progress to the foreground service notification,
  /// so that it stays up to date while the app is minimized.
  void _updateForegroundServiceProgress(ReceiveSessionState session) {
    if (!TransferNotification.shouldUpdate) {
      // Checked before the sum below because progress events arrive several times per second per file.
      return;
    }

    final transferNotifier = server.ref.read(fileTransferProvider);
    int currentBytes = 0;
    int totalBytes = 0;
    for (final receivingFile in session.files.values) {
      if (receivingFile.desiredName == null) {
        // not accepted by the user
        continue;
      }
      final size = receivingFile.file.size;
      totalBytes += size;
      currentBytes += (transferNotifier.getProgress(sessionId: session.sessionId, fileId: receivingFile.file.id) * size).round();
    }

    TransferNotification.update(
      sessionId: session.sessionId,
      currentBytes: currentBytes,
      totalBytes: totalBytes,
      startTime: session.startTime,
      endTime: session.endTime,
    );
  }

  /// A file has been received completely (or failed) by the server isolate.
  Future<void> onFileUploadResult(HttpServerFileUploadResultEvent event) async {
    final receiveState = server.getStateOrNull()?.session;
    const allowedStates = {SessionStatus.sending, SessionStatus.finishedWithErrors};
    if (receiveState == null || receiveState.sessionId != event.sessionId || !allowedStates.contains(receiveState.status)) {
      return;
    }

    final fileId = event.fileId;
    final receivingFile = receiveState.files[fileId];
    if (receivingFile == null || receivingFile.desiredName == null) {
      _logger.warning('Unexpected fileId: $fileId');
      return;
    }

    final fileType = receivingFile.file.fileType;
    final filePath = event.path;
    final error = event.error;

    if (error == null) {
      server.ref.notifier(fileTransferProvider).setStatus(sessionId: event.sessionId, fileId: fileId, status: FileStatus.finished);
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session?.fileFinished(
            fileId: fileId,
            path: filePath,
            savedToGallery: event.savedToGallery,
            errorMessage: null,
          ),
        ),
      );

      // Track it in history
      await server.ref
          .redux(receiveHistoryProvider)
          .dispatchAsync(
            AddHistoryEntryAction(
              entryId: fileId,
              fileName: receivingFile.desiredName!,
              fileType: fileType,
              path: filePath,
              savedToGallery: event.savedToGallery,
              isMessage: false,
              fileSize: receivingFile.file.size,
              senderAlias: receiveState.senderAlias,
              timestamp: DateTime.now().toUtc(),
            ),
          );
    } else {
      server.ref.notifier(fileTransferProvider).setStatus(sessionId: event.sessionId, fileId: fileId, status: FileStatus.failed);
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session?.fileFinished(
            fileId: fileId,
            path: null,
            savedToGallery: false,
            errorMessage: error,
          ),
        ),
      );
    }

    server.ref
        .notifier(fileTransferProvider)
        .setProgress(
          sessionId: receiveState.sessionId,
          fileId: fileId,
          progress: 1,
        );

    final session = server.getStateOrNull()?.session;
    if (session == null) {
      return;
    }

    _updateForegroundServiceProgress(session);

    final statuses = server.ref.read(fileTransferProvider).getStatuses(session.sessionId);
    if (allowedStates.contains(session.status) && statuses.isFinishedOrError) {
      // The transfer is over, the process no longer needs to be kept alive for it.
      TransferNotification.stop(session.sessionId);

      final hasError = statuses.any((status) => status == FileStatus.failed);
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session!.copyWith(
            status: hasError ? SessionStatus.finishedWithErrors : SessionStatus.finished,
            endTime: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      final settings = server.ref.read(settingsProvider);
      // Only auto-close fully successful sessions: a failed file may still be
      // retried by the sender (e.g. after a checksum mismatch), which requires
      // the session to stay open.
      bool quickSave = settings.quickSave && !hasError && server.getState().session?.message == null;
      final quickSaveFromFavorites = settings.quickSaveFromFavorites && !hasError && server.getState().session?.message == null;
      if (quickSaveFromFavorites) {
        final bool isFavorite = server.ref.read(favoritesProvider).any((e) => e.fingerprint == session.sender.fingerprint);
        if (isFavorite) {
          quickSave = true;
        }
      }
      if (quickSave) {
        // close the session **after** the response has been sent
        Future.delayed(Duration.zero, () {
          closeSession();
          _logger.info('Closing session');

          // ignore: use_build_context_synchronously, discarded_futures
          Routerino.context.pushRootImmediately(() => const HomePage(initialTab: HomeTab.receive, appStart: false));

          // open the dialog to open file instantly
          if (filePath != null && filePath.isNotEmpty) {
            // ignore: discarded_futures
            OpenFileDialog.open(
              Routerino.context, // ignore: use_build_context_synchronously
              filePath: filePath,
              fileType: fileType,
              openGallery: event.savedToGallery,
            );
          }
        });
      }
      _logger.info('Received all files.');
    }
  }

  /// An upload session ended on the Rust server.
  void onSessionEnd(HttpServerSessionEndEvent event) {
    final receiveSession = server.getStateOrNull()?.session;
    if (receiveSession == null || receiveSession.sessionId != event.sessionId) {
      return;
    }

    switch (event.reason) {
      case SessionEndReasonV2.finished:
        // Already handled when the last file finished.
        break;
      case SessionEndReasonV2.cancelled:
        _cancelBySender(server);
    }
  }

  /// The sender aborted the request while the user was still deciding.
  void onPrepareUploadAborted(HttpServerPrepareUploadAbortedEvent event) {
    final receiveSession = server.getStateOrNull()?.session;
    if (receiveSession == null || receiveSession.sessionId != event.sessionId || receiveSession.status != SessionStatus.waiting) {
      return;
    }

    _cancelBySender(server);
  }

  /// A remote device cancels a transfer this application is currently
  /// *sending* to it.
  void onCancelReceived(HttpServerCancelReceivedEvent event) {
    final sendSessions = server.ref.read(sendProvider);
    final selectedSession = sendSessions.values.firstWhereOrNull((s) => s.remoteSessionId == event.sessionId);
    if (selectedSession == null) {
      return;
    }

    if (selectedSession.target.ip != event.ip) {
      return;
    }

    if (selectedSession.status != SessionStatus.sending) {
      return;
    }

    server.ref
        .notifier(sendProvider)
        .cancelSessionByReceiver(
          selectedSession.sessionId,
        );
  }

  /// Another application instance requested the running application to show itself.
  /// The show token has already been checked by the Rust server.
  void onShow(HttpServerShowEvent event) {
    if (!checkPlatformIsDesktop()) {
      return;
    }

    // ignore: discarded_futures
    showFromTray().catchError((e) {
      // don't wait for it
      _logger.severe('Failed to show from tray', e);
    });

    final args = event.args;
    if (args.isEmpty) {
      return;
    }

    // ignore: unawaited_futures, discarded_futures
    server.ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args)).then((filesAdded) {
      if (filesAdded) {
        server.ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
      }
    });
  }

  /// Accepts the file request with the given [fileNameMap] (file id -> desired file name).
  Future<void> acceptFileRequest(Map<String, String> fileNameMap) async {
    final session = server.getStateOrNull()?.session;
    if (session == null || session.status != SessionStatus.waiting) {
      return;
    }

    final anywhere = _anywherePending[session.sessionId];
    if (anywhere != null) {
      await _acceptAnywhereFileRequest(session, anywhere, fileNameMap);
      return;
    }

    if (fileNameMap.isEmpty) {
      // nothing selected, the Rust server responds with 204 and creates no session
      // This usually happens for message transfers
      server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerPrepareUploadDecisionAction(config: _buildReceiveConfig(session, {})));
      closeSession();
      return;
    }

    server.setState(
      (oldState) {
        final receiveState = oldState!.session!;
        return oldState.copyWith(
          session: receiveState.copyWith(
            status: SessionStatus.sending,
            files: Map.fromEntries(
              receiveState.files.values.map((entry) {
                final desiredName = fileNameMap[entry.file.id];
                return MapEntry(
                  entry.file.id,
                  ReceivingFile(
                    file: entry.file,
                    token: null,
                    desiredName: desiredName,
                    path: null,
                    savedToGallery: false,
                    errorMessage: null,
                  ),
                );
              }),
            ),
          ),
        );
      },
    );

    server.ref
        .notifier(fileTransferProvider)
        .setStatuses(
          sessionId: session.sessionId,
          statuses: {
            for (final file in session.files.values) file.file.id: fileNameMap.containsKey(file.file.id) ? FileStatus.queue : FileStatus.skipped,
          },
        );

    // The storage permission only exists below Android 13 (scoped storage): newer versions
    // auto-deny the request, but the round trip through the system permission activity
    // still blocks the UI noticeably.
    final androidSdkInt = server.ref.read(deviceInfoProvider).androidSdkInt;
    if (checkPlatform([TargetPlatform.android]) && androidSdkInt != null && androidSdkInt < 33) {
      try {
        final result = await Permission.storage.request();
        _logger.info('storage permission: $result');
      } catch (e) {
        _logger.warning('Could not request storage permission', e);
      }
    }

    // Keep the process alive for the whole transfer. Started here because:
    // - the app is still in the foreground, and Android 12+ rejects starting a foreground service
    //   from the background,
    // - the service may ask for the notification permission, which Android cancels when it overlaps
    //   with the storage permission requests above.
    TransferNotification.start(sessionId: session.sessionId, receiving: true);

    // From here on, the server isolate receives all accepted files on its own
    // and reports back via upload progress/result events.
    final updatedSession = server.getStateOrNull()?.session;
    if (updatedSession == null) {
      return;
    }
    server.ref
        .redux(parentIsolateProvider)
        .dispatch(IsolateHttpServerPrepareUploadDecisionAction(config: _buildReceiveConfig(updatedSession, fileNameMap)));
  }

  HttpServerReceiveConfig _buildReceiveConfig(ReceiveSessionState session, Map<String, String> fileNameMap) {
    return HttpServerReceiveConfig(
      sessionId: session.sessionId,
      fileNameMap: fileNameMap,
      destinationDirectory: session.destinationDirectory,
      cacheDirectory: session.cacheDirectory,
      saveToGallery: session.saveToGallery,
      androidSdkInt: server.ref.read(deviceInfoProvider).androidSdkInt,
    );
  }

  Future<void> _acceptAnywhereFileRequest(
    ReceiveSessionState session,
    _AnywherePendingReceive anywhere,
    Map<String, String> fileNameMap,
  ) async {
    final targets = <String, Map<String, Object>>{};
    try {
      for (final file in session.files.values) {
        final desiredName = fileNameMap[file.file.id];
        if (desiredName == null) {
          continue;
        }
        final saveToGallery = session.saveToGallery && (file.file.fileType == FileType.image || file.file.fileType == FileType.video);
        final target = await prepareFileSaveTarget(
          destinationDirectory: session.destinationDirectory,
          cacheDirectory: session.cacheDirectory,
          fileName: desiredName,
          saveToGallery: saveToGallery,
          isImage: file.file.fileType == FileType.image,
          createdDirectories: session.createdDirectories,
          androidSdkInt: server.ref.read(deviceInfoProvider).androidSdkInt,
        );
        anywhere.targets[file.file.id] = _AnywherePreparedTarget(
          target: target,
          desiredName: desiredName,
          saveToGallery: saveToGallery,
          fileType: file.file.fileType,
        );
        targets[file.file.id] = target.fileDescriptor != null
            ? {'kind': 'fileDescriptor', 'fileDescriptor': target.fileDescriptor!}
            : {'kind': 'path', 'path': target.path!};
      }
    } catch (error, stackTrace) {
      _logger.warning('Could not prepare Relay receive destination', error, stackTrace);
      _declineAnywhere(anywhere);
      closeSession();
      return;
    }

    server.setState(
      (oldState) => oldState?.copyWith(
        session: session.copyWith(
          status: SessionStatus.sending,
          startTime: DateTime.now().millisecondsSinceEpoch,
          files: Map.fromEntries(
            session.files.values.map((file) {
              final desiredName = fileNameMap[file.file.id];
              return MapEntry(
                file.file.id,
                ReceivingFile(
                  file: file.file,
                  token: null,
                  desiredName: desiredName,
                  path: null,
                  savedToGallery: false,
                  errorMessage: null,
                ),
              );
            }),
          ),
        ),
      ),
    );
    server.ref
        .notifier(fileTransferProvider)
        .setStatuses(
          sessionId: session.sessionId,
          statuses: {
            for (final file in session.files.values) file.file.id: fileNameMap.containsKey(file.file.id) ? FileStatus.queue : FileStatus.skipped,
          },
        );
    TransferNotification.start(sessionId: session.sessionId, receiving: true);
    try {
      rust_relay_anywhere.relayAnywhereRespond(
        sessionId: anywhere.sessionId,
        transferId: anywhere.transferId,
        accept: true,
        targetsJson: jsonEncode(targets),
      );
    } catch (error, stackTrace) {
      _logger.warning('Could not accept authenticated Relay transfer', error, stackTrace);
      _cancelAnywhere(session, anywhere);
    }
  }

  void declineFileRequest() {
    final session = server.getStateOrNull()?.session;
    if (session == null || session.status != SessionStatus.waiting) {
      return;
    }

    final anywhere = _anywherePending[session.sessionId];
    if (anywhere != null) {
      _declineAnywhere(anywhere);
      closeSession();
      return;
    }

    server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerPrepareUploadDecisionAction(config: null));
    closeSession();
  }

  /// Updates the destination directory for the current session.
  void setSessionDestinationDir(String destinationDirectory) {
    server.setState(
      (oldState) => oldState?.copyWith(
        session: oldState.session?.copyWith(
          destinationDirectory: destinationDirectory.replaceAll('\\', '/'),
        ),
      ),
    );
  }

  /// Updates the "saveToGallery" setting for the current session.
  void setSessionSaveToGallery(bool saveToGallery) {
    server.setState(
      (oldState) => oldState?.copyWith(
        session: oldState.session?.copyWith(
          saveToGallery: saveToGallery,
        ),
      ),
    );
  }

  /// In addition to [closeSession], this method also
  /// - cancels the session on the Rust server so that further uploads fail
  /// - notifies the sender that the session has been canceled
  void cancelSession() async {
    final session = server.getStateOrNull()?.session;
    if (session == null) {
      // the server is not running
      return;
    }

    final anywhere = _anywherePending[session.sessionId];
    if (anywhere != null) {
      _cancelAnywhere(session, anywhere);
      return;
    }

    // fail further uploads
    server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerCancelSessionAction(sessionId: session.sessionId));

    // notify sender
    final target = session.sender;
    try {
      server.ref
          .read(httpProvider)
          .pinnedTo(target.fingerprint)
          // ignore: unawaited_futures
          .cancel(
            protocol: target.getProtocolType(),
            ip: target.ip!,
            port: target.port,
            sessionId: session.sessionId,
          );
    } catch (e) {
      _logger.warning('Failed to notify sender', e);
    }

    closeSession();
  }

  void closeSession() {
    final sessionId = server.getStateOrNull()?.session?.sessionId;
    if (sessionId == null) {
      return;
    }

    TransferNotification.stop(sessionId);

    _anywherePending.remove(sessionId);

    server.setState(
      (oldState) => oldState?.copyWith(
        session: null,
      ),
    );
    server.ref.notifier(fileTransferProvider).removeSession(sessionId);
  }

  void _declineAnywhere(_AnywherePendingReceive anywhere) {
    try {
      rust_relay_anywhere.relayAnywhereRespond(
        sessionId: anywhere.sessionId,
        transferId: anywhere.transferId,
        accept: false,
      );
    } catch (error, stackTrace) {
      _logger.warning('Could not decline authenticated Relay transfer', error, stackTrace);
    }
  }

  void _cancelAnywhere(ReceiveSessionState session, _AnywherePendingReceive anywhere) {
    rust_relay_anywhere.relayAnywhereCancel(sessionId: anywhere.sessionId);
    server.setState(
      (oldState) => oldState?.copyWith(
        session: session.copyWith(
          status: SessionStatus.canceledByReceiver,
          endTime: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    TransferNotification.stop(session.sessionId);
  }
}

class _AnywherePendingReceive {
  final BigInt sessionId;
  final BigInt transferId;
  final String remoteRelayId;
  final Map<String, _AnywherePreparedTarget> targets = {};

  _AnywherePendingReceive({
    required this.sessionId,
    required this.transferId,
    required this.remoteRelayId,
  });
}

class _AnywherePreparedTarget {
  final FileSaveTarget target;
  final String desiredName;
  final bool saveToGallery;
  final FileType fileType;

  const _AnywherePreparedTarget({
    required this.target,
    required this.desiredName,
    required this.saveToGallery,
    required this.fileType,
  });
}

void _cancelBySender(ServerUtils server) {
  final receiveSession = server.getStateOrNull()?.session;
  if (receiveSession == null) {
    return;
  }

  TransferNotification.stop(receiveSession.sessionId);

  if (receiveSession.status == SessionStatus.waiting) {
    // received cancel during accept/decline
    // pop just in case if user is in [ReceiveOptionsPage]
    Routerino.context.popUntil(ReceivePage);
  }

  server.setState(
    (oldState) => oldState?.copyWith(
      session: oldState.session?.copyWith(
        status: SessionStatus.canceledBySender,
        endTime: DateTime.now().millisecondsSinceEpoch,
      ),
    ),
  );
}

extension on ReceiveSessionState {
  ReceiveSessionState fileFinished({
    required String fileId,
    required String? path,
    required bool savedToGallery,
    required String? errorMessage,
  }) {
    return copyWith(
      files: {...files}
        ..update(
          fileId,
          (file) => file.copyWith(
            path: path,
            savedToGallery: savedToGallery,
            errorMessage: errorMessage,
          ),
        ),
    );
  }
}
