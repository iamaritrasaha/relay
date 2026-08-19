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
    const hasNetwork = networkKind !== null || networkLabel !== null;

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
        // A signal bucket with no network to belong to would draw as bars for
        // nothing, so it only survives alongside the network fields.
        signalLevel: hasNetwork ? boundedInt(raw.signalLevel, 0, 4) : null,
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
    const strength = status.signalLevel === null ? 'good' : bars[status.signalLevel];
    if (status.networkKind === 'wifi') {
        return [`network-wireless-signal-${strength}-symbolic`, 'network-wireless-symbolic'];
    }
    return [`network-cellular-signal-${strength}-symbolic`, 'network-cellular-symbolic'];
}

/**
 * @param {number} count - unread messages or standing notifications
 * @returns {string} the count as drawn in the panel
 */
export function unreadLabel(count) {
    return count > MAX_LITERAL_UNREAD ? `${MAX_LITERAL_UNREAD}+` : `${count}`;
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
        return _t('Relay, not running');
    if (status === null)
        return _t('Relay, no phone connected');

    const parts = [_t('Relay'), status.displayName, status.connected ? _t('connected') : _t('offline')];

    if (hasLiveBattery(status)) {
        parts.push(`${_t('battery')} ${status.batteryPercentage} ${_t('percent')}`);
        if (status.batteryIsFull)
            parts.push(_t('charged'));
        else if (status.batteryIsCharging)
            parts.push(_t('charging'));
    }

    if (status.networkLabel !== null)
        parts.push(status.networkLabel);

    if (status.notificationCount !== null && status.notificationCount > 0)
        parts.push(`${status.notificationCount} ${_t('notifications')}`);

    if (status.unreadMessageCount !== null && status.unreadMessageCount > 0)
        parts.push(`${status.unreadMessageCount} ${_t('unread messages')}`);

    return parts.join(', ');
}
