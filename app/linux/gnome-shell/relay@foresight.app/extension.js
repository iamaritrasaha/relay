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

/** Panel width budget, as a share of the primary monitor. */
const PANEL_WIDTH_SHARE = 0.24;
const MIN_PANEL_WIDTH = 120;
const MAX_PANEL_WIDTH = 380;

const APPEAR_MS = 180;
const EXPAND_MS = 220;
const CHANGE_MS = 140;

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
 * Brings an actor in by growing the pill out to fit it.
 *
 * Something arriving on the phone should read as the panel making room for it,
 * not as an icon blinking into place, so the width is what animates. With shell
 * animations off it simply appears.
 *
 * @param {Clutter.Actor} actor - the actor to reveal
 */
function expandActor(actor) {
    if (actor.visible)
        return;

    if (!animationsEnabled()) {
        actor.opacity = FULL_OPACITY;
        actor.set_width(-1);
        actor.show();
        return;
    }

    actor.remove_all_transitions();
    actor.show();
    actor.set_width(-1);
    const [, natural] = actor.get_preferred_width(-1);
    actor.opacity = 0;
    actor.set_width(0);
    actor.ease({
        width: natural,
        opacity: FULL_OPACITY,
        duration: EXPAND_MS,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        // Handing the width back to the layout keeps the segment responsive to
        // font size and text changes once it has arrived.
        onComplete: () => actor.set_width(-1),
    });
}

/**
 * Takes an actor away by closing the pill back up around it.
 *
 * @param {Clutter.Actor} actor - the actor to hide
 */
function collapseActor(actor) {
    if (!actor.visible)
        return;

    if (!animationsEnabled()) {
        actor.hide();
        actor.set_width(-1);
        return;
    }

    actor.remove_all_transitions();
    const [, natural] = actor.get_preferred_width(-1);
    actor.set_width(natural);
    actor.ease({
        width: 0,
        opacity: 0,
        duration: EXPAND_MS,
        mode: Clutter.AnimationMode.EASE_IN_QUAD,
        onComplete: () => {
            actor.hide();
            actor.set_width(-1);
            actor.opacity = FULL_OPACITY;
        },
    });
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
 * At rest it is a phone and its battery. It only takes more of the panel when
 * the phone has something waiting — a notification or an unread message — and
 * shrinks back once that is dealt with.
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

        this.add_style_class_name('relay-pill');

        this._box = new St.BoxLayout({style_class: 'relay-pill-box', y_align: Clutter.ActorAlign.CENTER});
        this.add_child(this._box);

        this._deviceIcon = new St.Icon({style_class: 'relay-pill-icon', y_align: Clutter.ActorAlign.CENTER});
        this._box.add_child(this._deviceIcon);

        this._network = this._buildSegment();
        this._battery = this._buildSegment();
        this._notifications = this._buildSegment('relay-attention');
        this._messages = this._buildSegment('relay-attention');

        this._stateLabel = new St.Label({style_class: 'relay-pill-state', y_align: Clutter.ActorAlign.CENTER});
        this._stateLabel.hide();
        this._box.add_child(this._stateLabel);

        this._buildMenu();

        // The width budget depends on the monitor and the text scale, so it is
        // recomputed when those change rather than on a timer.
        this._connectTo(Main.layoutManager, 'monitors-changed', () => this._applyWidthBudget());
        this._connectTo(St.ThemeContext.get_for_stage(global.stage), 'notify::scale-factor', () => this._applyWidthBudget());
        // Measuring needs a stage, and the indicator has none until the panel
        // takes it, so the first budget is applied when it is mapped.
        this._connectTo(this, 'notify::mapped', () => this._applyWidthBudget());
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

        // The leading slot is the phone's reception when Relay knows it, and the
        // phone itself when it does not. Nothing is invented to fill it: the
        // bars appear on their own the day a Relay capability reports signal.
        const showsSignal = connected && status.signalLevel !== null;
        this._deviceIcon.gicon = showsSignal
            ? themedIcon(networkIconNames(status))
            : themedIcon(status !== null && status.deviceType !== 'desktop'
                ? ['phone-symbolic', 'smartphone-symbolic', 'computer-symbolic']
                : ['computer-symbolic', 'phone-symbolic']);

        if (!connected) {
            this._network.box.hide();
            this._battery.box.hide();
            this._notifications.box.hide();
            this._messages.box.hide();
        } else {
            this._renderNetwork(status, showsSignal);
            this._renderBattery(status);
            this._renderAttention(status);
        }

        // Offline is stated in words as well as by the pill shrinking, so it
        // never rests on a shade of grey alone.
        const offline = this._serviceAvailable && status !== null && !connected;
        if (offline)
            this._stateLabel.text = _('Offline');
        this._stateLabel.visible = offline;

        this._box.opacity = connected ? FULL_OPACITY : MUTED_OPACITY;
        if (connected && !this._wasConnected)
            this._greet();
        this._wasConnected = connected;

        this.accessible_name = accessibleName(status, this._serviceAvailable, _);
        this._renderMenu();
        this._applyWidthBudget();
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
        expandActor(this._battery.box);
    }

    /**
     * Draws the network's name beside the bars.
     *
     * When the bars are already the pill's leading icon there is no second icon
     * here — just the label that says which network they belong to.
     *
     * @param {object} status - a normalized status
     * @param {boolean} showsSignal - whether the leading icon is already the bars
     */
    _renderNetwork(status, showsSignal) {
        if (status.networkLabel === null) {
            this._network.box.hide();
            return;
        }
        this._network.icon.visible = !showsSignal;
        if (!showsSignal)
            this._network.icon.gicon = themedIcon(networkIconNames(status));
        setLabelText(this._network.label, status.networkLabel);
        expandActor(this._network.box);
    }

    /**
     * Draws the counts that make the pill grow.
     *
     * Zero is a real answer and the honest way to draw it is to say nothing at
     * all, so a settled phone leaves the panel exactly as it found it.
     */
    _renderAttention(status) {
        const segments = [
            [this._notifications, status.notificationCount, ['preferences-system-notifications-symbolic', 'user-available-symbolic']],
            [this._messages, status.unreadMessageCount, ['mail-unread-symbolic', 'user-available-symbolic']],
        ];

        for (const [segment, count, icons] of segments) {
            // The pill stays open for as long as the count stands, and closes
            // again only once the user has actually dealt with it.
            if (count === null || count === 0) {
                collapseActor(segment.box);
                continue;
            }
            segment.icon.gicon = themedIcon(icons);
            setLabelText(segment.label, unreadLabel(count));
            expandActor(segment.box);
        }

        if (needsAttention(status))
            this._box.add_style_class_name('relay-attentive');
        else
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
            this._headerIcon.gicon = this._deviceIcon.gicon;
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

    /**
     * Keeps the pill inside a share of the panel.
     *
     * There is very little to give up by design — the phone's name lives in the
     * menu, not the panel — so this only sheds the text beside an icon, and
     * never the icons that say which phone the pill is about.
     */
    _applyWidthBudget() {
        if (!this.is_mapped())
            return;

        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor || 1;
        const monitor = Main.layoutManager.primaryMonitor;
        const monitorWidth = monitor ? monitor.width / scale : MAX_PANEL_WIDTH;
        const budget = Math.max(MIN_PANEL_WIDTH, Math.min(MAX_PANEL_WIDTH, Math.round(monitorWidth * PANEL_WIDTH_SHARE)));

        // Reverse importance: the network's label goes before the battery's,
        // and no icon is ever dropped.
        const reducers = [
            () => this._network.label.hide(),
            () => this._battery.label.hide(),
        ];

        for (const reduce of reducers) {
            const [, natural] = this._box.get_preferred_width(-1);
            if (natural / scale <= budget)
                return;
            reduce();
        }
    }

    _onDestroy() {
        for (const [object, handlerId] of this._handlerIds)
            object.disconnect(handlerId);
        this._handlerIds = [];
    }
});

export default class RelayPhonePillExtension extends Extension {
    enable() {
        this._cancellable = new Gio.Cancellable();
        this._proxy = null;
        this._signalId = 0;
        this._indicator = new RelayPhoneIndicator(this);
        Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');

        // Relay is an ordinary desktop app, not a bus-activated service. The
        // pill therefore follows the name: it comes alive when Relay starts and
        // falls back to an offline state when Relay quits, without reconnect
        // loops in between.
        this._watchId = Gio.bus_watch_name(
            Gio.BusType.SESSION,
            BUS_NAME,
            Gio.BusNameWatcherFlags.NONE,
            () => this._connectService(),
            () => this._disconnectService());

        // Owning this name is how Relay knows the panel is presenting it, and
        // therefore that it should not also sit in the notification area.
        this._surfaceOwnerId = Gio.bus_own_name(
            Gio.BusType.SESSION,
            SURFACE_BUS_NAME,
            Gio.BusNameOwnerFlags.REPLACE,
            null, null, null);
    }

    disable() {
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
                if (cancellable !== this._cancellable || this._indicator === null)
                    return;

                this._releaseProxy();
                this._proxy = proxy;
                this._signalId = proxy.connect('g-signal', (_p, _sender, name, parameters) => {
                    if (name === 'PhoneStatusChanged')
                        this._applyStatusVariant(parameters);
                });
                this._requestStatus();
            });
    }

    _requestStatus() {
        this._proxy?.call('GetPhoneStatus', null, Gio.DBusCallFlags.NONE, -1, this._cancellable, (proxy, result) => {
            try {
                this._applyStatusVariant(proxy.call_finish(result));
            } catch (error) {
                if (!error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    console.debug(`Relay: could not read the phone status: ${error.message}`);
            }
        });
    }

    /**
     * @param {GLib.Variant} parameters - a `(a{sv})` payload
     */
    _applyStatusVariant(parameters) {
        if (this._indicator === null)
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
        this._indicator.setStatus(status, true);
    }

    _disconnectService() {
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
