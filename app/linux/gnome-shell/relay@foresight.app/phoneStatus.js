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
export const SIGNAL_BAR_COUNT = 4;

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
 * @param {object} status - a normalized status
 * @returns {string[]} network icon names, most specific first
 */
export function networkIconNames(status) {
    const bars = ['none', 'weak', 'ok', 'good', 'excellent'];
    // Unknown must look unknown. In particular, never turn a missing reading
    // into the visually plausible but false "good" state.
    const strength = status?.signalLevel === null || status?.signalLevel === undefined ? 'none' : bars[status.signalLevel];
    if (status?.networkKind === 'wifi') {
        return [`network-wireless-signal-${strength}-symbolic`, 'network-wireless-symbolic'];
    }
    return [`network-cellular-signal-${strength}-symbolic`, 'network-cellular-symbolic', 'network-offline-symbolic'];
}

/**
 * Per-bar active/inactive state for a custom four-bar signal indicator.
 *
 * All four geometric bars are always present. This function determines which
 * ones are drawn at full emphasis ("active") versus muted ("inactive"). The
 * result always has exactly {@link SIGNAL_BAR_COUNT} entries.
 *
 * @param {number|null|undefined} signalLevel - 0–4, or null/undefined for unknown
 * @returns {boolean[]} per-bar active state, shortest bar first
 */
export function signalBarStates(signalLevel) {
    const level = typeof signalLevel === 'number' && Number.isFinite(signalLevel) && signalLevel >= 0 && signalLevel <= 4
        ? signalLevel
        : 0;
    const states = [];
    for (let i = 1; i <= SIGNAL_BAR_COUNT; i++)
        states.push(i <= level);
    return states;
}

/**
 * Presentation state for the battery slot.
 *
 * The battery slot is always present while a phone is selected. When the
 * reading is unavailable, the slot shows a battery outline with a placeholder
 * label instead of disappearing.
 *
 * @param {object|null} status - a normalized status
 * @returns {object} `{visible, icons, label, muted}` — slot state
 */
export function batterySlotState(status) {
    if (status === null || !status.connected)
        return {visible: false, icons: ['battery-missing-symbolic', 'battery-symbolic'], label: '', muted: true};

    if (status.batteryPercentage === null)
        return {visible: true, icons: ['battery-missing-symbolic', 'battery-symbolic'], label: '\u2014%', muted: true};

    if (status.batteryIsStale)
        return {visible: true, icons: batteryIconNames(status), label: `${status.batteryPercentage}%`, muted: true};

    return {visible: true, icons: batteryIconNames(status), label: `${status.batteryPercentage}%`, muted: false};
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
    if (status === null || !status.connected)
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
 * Opacity targets for one finite notification-attention event.
 *
 * Keeping this policy pure makes the important properties testable without a
 * running Shell: only an increase pulses, reduced motion has no transitions,
 * and the final target is always fully visible. The actor owns the timing.
 *
 * @param {number|null} previousCount - previous standing count
 * @param {number|null} currentCount - current standing count
 * @param {boolean} animations - whether Shell animations are enabled
 * @returns {number[]} finite opacity targets
 */
export function notificationPulseOpacities(previousCount, currentCount, animations) {
    const previous = previousCount ?? 0;
    const current = currentCount ?? 0;
    if (!animations || current <= 0 || current <= previous)
        return [];
    return [72, 255, 72, 255, 72, 255];
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
