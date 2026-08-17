import 'dart:async';

import 'package:dbus/dbus.dart';

const kdeConnectServiceName = 'org.kde.kdeconnect';
const gsConnectServiceName = 'org.gnome.Shell.Extensions.GSConnect';

enum KdeConnectDaemonPresence { notInstalled, stopped, gsConnectOnly, running }

enum KdeConnectDbusFailureKind { unavailable, incompatibleApi, timedOut, failed }

final class KdeConnectDbusException implements Exception {
  const KdeConnectDbusException(this.kind);

  final KdeConnectDbusFailureKind kind;

  @override
  String toString() => 'KdeConnectDbusException(${kind.name})';
}

final class KdeConnectOwnerChange {
  const KdeConnectOwnerChange({required this.serviceName, required this.hasOwner});

  final String serviceName;
  final bool hasOwner;
}

final class KdeConnectPeerSnapshot {
  const KdeConnectPeerSnapshot({
    required this.opaqueId,
    required this.displayName,
    required this.reachable,
    required this.paired,
    required this.clipboardTextAvailable,
  });

  final String opaqueId;
  final String displayName;
  final bool reachable;
  final bool paired;
  final bool clipboardTextAvailable;
}

final class KdeConnectDiscoverySnapshot {
  const KdeConnectDiscoverySnapshot({required this.peers, required this.degraded});

  final List<KdeConnectPeerSnapshot> peers;
  final bool degraded;
}

abstract interface class KdeConnectDbusBoundary {
  Stream<KdeConnectOwnerChange> get ownerChanges;

  Future<KdeConnectDaemonPresence> probePresence();
  Future<KdeConnectDiscoverySnapshot> discoverPeers();
  Future<void> sendClipboardText(String opaquePeerId, String text);
  Future<void> close();
}

final class KdeConnectDbusClient implements KdeConnectDbusBoundary {
  KdeConnectDbusClient({DBusClient? client, this.methodTimeout = const Duration(seconds: 5)}) : _client = client ?? DBusClient.session() {
    ownerChanges = _client.nameOwnerChanged
        .where((event) => event.name == kdeConnectServiceName || event.name == gsConnectServiceName)
        .map((event) => KdeConnectOwnerChange(serviceName: event.name, hasOwner: event.newOwner != null))
        .asBroadcastStream();
  }

  static const _rootPath = '/modules/kdeconnect';
  static const _daemonInterface = 'org.kde.kdeconnect.daemon';
  static const _deviceInterface = 'org.kde.kdeconnect.device';
  static const _clipboardInterface = 'org.kde.kdeconnect.device.clipboard';
  static const _clipboardPluginId = 'kdeconnect_clipboard';
  static final _safeObjectPathSegment = RegExp(r'^[A-Za-z0-9_]+$');

  final DBusClient _client;
  final Duration methodTimeout;

  @override
  late final Stream<KdeConnectOwnerChange> ownerChanges;

  @override
  Future<KdeConnectDaemonPresence> probePresence() async {
    final kdeRunning = await _bounded(() => _client.nameHasOwner(kdeConnectServiceName));
    if (kdeRunning) {
      return KdeConnectDaemonPresence.running;
    }

    final gsConnectRunning = await _bounded(() => _client.nameHasOwner(gsConnectServiceName));
    if (gsConnectRunning) {
      return KdeConnectDaemonPresence.gsConnectOnly;
    }

    final activatableNames = await _bounded(_client.listActivatableNames);
    return activatableNames.contains(kdeConnectServiceName) ? KdeConnectDaemonPresence.stopped : KdeConnectDaemonPresence.notInstalled;
  }

  @override
  Future<KdeConnectDiscoverySnapshot> discoverPeers() async {
    final rootPath = DBusObjectPath(_rootPath);
    final rootNode = await _introspect(rootPath);
    final daemonInterface = _interface(rootNode, _daemonInterface);
    final devicesMethod = _method(daemonInterface, 'devices', inputSignature: 'bb', outputSignature: 'as');
    if (devicesMethod == null) {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    }

    final response = await _call(
      path: rootPath,
      interface: _daemonInterface,
      method: 'devices',
      values: const [DBusBoolean(false), DBusBoolean(false)],
      replySignature: DBusSignature('as'),
    );
    final deviceIds = response.returnValues.single.asStringArray();
    final peers = <KdeConnectPeerSnapshot>[];
    var degraded = false;

    for (final deviceId in deviceIds) {
      if (!_safeObjectPathSegment.hasMatch(deviceId)) {
        degraded = true;
        continue;
      }
      try {
        final peer = await _inspectPeer(deviceId);
        if (peer != null) {
          peers.add(peer);
        } else {
          degraded = true;
        }
      } on KdeConnectDbusException catch (error) {
        if (error.kind == KdeConnectDbusFailureKind.unavailable) {
          rethrow;
        }
        degraded = true;
      } catch (_) {
        degraded = true;
      }
    }

    return KdeConnectDiscoverySnapshot(peers: List.unmodifiable(peers), degraded: degraded);
  }

  Future<KdeConnectPeerSnapshot?> _inspectPeer(String deviceId) async {
    final devicePath = DBusObjectPath('$_rootPath/devices/$deviceId');
    final deviceNode = await _introspect(devicePath);
    final deviceInterface = _interface(deviceNode, _deviceInterface);
    if (deviceInterface == null ||
        !_hasProperty(deviceInterface, 'name', 's') ||
        !_hasProperty(deviceInterface, 'isReachable', 'b') ||
        !_hasProperty(deviceInterface, 'isPaired', 'b')) {
      return null;
    }

    final properties = await _getAllProperties(devicePath, _deviceInterface);
    final name = _readString(properties, 'name');
    final reachable = _readBoolean(properties, 'isReachable');
    final paired = _readBoolean(properties, 'isPaired');
    if (name == null || reachable == null || paired == null) {
      return null;
    }

    var clipboardAvailable = false;
    final loadedPlugins = _readStringArray(properties, 'loadedPlugins');
    if (loadedPlugins?.contains(_clipboardPluginId) ?? false) {
      final clipboardPath = DBusObjectPath('$_rootPath/devices/$deviceId/clipboard');
      try {
        final clipboardNode = await _introspect(clipboardPath);
        final clipboardInterface = _interface(clipboardNode, _clipboardInterface);
        clipboardAvailable = _method(clipboardInterface, 'sendClipboard', inputSignature: 's', outputSignature: '') != null;
      } catch (_) {
        clipboardAvailable = false;
      }
    }

    return KdeConnectPeerSnapshot(
      opaqueId: deviceId,
      displayName: name,
      reachable: reachable,
      paired: paired,
      clipboardTextAvailable: clipboardAvailable,
    );
  }

  @override
  Future<void> sendClipboardText(String opaquePeerId, String text) async {
    if (!_safeObjectPathSegment.hasMatch(opaquePeerId)) {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    }
    final clipboardPath = DBusObjectPath('$_rootPath/devices/$opaquePeerId/clipboard');
    final clipboardNode = await _introspect(clipboardPath);
    final clipboardInterface = _interface(clipboardNode, _clipboardInterface);
    if (_method(clipboardInterface, 'sendClipboard', inputSignature: 's', outputSignature: '') == null) {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    }
    await _call(
      path: clipboardPath,
      interface: _clipboardInterface,
      method: 'sendClipboard',
      values: [DBusString(text)],
      replySignature: DBusSignature.empty,
    );
  }

  Future<DBusIntrospectNode> _introspect(DBusObjectPath path) async {
    final response = await _call(
      path: path,
      interface: 'org.freedesktop.DBus.Introspectable',
      method: 'Introspect',
      replySignature: DBusSignature.string,
    );
    try {
      return parseDBusIntrospectXml(response.returnValues.single.asString());
    } catch (_) {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    }
  }

  Future<Map<String, DBusValue>> _getAllProperties(DBusObjectPath path, String interface) async {
    final response = await _call(
      path: path,
      interface: 'org.freedesktop.DBus.Properties',
      method: 'GetAll',
      values: [DBusString(interface)],
      replySignature: DBusSignature('a{sv}'),
    );
    return response.returnValues.single.asStringVariantDict();
  }

  Future<DBusMethodSuccessResponse> _call({
    required DBusObjectPath path,
    required String interface,
    required String method,
    Iterable<DBusValue> values = const [],
    required DBusSignature replySignature,
  }) {
    return _bounded(
      () => _client.callMethod(
        destination: kdeConnectServiceName,
        path: path,
        interface: interface,
        name: method,
        values: values,
        replySignature: replySignature,
        noAutoStart: true,
      ),
    );
  }

  Future<T> _bounded<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(methodTimeout);
    } on TimeoutException {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.timedOut);
    } on DBusServiceUnknownException {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.unavailable);
    } on DBusUnknownObjectException {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    } on DBusUnknownInterfaceException {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    } on DBusUnknownMethodException {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    } on DBusReplySignatureException {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.incompatibleApi);
    } catch (_) {
      throw const KdeConnectDbusException(KdeConnectDbusFailureKind.failed);
    }
  }

  static DBusIntrospectInterface? _interface(DBusIntrospectNode node, String name) {
    for (final interface in node.interfaces) {
      if (interface.name == name) {
        return interface;
      }
    }
    return null;
  }

  static DBusIntrospectMethod? _method(
    DBusIntrospectInterface? interface,
    String name, {
    required String inputSignature,
    required String outputSignature,
  }) {
    if (interface == null) {
      return null;
    }
    for (final method in interface.methods) {
      if (method.name == name && method.inputSignature.value == inputSignature && method.outputSignature.value == outputSignature) {
        return method;
      }
    }
    return null;
  }

  static bool _hasProperty(DBusIntrospectInterface interface, String name, String signature) {
    return interface.properties.any((property) => property.name == name && property.type.value == signature);
  }

  static String? _readString(Map<String, DBusValue> properties, String name) {
    final value = properties[name];
    return value?.signature.value == 's' ? value!.asString() : null;
  }

  static bool? _readBoolean(Map<String, DBusValue> properties, String name) {
    final value = properties[name];
    return value?.signature.value == 'b' ? value!.asBoolean() : null;
  }

  static List<String>? _readStringArray(Map<String, DBusValue> properties, String name) {
    final value = properties[name];
    return value?.signature.value == 'as' ? value!.asStringArray().toList(growable: false) : null;
  }

  @override
  Future<void> close() => _client.close();
}
