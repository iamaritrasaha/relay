import 'dart:ui';

/// Central geometry for Relay's adaptive desktop surfaces.
///
/// The resolver deliberately interpolates a small set of spatial values rather
/// than scaling the entire UI. Text and controls keep their normal size while
/// the nearby field, frame and dock gain bounded breathing room.
abstract final class RelayDesktopMetrics {
  static const double desktopBreakpoint = 700;
  static const double homeFrameWidth = 1180;
  static const double settingsFrameWidth = 1120;
  static const double settingsWideFrameWidth = 1600;
  static const double settingsSingleColumnWidth = 720;
  static const double settingsTwoColumnBreakpoint = 1050;
  static const double settingsWideBreakpoint = 1550;
  static const double settingsDesktopGutter = 24;
  static const double aboutTwoColumnBreakpoint = 960;
  static const double frameGutter = 40;
  static const double compactGutter = 20;
  static const double topBarHeight = 60;
  static const double topBarInset = 40;
  static const double medallionSize = 132;
  static const double medallionSlot = 160;
  static const double medallionGap = 112;
  static const double medallionStagger = 22;
  static const double dockHeight = 56;
  static const double dockBottomInset = 40;
  static const double settingsColumnGap = 72;
  static const double settingsRowMinHeight = 52;
  static const double aboutIdentityColumnWidth = 400;

  static bool isDesktopWidth(double width) => width >= desktopBreakpoint;

  static RelaySettingsLayout settingsLayout(double availableWidth) {
    if (availableWidth < settingsTwoColumnBreakpoint) {
      return RelaySettingsLayout.singleColumn;
    }
    if (availableWidth <= settingsWideBreakpoint) {
      return RelaySettingsLayout.twoColumnStandard;
    }
    return RelaySettingsLayout.twoColumnWide;
  }

  static bool useTwoColumnAbout(double availableWidth) => availableWidth >= aboutTwoColumnBreakpoint;

  static RelayResponsiveMetrics resolve(Size available) {
    final widthProgress = _unit((available.width - 900) / (1920 - 900));
    final heightProgress = _unit((available.height - 600) / (1080 - 600));
    final room = widthProgress * 0.58 + heightProgress * 0.42;
    final shortWindow = _unit((700 - available.height) / 100);

    return RelayResponsiveMetrics(
      viewport: available,
      maxContentWidth: _lerp(820, 1360, widthProgress),
      horizontalGutter: _lerp(24, 64, widthProgress),
      topBarInset: _lerp(20, 52, widthProgress),
      nearbyStageVerticalPadding: _lerp(20, 48, room) * (1 - shortWindow * 0.2),
      deviceMedallionDiameter: _lerp(108, 146, room),
      deviceSlotDiameter: _lerp(134, 178, room),
      deviceGap: _lerp(42, 112, widthProgress),
      deviceSilhouetteSize: _lerp(44, 57, room),
      progressRingDiameter: _lerp(126, 166, room),
      payloadDockMaxWidth: _lerp(620, 860, widthProgress),
      dockBottomSpacing: _lerp(22, 48, heightProgress),
      emptyStateScale: _lerp(0.84, 1.08, room),
      majorIconSize: _lerp(20, 24, room),
      deviceStagger: _lerp(10, 24, heightProgress),
      headingTopSpacing: _lerp(20, 38, heightProgress),
      headingBottomSpacing: _lerp(10, 16, heightProgress),
    );
  }

  static double _unit(double value) => value.clamp(0.0, 1.0);
  static double _lerp(double min, double max, double t) => min + (max - min) * t;
}

enum RelaySettingsLayout { singleColumn, twoColumnStandard, twoColumnWide }

class RelayResponsiveMetrics {
  final Size viewport;
  final double maxContentWidth;
  final double horizontalGutter;
  final double topBarInset;
  final double nearbyStageVerticalPadding;
  final double deviceMedallionDiameter;
  final double deviceSlotDiameter;
  final double deviceGap;
  final double deviceSilhouetteSize;
  final double progressRingDiameter;
  final double payloadDockMaxWidth;
  final double dockBottomSpacing;
  final double emptyStateScale;
  final double majorIconSize;
  final double deviceStagger;
  final double headingTopSpacing;
  final double headingBottomSpacing;

  const RelayResponsiveMetrics({
    required this.viewport,
    required this.maxContentWidth,
    required this.horizontalGutter,
    required this.topBarInset,
    required this.nearbyStageVerticalPadding,
    required this.deviceMedallionDiameter,
    required this.deviceSlotDiameter,
    required this.deviceGap,
    required this.deviceSilhouetteSize,
    required this.progressRingDiameter,
    required this.payloadDockMaxWidth,
    required this.dockBottomSpacing,
    required this.emptyStateScale,
    required this.majorIconSize,
    required this.deviceStagger,
    required this.headingTopSpacing,
    required this.headingBottomSpacing,
  });
}
