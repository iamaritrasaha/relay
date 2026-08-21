/* Relay — GNOME Shell integration
 *
 * Pure helpers for turning Relay's shell snapshot into something the panel can
 * draw. Nothing in this file touches Clutter, St or the bus, so it stays
 * readable and can be exercised on its own.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/** Highest unread count rendered literally; anything above collapses to "99+". */
const MAX_LITERAL_UNREAD = 99;

/** Number of individual bars in the signal indicator. */
/* Charging warmth: fade up, fade back, then rest. */
export const CHARGE_FADE_MS = 900;
export const CHARGE_REST_MS = 800;
export const CHARGE_CYCLE_MS = CHARGE_FADE_MS * 2 + CHARGE_REST_MS;

/* Signal levels 0..4, in the order the native icon family names them. */
export const SIGNAL_STRENGTHS = ['none', 'weak', 'ok', 'good', 'excellent'];

/**
 * Reads a field only when it has the expected type.
 *
 * Relay is the only writer of these snapshots, but the panel lives inside
 * gnome-shell: a malformed value has to become "unknown" rather than an
 * exception, so every field is checked before it is believed.
 *
 * @param {object} raw - decoded snapshot
 * @param {string} key - field name
 * @param {string} type - expected `typeof`
 * @returns {*} the value, or undefined
 */
function field(raw, key, type) {
    const value = raw[key];
    // eslint-disable-next-line valid-typeof
    return typeof value === type ? value : undefined;
}

/**
 * @param {*} value - candidate number
 * @param {number} min - inclusive lower bound
 * @param {number} max - inclusive upper bound
 * @returns {number|null} the value when it is a whole number in range
 */
function boundedInt(value, min, max) {
    if (typeof value !== 'number' || !Number.isFinite(value))
        return null;
    const rounded = Math.round(value);
    return rounded >= min && rounded <= max ? rounded : null;
}

/**
 * Validates a decoded snapshot.
 *
 * Out-of-range values are dropped rather than clamped: a clamped number would
 * be indistinguishable from a real reading. An absent optional field means
 * Relay does not know, which is never the same as a zero value.
 *
 * @param {object|null} raw - snapshot decoded from the bus
 * @returns {object|null} a validated status, or null when there is no phone
 */
export function normalizePhoneStatus(raw) {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw))
        return null;

    const deviceId = field(raw, 'deviceId', 'string');
    if (!deviceId)
        return null;

    const name = (field(raw, 'displayName', 'string') ?? '').trim();
    const batteryPercentage = boundedInt(raw.batteryPercentage, 0, 100);
    const networkKind = (field(raw, 'networkKind', 'string') ?? '').trim() || null;
    const networkLabel = (field(raw, 'networkLabel', 'string') ?? '').trim() || null;
    return Object.freeze({
        deviceId,
        displayName: name || 'Phone',
        deviceType: field(raw, 'deviceType', 'string') ?? 'mobile',
        connected: field(raw, 'connected', 'boolean') ?? false,
        paired: field(raw, 'paired', 'boolean') ?? false,
        batteryPercentage,
        batteryIsCharging: batteryPercentage === null ? null : field(raw, 'batteryIsCharging', 'boolean') ?? false,
        batteryIsFull: batteryPercentage === null ? null : field(raw, 'batteryIsFull', 'boolean') ?? false,
        batteryIsStale: batteryPercentage === null ? false : field(raw, 'batteryIsStale', 'boolean') ?? false,
        networkKind,
        networkLabel,
        // Signal is independently useful. A future connectivity provider may
        // know the level before it knows a carrier label, and the panel's
        // network-first slot can present that honest partial answer.
        signalLevel: boundedInt(raw.signalLevel, 0, 4),
        unreadMessageCount: boundedInt(raw.unreadMessageCount, 0, Number.MAX_SAFE_INTEGER),
        notificationCount: boundedInt(raw.notificationCount, 0, Number.MAX_SAFE_INTEGER),
        supportsFindDevice: field(raw, 'supportsFindDevice', 'boolean') ?? false,
        supportsClipboard: field(raw, 'supportsClipboard', 'boolean') ?? false,
        supportsMessages: field(raw, 'supportsMessages', 'boolean') ?? false,
        supportsNotifications: field(raw, 'supportsNotifications', 'boolean') ?? false,
        showNetworkLabel: field(raw, 'showNetworkLabel', 'boolean') ?? true,
        showBatteryPercentage: field(raw, 'showBatteryPercentage', 'boolean') ?? true,
        showNotifications: field(raw, 'showNotifications', 'boolean') ?? true,
        chargingAnimationEnabled: field(raw, 'chargingAnimationEnabled', 'boolean') ?? true,
        showSignal: field(raw, 'showSignal', 'boolean') ?? true,
        phoneCount: boundedInt(raw.phoneCount, 1, 999) ?? 1,
    });
}

/**
 * Picks the battery icon that matches a reading.
 *
 * @param {object} status - a normalized status
 * @returns {string[]} icon names, most specific first
 */
export function batteryIconNames(status) {
    if (status.batteryPercentage === null)
        return ['battery-missing-symbolic', 'battery-symbolic'];

    const level = Math.round(status.batteryPercentage / 10) * 10;
    if (status.batteryIsFull)
        return ['battery-level-100-charged-symbolic', 'battery-level-100-charging-symbolic', 'battery-symbolic'];
    if (status.batteryIsCharging)
        return [`battery-level-${level}-charging-symbolic`, 'battery-level-100-charging-symbolic', 'battery-symbolic'];
    return [`battery-level-${level}-symbolic`, 'battery-symbolic'];
}

/**
 * Icon chain for the network strength of a phone.
 *
 * Uses the same `network-cellular-signal-*` family the shell's own network
 * indicator draws, so Relay's reading and GNOME's sit at identical weight.
 *
 * @param {object|null} status - a normalized status
 * @returns {string[]} icon names, most specific first
 */
export function networkIconNames(status) {
    const level = status?.signalLevel;
    const known = typeof level === 'number' && level >= 0 && level < SIGNAL_STRENGTHS.length;
    const strength = known ? SIGNAL_STRENGTHS[level] : null;

    if (status?.networkKind === 'wifi') {
        return strength === null
            ? ['network-wireless-acquiring-symbolic', 'network-wireless-symbolic']
            : [`network-wireless-signal-${strength}-symbolic`, 'network-wireless-symbolic'];
    }

    // A missing reading is never drawn as "none": zero bars is itself a
    // reading, and claiming it would be inventing one.
    if (strength === null)
        return ['network-cellular-acquiring-symbolic', 'network-cellular-symbolic', 'network-cellular-signal-none-symbolic'];

    return [`network-cellular-signal-${strength}-symbolic`, 'network-cellular-symbolic', 'network-offline-symbolic'];
}

/**
 * Icon chain for the top panel's signal slot.
 *
 * A phone that is not connected is stated as offline rather than as a phone
 * with no bars, which is a different fact.
 *
 * @param {object|null} status - a normalized status
 * @param {boolean} connected - whether a live link exists
 * @returns {string[]} icon names, most specific first
 */
export function signalIconNames(status, connected) {
    if (status === null || connected !== true)
        return ['network-cellular-offline-symbolic', 'network-cellular-signal-none-symbolic', 'network-cellular-symbolic'];

    return networkIconNames(status);
}

/**
 * Icon chain for the notification bell.
 *
 * One glyph for both states: unread is said with colour, not by swapping the
 * artwork for a different shape.
 *
 * @returns {string[]} icon names, most specific first
 */
export function bellIconNames() {
    return ['preferences-system-notifications-symbolic', 'notification-symbolic', 'user-available-symbolic'];
}

/**
 * Presentation state for the battery slot in the top panel.
 *
 * The slot disappears only when no phone is selected. When a selected phone's
 * reading is unavailable, the slot shows a battery outline with a placeholder
 * label instead of disappearing.
 *
 * @param {object|null} status - a normalized status
 * @returns {object} `{visible, icons, label, muted}` — slot state
 */
export function batterySlotState(status) {
    if (status === null || !status.connected)
        return {visible: false, icons: ['battery-missing-symbolic', 'battery-symbolic'], label: '', muted: true};

    const showPercent = status.showBatteryPercentage !== false;

    if (status.batteryPercentage === null)
        return {visible: true, icons: ['battery-missing-symbolic', 'battery-symbolic'], label: showPercent ? '\u2014%' : '', muted: true};

    if (status.batteryIsStale)
        return {visible: true, icons: batteryIconNames(status), label: showPercent ? `${status.batteryPercentage}%` : '', muted: true};

    return {visible: true, icons: batteryIconNames(status), label: showPercent ? `${status.batteryPercentage}%` : '', muted: false};
}

/**
 * Presentation state for the notification bell slot.
 *
 * The bell is always visible while a phone is selected: hollow/muted when no
 * notifications are standing, filled/active when at least one is.
 *
 * @param {object|null} status - a normalized status
 * @returns {object} `{visible, active, count}` — slot state
 */
export function bellState(status) {
    if (status === null || !status.connected || status.showNotifications === false)
        return {visible: false, active: false, count: 0};

    const count = status.notificationCount ?? 0;
    return {visible: true, active: count > 0, count};
}

/**
 * @param {number} count - unread messages or standing notifications
 * @returns {string} the count as drawn in the panel
 */
export function unreadLabel(count) {
    return count > MAX_LITERAL_UNREAD ? `${MAX_LITERAL_UNREAD}+` : `${count}`;
}

/**
 * Whether a new notification should ring the bell.
 *
 * Only an increase rings, and only when the shell is animating: a count that
 * stands still, falls, or arrives on a desktop with reduced motion must not
 * move anything.
 *
 * @param {number|null} previousCount - previous standing count
 * @param {number|null} currentCount - current standing count
 * @param {boolean} animations - whether Shell animations are enabled
 * @returns {boolean} whether to play the one-shot ring
 */
export function shouldRingBell(previousCount, currentCount, animations) {
    const previous = previousCount ?? 0;
    const current = currentCount ?? 0;
    return animations === true && current > 0 && current > previous;
}

/**
 * The one-shot bell ring, as angles in degrees with the time to reach each.
 *
 * A decaying swing rather than a wobble: the first throw is the largest and
 * every one after it is smaller, which is how a struck bell actually settles.
 * The sequence always ends at zero so the glyph cannot be left tilted.
 *
 * @returns {object[]} `{angle, duration}` steps, in order
 */
export function bellRingKeyframes() {
    return [
        {angle: -6, duration: 90},
        {angle: 6, duration: 120},
        {angle: -3, duration: 100},
        {angle: 2, duration: 90},
        {angle: 0, duration: 80},
    ];
}

/** Total time one ring takes, in milliseconds. */
export function bellRingDuration() {
    return bellRingKeyframes().reduce((total, step) => total + step.duration, 0);
}

/** Opacity of the bell glyph at rest, by whether anything is unread. */
export const BELL_READ_OPACITY = 186;
export const BELL_UNREAD_OPACITY = 255;

/**
 * Resting opacity for the bell.
 *
 * Unread is carried by presence alone — a fuller glyph — rather than by a
 * colour or a badge, so the panel gains no permanent marker.
 *
 * @param {boolean} active - whether anything is unread
 * @returns {number} 0–255 opacity
 */
export function bellRestingOpacity(active) {
    return active ? BELL_UNREAD_OPACITY : BELL_READ_OPACITY;
}

/**
 * Whether something on the phone is asking for the user.
 *
 * This is what makes the pill grow: at rest it stays a phone and a battery, and
 * it only takes more of the panel when there is genuinely something waiting.
 *
 * @param {object|null} status - a normalized status
 * @returns {boolean} true when a count is present and above zero
 */
export function needsAttention(status) {
    if (status === null || !status.connected)
        return false;
    return (status.notificationCount ?? 0) > 0 || (status.unreadMessageCount ?? 0) > 0;
}

/**
 * Whether the panel should draw a battery reading as live.
 *
 * A phone that dropped off keeps its last reading in the menu, but the panel
 * must not go on presenting it as current.
 *
 * @param {object} status - a normalized status
 * @returns {boolean} true when the reading is live
 */
export function hasLiveBattery(status) {
    return status.batteryPercentage !== null && status.connected && !status.batteryIsStale;
}

/**
 * Builds the spoken description of the panel button.
 *
 * Only what is actually known is announced, and never an internal device id.
 *
 * @param {object|null} status - a normalized status, or null
 * @param {boolean} serviceAvailable - whether Relay is running
 * @param {Function} gettext - translation function
 * @returns {string} an accessible name
 */
export function accessibleName(status, serviceAvailable, gettext) {
    const _t = gettext;
    if (!serviceAvailable)
        return _t('Relay phone, not running');
    if (status === null)
        return _t('Relay phone, no phone connected');

    const parts = [_t('Relay phone'), status.displayName, status.connected ? _t('connected') : _t('offline')];

    if (status.connected) {
        const signalNames = [_t('no signal'), _t('weak signal'), _t('fair signal'), _t('good signal'), _t('excellent signal')];
        parts.push(status.signalLevel === null ? _t('signal unknown') : signalNames[status.signalLevel]);
    }

    if (hasLiveBattery(status)) {
        parts.push(`${_t('battery')} ${status.batteryPercentage} ${_t('percent')}`);
        if (status.batteryIsFull)
            parts.push(_t('charged'));
        else if (status.batteryIsCharging)
            parts.push(_t('charging'));
    }

    if (status.networkLabel !== null)
        parts.push(status.networkLabel);

    if (status.notificationCount !== null)
        parts.push(status.notificationCount === 1 ? _t('1 notification') : `${status.notificationCount} ${_t('notifications')}`);

    if (status.unreadMessageCount !== null)
        parts.push(status.unreadMessageCount === 1 ? _t('1 unread message') : `${status.unreadMessageCount} ${_t('unread messages')}`);

    return parts.join(', ');
}

/**
 * Human-readable signal quality label.
 *
 * @param {number|null|undefined} signalLevel - 0–4, or unknown
 * @param {Function} [gettext] - optional translation function
 * @returns {string} signal description
 */
export function signalQualityLabel(signalLevel, gettext) {
    const _t = gettext || (s => s);
    if (signalLevel === null || signalLevel === undefined)
        return _t('Unavailable');
    switch (signalLevel) {
        case 4: return _t('Excellent');
        case 3: return _t('Good');
        case 2: return _t('Fair');
        case 1: return _t('Weak');
        case 0: return _t('No signal');
        default: return _t('Unavailable');
    }
}

/**
 * The one battery line in the dropdown.
 *
 * The charge and its state belong on a single row: splitting them across
 * "Battery" and "Status" made the menu restate the same reading twice.
 *
 * @param {object|null} status - a normalized status
 * @param {Function} gettext - translation function
 * @returns {string} the value for the battery row
 */
export function batteryMenuLabel(status, gettext) {
    const _ = gettext;
    if (status === null || status.batteryPercentage === null)
        return _('Not reported');

    const charge = `${status.batteryPercentage}%`;
    if (status.batteryIsStale || !status.connected)
        return `${charge} \u00b7 ${_('Last known')}`;
    if (status.batteryIsFull)
        return `${charge} \u00b7 ${_('Charged')}`;
    if (status.batteryIsCharging)
        return `${charge} \u00b7 ${_('Charging')}`;
    return charge;
}

/// Whether the battery is charging, and whether that may be animated.
///
/// Charging and animated are separate answers on purpose: a desktop with
/// animations turned off still has to say the phone is charging, it just says
/// it with a static mark instead of a moving one.
///
/// @param {object|null} status - a normalized status
/// @param {boolean} animationsAllowed - whether the shell permits animation
/// @returns {object} `{charging, animated}`
export function chargeAnimationState(status, animationsAllowed) {
    const charging =
        status !== null &&
        status.connected === true &&
        status.batteryIsCharging === true &&
        status.batteryIsStale === false &&
        status.batteryPercentage !== null;

    return {charging, animated: charging && animationsAllowed === true};
}


/**
 * The compact network generation for the top panel: LTE, 5G, 4G and so on.
 *
 * Only what the phone actually reported. Signal *quality* — "Excellent",
 * "Good" — is deliberately not offered here: it is a long word that changes on
 * its own while the user is reading it, which is dropdown material.
 *
 * @param {object|null} status - a normalized status
 * @param {boolean} connected - whether a live link exists
 * @returns {string|null} the label, or null when there is nothing to state
 */
export function networkGenerationLabel(status, connected) {
    if (status === null || connected !== true)
        return null;

    const label = typeof status.networkLabel === 'string' ? status.networkLabel.trim() : '';
    if (label === '')
        return null;

    // A carrier name is not a generation. Anything long is a name, and putting
    // it in the panel is how the cluster ends up as wide as the clock.
    if (label.length > 5)
        return null;

    return label.toUpperCase();
}

/**
 * The battery percentage for the top panel.
 *
 * Absent rather than a placeholder when the charge is unknown: a dash in the
 * panel reads as a reading, and there is none.
 *
 * @param {object|null} status - a normalized status
 * @returns {string|null} e.g. "55%", or null when unknown
 */
export function batteryPanelLabel(status) {
    if (status === null || status.batteryPercentage === null)
        return null;

    return `${status.batteryPercentage}%`;
}
