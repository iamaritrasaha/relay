/* Relay — GNOME Shell integration
 *
 * Presents the status of the user's primary phone in the GNOME top panel.
 *
 * This extension speaks no device protocol. It subscribes to one sanitized
 * snapshot published by Relay on the session bus and draws it; discovery,
 * pairing, transport, TLS and packet handling all stay inside Relay, which
 * remains the single source of device truth.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

import {
    accessibleName,
    batteryIconNames,
    hasLiveBattery,
    needsAttention,
    networkIconNames,
    notificationPulseOpacities,
    normalizePhoneStatus,
    unreadLabel,
} from './phoneStatus.js';

const BUS_NAME = 'com.foresight.app.relay.Shell';
const OBJECT_PATH = '/com/foresight/app/relay/Shell';
const INTERFACE_NAME = 'com.foresight.app.relay.Shell1';

/* Held for as long as the pill is presenting Relay. Relay watches this name and
 * stays out of the notification area while it exists, so the user gets one
 * Relay in the panel rather than two. */
const SURFACE_BUS_NAME = 'com.foresight.app.relay.ShellSurface';

/** Desktop entries to try, in order, when Relay is not running. */
const DESKTOP_IDS = ['relay.desktop', 'com.foresight.app.relay.desktop'];

const APPEAR_MS = 180;
const CHANGE_MS = 140;
const NOTIFICATION_PULSE_PHASE_MS = 180;

const FULL_OPACITY = 255;
const MUTED_OPACITY = 155;
const SECONDARY_OPACITY = 180;

/**
 * A themed icon built from a fallback chain.
 *
 * Icon names differ between themes and shell versions, so every icon is asked
 * for as a list ending in a name the shell is certain to have. A theme missing
 * the preferred name degrades to the next one instead of drawing nothing.
 *
 * @param {string[]} names - icon names, most specific first
 * @returns {Gio.ThemedIcon} the icon
 */
function themedIcon(names) {
    return new Gio.ThemedIcon({names});
}

/** @returns {boolean} whether the shell is currently animating anything */
function animationsEnabled() {
    return St.Settings.get().enable_animations;
}

/**
 * Replaces a label's text with a quick crossfade, so a percentage or a count
 * changing reads as a change rather than a flicker.
 *
 * @param {St.Label} label - the label to update
 * @param {string} text - the new text
 */
function setLabelText(label, text) {
    if (label.text === text)
        return;

    if (!animationsEnabled() || !label.visible) {
        label.text = text;
        return;
    }

    label.remove_all_transitions();
    label.ease({
        opacity: 0,
        duration: CHANGE_MS / 2,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        onComplete: () => {
            label.text = text;
            label.ease({
                opacity: FULL_OPACITY,
                duration: CHANGE_MS / 2,
                mode: Clutter.AnimationMode.EASE_IN_QUAD,
            });
        },
    });
}

/** One label-and-value row in the menu. */
const InfoRow = GObject.registerClass(
class RelayInfoRow extends PopupMenu.PopupBaseMenuItem {
    _init(label, value) {
        super._init({reactive: false, can_focus: false, style_class: 'popup-menu-item relay-info-row'});

        this._label = new St.Label({text: label, style_class: 'relay-info-label', y_align: Clutter.ActorAlign.CENTER, opacity: SECONDARY_OPACITY});
        this._value = new St.Label({text: value, style_class: 'relay-info-value', y_align: Clutter.ActorAlign.CENTER});
        this._value.clutter_text.ellipsize = Pango.EllipsizeMode.END;

        this.add_child(this._label);
        this.add_child(new St.Widget({x_expand: true}));
        this.add_child(this._value);
    }

    setValue(value) {
        this._value.text = value;
    }
});

/**
 * The Relay pill in the top panel, plus the menu behind it.
 *
 * Its first visual is always network reception. The notification slot keeps a
 * fixed footprint, so attention never shifts the clock or neighboring panel
 * items; a new notification uses a short finite pulse instead.
 */
const RelayPhoneIndicator = GObject.registerClass(
class RelayPhoneIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.5, 'Relay', false);

        this._extension = extension;
        this._status = null;
        this._serviceAvailable = false;
        this._wasConnected = false;
        this._handlerIds = [];
        this._previousNotificationCount = 0;
        this._notificationPulseGeneration = 0;
        this._destroyed = false;

        this.add_style_class_name('relay-pill');

        this._box = new St.BoxLayout({style_class: 'relay-pill-box', y_align: Clutter.ActorAlign.CENTER});
        this.add_child(this._box);

        this._signalIcon = new St.Icon({style_class: 'relay-pill-icon relay-signal-icon', y_align: Clutter.ActorAlign.CENTER});
        this._box.add_child(this._signalIcon);

        this._battery = this._buildSegment();
        this._notifications = this._buildSegment('relay-notification-slot');
        this._notifications.icon.gicon = themedIcon(['preferences-system-notifications-symbolic', 'user-available-symbolic']);
        this._notifications.label.hide();
        this._notifications.box.opacity = 0;
        this._notifications.box.show();

        this._stateLabel = new St.Label({style_class: 'relay-pill-state', y_align: Clutter.ActorAlign.CENTER});
        this._stateLabel.hide();
        this._box.add_child(this._stateLabel);

        this._buildMenu();

        this._connectTo(this, 'key-press-event', (actor, event) => this._onKeyPress(actor, event));

        this.connect('destroy', () => this._onDestroy());
        this._render();
    }

    /**
     * Opens the menu from the keyboard.
     *
     * The shell's own panel button only wires arrow-key navigation, so this is
     * added rather than inherited: a panel control that cannot be reached
     * without a mouse is not finished.
     *
     * @param {Clutter.Actor} actor - the pill
     * @param {Clutter.Event} event - the key event
     * @returns {boolean} whether the key was consumed
     */
    _onKeyPress(actor, event) {
        const symbol = event.get_key_symbol();
        if (symbol === Clutter.KEY_Return || symbol === Clutter.KEY_KP_Enter || symbol === Clutter.KEY_space) {
            this.menu.toggle();
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _connectTo(object, signal, callback) {
        this._handlerIds.push([object, object.connect(signal, callback)]);
    }

    /**
     * @param {string} [styleClass] - extra style class for the group
     * @returns {object} the icon and label of a status segment
     */
    _buildSegment(styleClass) {
        const box = new St.BoxLayout({
            style_class: styleClass ? `relay-pill-segment ${styleClass}` : 'relay-pill-segment',
            y_align: Clutter.ActorAlign.CENTER,
        });
        const icon = new St.Icon({style_class: 'relay-pill-icon', y_align: Clutter.ActorAlign.CENTER});
        const label = new St.Label({style_class: 'relay-pill-value', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(icon);
        box.add_child(label);
        box.hide();
        this._box.add_child(box);
        return {box, icon, label};
    }

    _buildMenu() {
        this._header = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false, style_class: 'popup-menu-item relay-header'});
        this._headerIcon = new St.Icon({style_class: 'relay-header-icon', y_align: Clutter.ActorAlign.CENTER});
        const headerText = new St.BoxLayout({vertical: true, x_expand: true, style_class: 'relay-header-text'});
        this._headerName = new St.Label({style_class: 'relay-header-name'});
        this._headerName.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        this._headerState = new St.Label({style_class: 'relay-header-state', opacity: SECONDARY_OPACITY});
        headerText.add_child(this._headerName);
        headerText.add_child(this._headerState);
        this._header.add_child(this._headerIcon);
        this._header.add_child(headerText);
        this.menu.addMenuItem(this._header);

        this._detailSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._detailSection);

        this._batteryRow = new InfoRow(_('Battery'), '');
        this._batteryStateRow = new InfoRow(_('Status'), '');
        this._networkRow = new InfoRow(_('Network'), '');
        this._signalRow = new InfoRow(_('Signal'), '');
        this._notificationsRow = new InfoRow(_('Notifications'), '');
        this._messagesRow = new InfoRow(_('Messages'), '');
        for (const row of [this._batteryRow, this._batteryStateRow, this._networkRow, this._signalRow, this._notificationsRow, this._messagesRow])
            this._detailSection.addMenuItem(row);

        this._actionSeparator = new PopupMenu.PopupSeparatorMenuItem();
        this.menu.addMenuItem(this._actionSeparator);

        this._findItem = new PopupMenu.PopupMenuItem(_('Find Phone'));
        this._findItem.connect('activate', () => this._extension.findPhone(this._status?.deviceId));
        this.menu.addMenuItem(this._findItem);

        this._openItem = new PopupMenu.PopupMenuItem(_('Open Relay'));
        this._openItem.connect('activate', () => this._extension.openRelay());
        this.menu.addMenuItem(this._openItem);

        this._quitItem = new PopupMenu.PopupMenuItem(_('Quit Relay'));
        this._quitItem.connect('activate', () => this._extension.quitRelay());
        this.menu.addMenuItem(this._quitItem);
    }

    /**
     * Applies a new snapshot.
     *
     * @param {object|null} status - a validated status, or null for no phone
     * @param {boolean} serviceAvailable - whether Relay is running
     */
    setStatus(status, serviceAvailable) {
        this._status = status;
        this._serviceAvailable = serviceAvailable;
        try {
            this._render();
        } catch (error) {
            // The pill lives inside gnome-shell. A drawing mistake has to stay
            // a drawing mistake rather than becoming a shell traceback.
            console.debug(`Relay: could not draw the phone status: ${error.message}`);
        }
    }

    _render() {
        const status = this._status;
        const connected = status !== null && status.connected;

        // Network reception is the permanent leading language. Until Relay has
        // a genuine reading, the native signal-none icon is deliberately muted;
        // a handset icon is never substituted and no strength is invented.
        this._signalIcon.gicon = themedIcon(networkIconNames(status));
        this._signalIcon.opacity = connected && status.signalLevel === null ? SECONDARY_OPACITY : FULL_OPACITY;

        if (!connected) {
            this._battery.box.hide();
            this._clearNotificationAttention();
        } else {
            this._renderBattery(status);
            this._renderAttention(status);
        }

        // With no phone to describe, "Relay" is the only word admitted to the
        // top bar. A known phone that dropped off is stated as offline.
        const offline = this._serviceAvailable && status !== null && !connected;
        const noPhone = !this._serviceAvailable || status === null;
        if (offline || noPhone)
            this._stateLabel.text = offline ? _('Offline') : 'Relay';
        this._stateLabel.visible = offline || noPhone;

        this._box.opacity = connected ? FULL_OPACITY : MUTED_OPACITY;
        if (connected && !this._wasConnected)
            this._greet();
        this._wasConnected = connected;

        this.accessible_name = accessibleName(status, this._serviceAvailable, _);
        this._renderMenu();
    }

    _renderBattery(status) {
        // A phone that went away keeps its last reading in the menu, but the
        // panel stops presenting it as if it were current.
        if (!hasLiveBattery(status)) {
            this._battery.box.hide();
            return;
        }
        this._battery.icon.gicon = themedIcon(batteryIconNames(status));
        setLabelText(this._battery.label, `${status.batteryPercentage}%`);
        this._battery.box.show();
    }

    /**
     * Updates the fixed notification slot and starts a finite pulse only when
     * the standing count increases.
     */
    _renderAttention(status) {
        const count = status.notificationCount ?? 0;
        const pulse = notificationPulseOpacities(this._previousNotificationCount, count, animationsEnabled());
        this._previousNotificationCount = count;
        this._notificationPulseGeneration += 1;
        const generation = this._notificationPulseGeneration;
        this._notifications.box.remove_all_transitions();

        if (count <= 0) {
            this._notifications.box.opacity = 0;
        } else {
            this._notifications.box.opacity = FULL_OPACITY;
            if (pulse.length > 0)
                this._runNotificationPulse(pulse, 0, generation);
        }

        if (needsAttention(status))
            this._box.add_style_class_name('relay-attentive');
        else
            this._box.remove_style_class_name('relay-attentive');
    }

    _runNotificationPulse(opacities, index, generation) {
        if (this._destroyed || generation !== this._notificationPulseGeneration)
            return;
        if (index >= opacities.length) {
            this._notifications.box.opacity = this._previousNotificationCount > 0 ? FULL_OPACITY : 0;
            return;
        }
        this._notifications.box.ease({
            opacity: opacities[index],
            duration: NOTIFICATION_PULSE_PHASE_MS,
            mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onComplete: () => this._runNotificationPulse(opacities, index + 1, generation),
        });
    }

    _clearNotificationAttention() {
        this._previousNotificationCount = 0;
        this._notificationPulseGeneration += 1;
        this._notifications.box.remove_all_transitions();
        this._notifications.box.opacity = 0;
        this._box.remove_style_class_name('relay-attentive');
    }

    _renderMenu() {
        const status = this._status;

        if (!this._serviceAvailable) {
            this._headerIcon.gicon = themedIcon(['computer-symbolic']);
            this._headerName.text = 'Relay';
            this._headerState.text = _('Not running');
        } else if (status === null) {
            this._headerIcon.gicon = themedIcon(['phone-symbolic', 'smartphone-symbolic']);
            this._headerName.text = 'Relay';
            this._headerState.text = _('No phone connected');
        } else {
            this._headerIcon.gicon = themedIcon(['phone-symbolic', 'smartphone-symbolic', 'computer-symbolic']);
            this._headerName.text = status.displayName;
            this._headerState.text = status.connected ? _('Connected') : _('Offline');
        }

        const showBattery = status !== null;
        this._batteryRow.visible = showBattery;
        this._batteryStateRow.visible = false;
        if (showBattery) {
            if (status.batteryPercentage === null) {
                this._batteryRow.setValue(_('Not reported'));
            } else {
                this._batteryRow.setValue(`${status.batteryPercentage}%`);
                this._batteryStateRow.visible = true;
                if (status.batteryIsStale || !status.connected)
                    this._batteryStateRow.setValue(_('Last known'));
                else if (status.batteryIsFull)
                    this._batteryStateRow.setValue(_('Charged'));
                else if (status.batteryIsCharging)
                    this._batteryStateRow.setValue(_('Charging'));
                else
                    this._batteryStateRow.setValue(_('On battery'));
            }
        }

        // Network has no source in Relay yet. Its rows appear the moment a real
        // capability starts reporting it, and stay away until then rather than
        // standing in as empty placeholders.
        const showNetwork = status !== null && status.networkLabel !== null;
        this._networkRow.visible = showNetwork;
        if (showNetwork)
            this._networkRow.setValue(status.networkLabel);

        const showSignal = status !== null && status.signalLevel !== null;
        this._signalRow.visible = showSignal;
        if (showSignal)
            this._signalRow.setValue('▂▄▆█'.slice(0, status.signalLevel) || _('No signal'));

        const showNotifications = status !== null && status.supportsNotifications;
        this._notificationsRow.visible = showNotifications;
        if (showNotifications) {
            const count = status.notificationCount;
            this._notificationsRow.setValue(count === null ? _('Not reported') : count === 0 ? _('None') : unreadLabel(count));
        }

        const showMessages = status !== null && status.supportsMessages;
        this._messagesRow.visible = showMessages;
        if (showMessages) {
            const count = status.unreadMessageCount;
            this._messagesRow.setValue(count === null ? _('Not reported') : count === 0 ? _('No unread messages') : unreadLabel(count));
        }

        this._findItem.visible = status !== null && status.supportsFindDevice;
        this._openItem.visible = this._extension.canOpenRelay();
        this._quitItem.visible = this._serviceAvailable;
        this._actionSeparator.visible = this._findItem.visible || this._openItem.visible || this._quitItem.visible;
    }

    /**
     * One soft rise when a phone comes back.
     *
     * Deliberately a single shot: a permanently animating panel is a permanent
     * distraction, and it would keep a repaint running while nothing changes.
     */
    _greet() {
        if (!animationsEnabled())
            return;
        this._box.remove_all_transitions();
        this._box.set_pivot_point(0.5, 0.5);
        this._box.set_scale(0.9, 0.9);
        this._box.ease({
            scale_x: 1,
            scale_y: 1,
            duration: APPEAR_MS,
            mode: Clutter.AnimationMode.EASE_OUT_BACK,
        });
    }

    _onDestroy() {
        this._destroyed = true;
        this._notificationPulseGeneration += 1;
        this._notifications.box.remove_all_transitions();
        this._battery.label.remove_all_transitions();
        this._box.remove_all_transitions();
        for (const [object, handlerId] of this._handlerIds)
            object.disconnect(handlerId);
        this._handlerIds = [];
    }
});

export default class RelayPhonePillExtension extends Extension {
    enable() {
        console.log('[Relay Pill][S4] enable');
        this._cancellable = new Gio.Cancellable();
        this._proxy = null;
        this._signalId = 0;
        this._serviceGeneration = 0;
        this._statusSeen = false;

        // A failed earlier lifecycle must not leave two Relay entries behind.
        Main.panel.statusArea[this.uuid]?.destroy();
        this._indicator = new RelayPhoneIndicator(this);
        console.log('[Relay Pill][S5] indicator created');
        Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');
        console.log('[Relay Pill][S6] added to panel');

        // Relay is an ordinary desktop app, not a bus-activated service. The
        // pill therefore follows the name: it comes alive when Relay starts and
        // falls back to an offline state when Relay quits, without reconnect
        // loops in between.
        this._watchId = Gio.bus_watch_name(
            Gio.BusType.SESSION,
            BUS_NAME,
            Gio.BusNameWatcherFlags.NONE,
            () => {
                console.log('[Relay Pill][S7] Relay service appeared');
                this._connectService();
            },
            () => {
                console.log('[Relay Pill][S7] Relay service disappeared');
                this._disconnectService();
            });

        // Owning this name is how Relay knows the panel is presenting it, and
        // therefore that it should not also sit in the notification area.
        this._surfaceOwnerId = Gio.bus_own_name(
            Gio.BusType.SESSION,
            SURFACE_BUS_NAME,
            Gio.BusNameOwnerFlags.NONE,
            null,
            () => console.log('[Relay Pill][S11] shell surface owned'),
            () => console.log('[Relay Pill][S11] shell surface released'));
    }

    disable() {
        console.log('[Relay Pill] disable');
        this._serviceGeneration += 1;
        if (this._watchId) {
            Gio.bus_unwatch_name(this._watchId);
            this._watchId = 0;
        }
        if (this._surfaceOwnerId) {
            Gio.bus_unown_name(this._surfaceOwnerId);
            this._surfaceOwnerId = 0;
        }
        this._cancellable?.cancel();
        this._cancellable = null;
        this._releaseProxy();
        this._indicator?.destroy();
        this._indicator = null;
    }

    _releaseProxy() {
        if (this._proxy && this._signalId)
            this._proxy.disconnect(this._signalId);
        this._signalId = 0;
        this._proxy = null;
    }

    _connectService() {
        const generation = ++this._serviceGeneration;
        const cancellable = this._cancellable;
        Gio.DBusProxy.new(
            Gio.DBus.session,
            Gio.DBusProxyFlags.DO_NOT_AUTO_START,
            null,
            BUS_NAME,
            OBJECT_PATH,
            INTERFACE_NAME,
            cancellable,
            (_source, result) => {
                let proxy;
                try {
                    proxy = Gio.DBusProxy.new_finish(result);
                } catch (error) {
                    if (!error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        console.debug(`Relay: could not reach the status service: ${error.message}`);
                    return;
                }
                if (cancellable !== this._cancellable || generation !== this._serviceGeneration || this._indicator === null)
                    return;

                this._releaseProxy();
                this._proxy = proxy;
                this._statusSeen = false;
                console.log('[Relay Pill][S8] status proxy ready');
                this._signalId = proxy.connect('g-signal', (_p, _sender, name, parameters) => {
                    if (name === 'PhoneStatusChanged')
                        this._applyStatusVariant(parameters, generation);
                });
                this._requestStatus(proxy, generation);
            });
    }

    _requestStatus(proxy, generation) {
        proxy.call('GetPhoneStatus', null, Gio.DBusCallFlags.NONE, -1, this._cancellable, (source, result) => {
            try {
                const parameters = source.call_finish(result);
                if (generation === this._serviceGeneration && source === this._proxy)
                    this._applyStatusVariant(parameters, generation);
            } catch (error) {
                if (!error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    console.debug(`Relay: could not read the phone status: ${error.message}`);
            }
        });
    }

    /**
     * @param {GLib.Variant} parameters - a `(a{sv})` payload
     */
    _applyStatusVariant(parameters, generation) {
        if (this._indicator === null || generation !== this._serviceGeneration)
            return;
        let status = null;
        try {
            const [raw] = parameters.recursiveUnpack();
            status = normalizePhoneStatus(raw);
        } catch (error) {
            // A snapshot that cannot be read leaves the pill in its previous
            // safe state rather than taking the shell down with it.
            console.debug(`Relay: ignoring a malformed phone status: ${error.message}`);
            return;
        }
        if (!this._statusSeen) {
            this._statusSeen = true;
            console.log('[Relay Pill][S9] initial status received');
        }
        this._indicator.setStatus(status, true);
    }

    _disconnectService() {
        this._serviceGeneration += 1;
        this._statusSeen = false;
        this._releaseProxy();
        this._indicator?.setStatus(null, false);
    }

    /** @returns {Gio.DesktopAppInfo|null} the Relay desktop entry, if installed */
    _desktopAppInfo() {
        for (const id of DESKTOP_IDS) {
            const info = Gio.DesktopAppInfo.new(id);
            if (info)
                return info;
        }
        return null;
    }

    /** @returns {boolean} whether Relay can be brought up from here */
    canOpenRelay() {
        return this._proxy !== null || this._desktopAppInfo() !== null;
    }

    /**
     * @param {string} method - a method on the Relay shell interface
     * @param {GLib.Variant|null} params - its arguments
     * @param {string} description - what to say if it does not arrive
     */
    _callRelay(method, params, description) {
        this._proxy?.call(method, params, Gio.DBusCallFlags.NONE, -1, this._cancellable, (proxy, result) => {
            try {
                proxy.call_finish(result);
            } catch (error) {
                if (!error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    console.debug(`Relay: ${description}: ${error.message}`);
            }
        });
    }

    /**
     * Brings Relay forward.
     *
     * A running Relay is asked directly, so a window that is only hidden is
     * raised instead of a second instance being launched. Otherwise the desktop
     * entry is activated through Gio; no shell commands are involved.
     */
    openRelay() {
        if (this._proxy) {
            this._callRelay('Activate', null, 'could not raise the window');
            return;
        }

        const info = this._desktopAppInfo();
        if (info === null)
            return;
        try {
            info.launch([], global.create_app_launch_context(0, -1));
        } catch (error) {
            console.debug(`Relay: could not launch Relay: ${error.message}`);
        }
    }

    /** Asks a running Relay to quit, the way its notification-area entry did. */
    quitRelay() {
        this._callRelay('Quit', null, 'could not quit Relay');
    }

    /**
     * @param {string|undefined} deviceId - the phone shown in the pill
     */
    findPhone(deviceId) {
        if (!this._proxy || !deviceId)
            return;
        this._callRelay('FindPhone', new GLib.Variant('(s)', [deviceId]), 'could not ring the phone');
    }
}
