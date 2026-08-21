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
    batteryMenuLabel,
    batterySlotState,
    bellIconNames,
    bellState,
    chargeAnimationState,
    needsAttention,
    normalizePhoneStatus,
    bellRestingOpacity,
    bellRingDuration,
    bellRingKeyframes,
    shouldRingBell,
    batteryPanelLabel,
    networkGenerationLabel,
    signalIconNames,
    signalQualityLabel,
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
/* How warm the bell is allowed to get at the peak of a ring. Well short of a
 * solid coral glyph, and gone again within half a second. */
const BELL_RING_WARMTH = 200;

const FULL_OPACITY = 255;
const MUTED_OPACITY = 155;
const SECONDARY_OPACITY = 180;
const INACTIVE_BELL_OPACITY = 191;
/* Charging warmth: fade up, fade back, then rest. One pass reads as a pulse of
 * energy arriving; a continuous loop would read as a spinner. */
const CHARGE_FADE_MS = 900;
const CHARGE_REST_MS = 800;

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

/** Custom dropdown row for cellular/WiFi network status with 4-bar indicator. */
const NetworkRow = GObject.registerClass(
class RelayNetworkRow extends PopupMenu.PopupBaseMenuItem {
    _init(label) {
        super._init({reactive: false, can_focus: false, style_class: 'popup-menu-item relay-info-row relay-network-row'});

        this._label = new St.Label({text: label, style_class: 'relay-info-label', y_align: Clutter.ActorAlign.CENTER, opacity: SECONDARY_OPACITY});

        this._valueBox = new St.BoxLayout({style_class: 'relay-network-value-box', y_align: Clutter.ActorAlign.CENTER});

        this._badge = new St.Label({style_class: 'relay-network-badge', y_align: Clutter.ActorAlign.CENTER});
        this._badge.hide();

        this._carrier = new St.Label({style_class: 'relay-network-carrier', y_align: Clutter.ActorAlign.CENTER});
        this._carrier.clutter_text.ellipsize = Pango.EllipsizeMode.END;

        // The same native cellular icon the top panel shows, so the dropdown
        // and the panel never present two different drawings of one reading.
        this._signalIcon = new St.Icon({style_class: 'relay-signal-icon', y_align: Clutter.ActorAlign.CENTER});
        this._signalLevel = null;

        this._quality = new St.Label({style_class: 'relay-info-value relay-signal-quality', y_align: Clutter.ActorAlign.CENTER});

        this._valueBox.add_child(this._badge);
        this._valueBox.add_child(this._carrier);
        this._valueBox.add_child(this._signalIcon);
        this._valueBox.add_child(this._quality);

        this.add_child(this._label);
        this.add_child(new St.Widget({x_expand: true}));
        this.add_child(this._valueBox);
    }

    setNetwork(networkKind, networkLabel, signalLevel) {
        this._signalLevel = signalLevel;
        this._signalIcon.gicon = themedIcon(signalIconNames({networkKind, signalLevel, connected: true}, true));

        if (networkKind && networkKind !== 'none' && networkKind !== 'unknown') {
            this._badge.text = networkKind.toUpperCase();
            this._badge.show();
        } else {
            this._badge.hide();
        }

        if (networkLabel) {
            this._carrier.text = networkLabel;
            this._carrier.show();
        } else {
            this._carrier.hide();
        }

        this._quality.text = signalQualityLabel(signalLevel, _);
    }
});

/**
 * The Relay pill in the top panel, plus the menu behind it.
 *
 * Three permanent slots — signal bars, battery, notification bell — stay
 * allocated at all times while a phone is selected. No slot disappears or
 * shifts position due to normal state changes. The layout is calm and spatially
 * stable.
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
        this._signalLevel = null;

        this.add_style_class_name('relay-pill');

        // Three tight groups rather than five loose widgets: network, power,
        // notifications. Icons stay stock `system-status-icon`s so their size
        // still comes from the shell theme and follows the user's font scale;
        // only the spacing between them is Relay's, because the native 4px icon
        // margin cannot express "tight pair, loose group".
        this._box = new St.BoxLayout({style_class: 'relay-cluster', y_align: Clutter.ActorAlign.CENTER});
        this.add_child(this._box);

        // ── Network: [signal] LTE ───────────────────────────────────────
        this._networkGroup = new St.BoxLayout({style_class: 'relay-group', y_align: Clutter.ActorAlign.CENTER});
        this._signalIcon = new St.Icon({style_class: 'system-status-icon', y_align: Clutter.ActorAlign.CENTER});
        this._networkLabel = new St.Label({
            style_class: 'relay-panel-label',
            y_align: Clutter.ActorAlign.CENTER,
            // Quieter than the charge percentage: the generation is context,
            // the battery reading is the thing being glanced at. Done with
            // opacity rather than a colour so it holds in any shell theme.
            opacity: SECONDARY_OPACITY,
        });
        this._networkGroup.add_child(this._signalIcon);
        this._networkGroup.add_child(this._networkLabel);
        this._box.add_child(this._networkGroup);

        // ── Power: [battery] 55% ────────────────────────────────────────
        this._batteryCharging = false;
        this._batteryChargeAnimated = false;
        this._chargeRunning = false;
        this._chargeRestId = 0;

        this._batteryGroup = new St.BoxLayout({style_class: 'relay-group', y_align: Clutter.ActorAlign.CENTER});

        // Two copies of the same native icon, one tinted warm and normally
        // invisible. Charging fades the warm copy in and out over the top, so
        // the icon on screen is always the stock GNOME artwork — and the
        // percentage beside it never moves.
        this._batteryStack = new St.Widget({
            layout_manager: new Clutter.BinLayout(),
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._batteryIcon = new St.Icon({style_class: 'system-status-icon'});
        this._batteryWarmIcon = new St.Icon({style_class: 'system-status-icon relay-charge-warm', opacity: 0});
        this._batteryStack.add_child(this._batteryIcon);
        this._batteryStack.add_child(this._batteryWarmIcon);

        this._batteryLabel = new St.Label({style_class: 'relay-panel-label', y_align: Clutter.ActorAlign.CENTER});
        this._batteryGroup.add_child(this._batteryStack);
        this._batteryGroup.add_child(this._batteryLabel);
        this._box.add_child(this._batteryGroup);

        // ── Notifications: [bell] ───────────────────────────────────────
        // The bell is never given a permanent marker. Unread is carried by the
        // glyph being fuller, and a new one is announced by a single ring that
        // ends exactly where it started.
        this._bellActive = false;
        this._bellStack = new St.Widget({
            layout_manager: new Clutter.BinLayout(),
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._bellIcon = new St.Icon({style_class: 'system-status-icon'});
        // A coral copy, invisible except during the ring itself. Symbolic icon
        // colour comes from CSS and cannot be eased, so the warmth is a second
        // icon fading over the first — the same trick the battery uses.
        this._bellWarmIcon = new St.Icon({style_class: 'system-status-icon relay-bell-warm', opacity: 0});
        this._bellStack.add_child(this._bellIcon);
        this._bellStack.add_child(this._bellWarmIcon);
        // A bell swings from where it hangs, not from the middle of its box.
        this._bellStack.set_pivot_point(0.5, 0.1);
        this._box.add_child(this._bellStack);

        // ── State label (offline / "Relay") ─────────────────────────────
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
        this._networkRow = new NetworkRow(_('Network'));
        this._notificationsRow = new InfoRow(_('Notifications'), '');
        this._messagesRow = new InfoRow(_('Messages'), '');
        for (const row of [this._batteryRow, this._networkRow, this._notificationsRow, this._messagesRow])
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

        // ── Network ─────────────────────────────────────────────────────
        // The same native cellular family the shell's own network indicator
        // uses. Unknown stays unknown rather than being drawn as zero bars.
        const showSignal = status === null || status.showSignal !== false;
        this._signalIcon.gicon = themedIcon(signalIconNames(status, connected));
        this._signalIcon.visible = showSignal;

        // The generation only. Signal quality is wording for the dropdown; in
        // the panel it would just be a long word that changes on its own.
        const showNetLabel = status !== null && status.showNetworkLabel !== false;
        const generation = showNetLabel ? networkGenerationLabel(status, connected) : null;
        this._networkLabel.text = generation ?? '';
        this._networkLabel.visible = generation !== null;
        this._networkGroup.visible = this._signalIcon.visible || this._networkLabel.visible;

        // ── Battery ─────────────────────────────────────────────────────
        this._renderBattery(status);

        // ── Notification bell ───────────────────────────────────────────
        this._renderBell(status);

        if (!connected)
            this._clearNotificationAttention();

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

    /**
     * Fades a warm copy of the battery icon in and out while charging.
     *
     * The base icon is never touched, so what is on screen stays stock GNOME
     * artwork: only a tinted duplicate above it changes opacity. Nothing runs
     * at all when the phone is not charging or animations are off.
     *
     * @param {boolean} wanted - whether the warmth pulse should be running
     */
    _syncChargeWarmth(wanted) {
        if (!wanted) {
            this._chargeRunning = false;
            if (this._chargeRestId !== 0) {
                GLib.Source.remove(this._chargeRestId);
                this._chargeRestId = 0;
            }
            this._batteryWarmIcon.remove_all_transitions();
            this._batteryWarmIcon.opacity = 0;
            return;
        }

        if (this._chargeRunning)
            return;
        this._chargeRunning = true;
        this._runChargePulse();
    }

    _runChargePulse() {
        if (this._destroyed || !this._chargeRunning)
            return;

        this._batteryWarmIcon.remove_all_transitions();
        this._batteryWarmIcon.opacity = 0;
        this._batteryWarmIcon.ease({
            opacity: FULL_OPACITY,
            duration: CHARGE_FADE_MS,
            mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onComplete: () => {
                if (this._destroyed || !this._chargeRunning)
                    return;
                this._batteryWarmIcon.ease({
                    opacity: 0,
                    duration: CHARGE_FADE_MS,
                    mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
                    onComplete: () => this._scheduleChargeRest(),
                });
            },
        });
    }

    _scheduleChargeRest() {
        if (this._destroyed || !this._chargeRunning)
            return;

        this._chargeRestId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, CHARGE_REST_MS, () => {
            this._chargeRestId = 0;
            if (!this._destroyed && this._chargeRunning)
                this._runChargePulse();
            return GLib.SOURCE_REMOVE;
        });
    }

    /**
     * Renders the battery as the stock GNOME battery-level icon.
     *
     * The panel stays icon-only: the exact percentage and the charging wording
     * live one click away in the dropdown, which is where GNOME puts its own.
     *
     * @param {object|null} status - a normalized status
     */
    _renderBattery(status) {
        const state = batterySlotState(status);

        if (!state.visible) {
            // A phone that has gone away must not leave the pulse running.
            this._syncChargeWarmth(false);
            this._batteryGroup.hide();
            return;
        }

        const icon = themedIcon(state.icons);
        this._batteryIcon.gicon = icon;
        this._batteryWarmIcon.gicon = icon;

        // The reading is the useful part of this group, so it is stated rather
        // than left to be inferred from a five-step icon. An unknown charge
        // shows no label at all instead of a placeholder.
        const showPercent = status === null || status.showBatteryPercentage !== false;
        const percentage = showPercent ? batteryPanelLabel(status) : null;
        this._batteryLabel.text = percentage ?? '';
        this._batteryLabel.visible = percentage !== null;

        const chargingAllowed = status === null || status.chargingAnimationEnabled !== false;
        const charge = chargeAnimationState(status, animationsEnabled() && chargingAllowed);
        this._batteryCharging = charge.charging;
        this._batteryChargeAnimated = charge.animated;

        this._batteryGroup.opacity = state.muted ? SECONDARY_OPACITY : FULL_OPACITY;
        this._batteryGroup.show();
        this._syncChargeWarmth(charge.animated);
    }

    /**
     * Renders the notification bell slot. The bell is always visible while a
     * phone is connected — hollow at zero notifications, filled at 1+.
     */
    _renderBell(status) {
        const bell = bellState(status);

        if (!bell.visible || (status !== null && status.showNotifications === false)) {
            this._bellStack.hide();
            return;
        }

        const icon = themedIcon(bellIconNames());
        this._bellIcon.gicon = icon;
        this._bellWarmIcon.gicon = icon;
        this._bellStack.show();

        // The glyph is the ordinary panel foreground in both states; unread is
        // simply a fuller one. No colour survives past the ring.
        this._bellIcon.opacity = bellRestingOpacity(bell.active);
        this._bellActive = bell.active;

        const count = bell.count;
        const ring = shouldRingBell(this._previousNotificationCount, count, animationsEnabled());
        this._previousNotificationCount = count;

        // The generation is bumped only when a ring actually starts. Bumping it
        // on every render would let an ordinary battery update land mid-swing,
        // abandon the ring and leave the bell tilted in the panel.
        if (ring)
            this._ringBell();

        if (needsAttention(status))
            this._box.add_style_class_name('relay-attentive');
        else
            this._box.remove_style_class_name('relay-attentive');
    }

    /**
     * One finite bell ring: a decaying swing that always ends level.
     *
     * The warm copy fades up over the first half of the swing and back down
     * over the second, so the colour is gone by the time the glyph stops.
     *
     */
    _ringBell() {
        const generation = ++this._notificationPulseGeneration;
        const steps = bellRingKeyframes();
        this._bellStack.remove_all_transitions();
        this._bellWarmIcon.remove_all_transitions();
        this._bellStack.rotation_angle_z = 0;

        const half = Math.round(bellRingDuration() / 2);
        this._bellWarmIcon.opacity = 0;
        this._bellWarmIcon.ease({
            opacity: BELL_RING_WARMTH,
            duration: half,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onComplete: () => {
                if (this._destroyed || generation !== this._notificationPulseGeneration)
                    return;
                this._bellWarmIcon.ease({
                    opacity: 0,
                    duration: bellRingDuration() - half,
                    mode: Clutter.AnimationMode.EASE_IN_QUAD,
                });
            },
        });

        this._runBellRing(steps, 0, generation);
    }

    _runBellRing(steps, index, generation) {
        if (this._destroyed)
            return;
        if (generation !== this._notificationPulseGeneration) {
            // A newer ring has taken over and has already reset the angle.
            return;
        }
        if (index >= steps.length) {
            // Whatever happened on the way, the bell finishes level and neutral.
            this._bellStack.rotation_angle_z = 0;
            this._bellWarmIcon.opacity = 0;
            return;
        }
        this._bellStack.ease({
            rotation_angle_z: steps[index].angle,
            duration: steps[index].duration,
            mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onComplete: () => this._runBellRing(steps, index + 1, generation),
        });
    }

    _clearNotificationAttention() {
        this._previousNotificationCount = 0;
        this._notificationPulseGeneration += 1;
        this._bellStack.remove_all_transitions();
        this._bellStack.rotation_angle_z = 0;
        this._bellWarmIcon.remove_all_transitions();
        this._bellWarmIcon.opacity = 0;
        // The bell stays visible at secondary opacity when connected with
        // nothing unread; it is hidden only when disconnected.
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
        if (showBattery)
            this._batteryRow.setValue(batteryMenuLabel(status, _));

        // Network row: native cellular icon, carrier badge and quality wording.
        const showNetwork = status !== null && (status.networkLabel !== null || status.signalLevel !== null || status.networkKind !== null);
        this._networkRow.visible = showNetwork;
        if (showNetwork)
            this._networkRow.setNetwork(status.networkKind, status.networkLabel, status.signalLevel);

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
        // A fade rather than a sprung scale: EASE_OUT_BACK overshoots, which at
        // panel size reads as the icons bouncing.
        this._box.remove_all_transitions();
        this._box.set_scale(1, 1);
        this._box.opacity = MUTED_OPACITY;
        this._box.ease({
            opacity: FULL_OPACITY,
            duration: APPEAR_MS,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        });
    }

    _onDestroy() {
        this._destroyed = true;
        this._syncChargeWarmth(false);
        this._notificationPulseGeneration += 1;
        this._bellStack.remove_all_transitions();
        this._bellWarmIcon.remove_all_transitions();
        this._batteryWarmIcon.remove_all_transitions();
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
