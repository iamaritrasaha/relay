import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/persistence/quick_save_mode.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';
import 'package:relay_isolates/model/dto/multicast_dto.dart';
import 'package:relay_isolates/model/stored_security_context.dart';

import 'mocks_stub.dart';

export 'mocks_stub.dart';

/// The persistence stubbing the desktop review renders need, in one place so
/// each render file states only what it is actually rendering.
void stubReviewPersistence(ReviewPersistenceService persistence) {
  when(persistence.getReceiveHistory()).thenReturn([]);
  when(persistence.getShowToken()).thenReturn('review-token');
  when(persistence.getAlias()).thenReturn('Falcon');
  when(persistence.getTheme()).thenReturn(ThemeMode.dark);
  when(persistence.getColorMode()).thenReturn(ColorMode.relay);
  when(persistence.getPort()).thenReturn(53317);
  when(persistence.getNetworkWhitelist()).thenReturn([]);
  when(persistence.getNetworkBlacklist()).thenReturn([]);
  when(persistence.getMulticastGroup()).thenReturn('224.0.0.167');
  when(persistence.getDestination()).thenReturn(null);
  when(persistence.getQuickSave()).thenReturn(QuickSaveMode.off);
  when(persistence.isSaveToGallery()).thenReturn(false);
  when(persistence.isSaveToHistory()).thenReturn(true);
  when(persistence.isAutoFinish()).thenReturn(false);
  when(persistence.isMinimizeToTray()).thenReturn(false);
  when(persistence.isHttps()).thenReturn(true);
  when(persistence.getSaveWindowPlacement()).thenReturn(false);
  when(persistence.getEnableAnimations()).thenReturn(false);
  when(persistence.getDeviceType()).thenReturn(DeviceType.desktop);
  when(persistence.getShareViaLinkAutoAccept()).thenReturn(false);
  when(persistence.getReceiveViaLinkAutoAccept()).thenReturn(false);
  when(persistence.getCreateChecksums()).thenReturn(true);
  when(persistence.getVerifyChecksums()).thenReturn(true);
  when(persistence.getAdvancedSettingsEnabled()).thenReturn(false);
  when(persistence.getGnomePanelDeviceId()).thenReturn(null);
  when(persistence.getGnomePanelShowNetworkType()).thenReturn(true);
  when(persistence.getGnomePanelShowBatteryPercentage()).thenReturn(true);
  when(persistence.getGnomePanelShowNotifications()).thenReturn(true);
  when(persistence.getGnomePanelChargingAnimation()).thenReturn(true);
  when(persistence.getGnomePanelShowSignal()).thenReturn(true);
}

/// A parent isolate that never spawns anything: the review renders read the
/// sync state for identity only.
class ReviewIsolateController extends IsolateController {
  ReviewIsolateController()
    : super(
        initialState: ParentIsolateState(
          syncState: SyncState(
            rootIsolateToken: Object(),
            securityContext: const StoredSecurityContext(
              privateKey: '',
              publicKey: '',
              certificate: '',
              certificateHash: '',
            ),
            deviceInfo: DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: 'Linux', androidSdkInt: null),
            alias: 'Falcon',
            port: 53317,
            networkWhitelist: null,
            networkBlacklist: null,
            protocol: ProtocolType.https,
            multicastGroup: '224.0.0.167',
            discoveryTimeout: 30,
            serverRunning: false,
            download: false,
          ),
          discovery: null,
          httpUpload: null,
          httpServer: null,
        ),
      );
}
