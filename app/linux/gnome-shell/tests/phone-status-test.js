#!/usr/bin/env gjs -m
/* Relay — GNOME Shell integration
 *
 * Checks the pure part of the panel extension: what it believes about a
 * snapshot, and what it refuses to believe. Run with:
 *
 *     gjs -m app/linux/gnome-shell/tests/phone-status-test.js
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import {
    accessibleName,
    batteryIconNames,
    batterySlotState,
    bellState,
    hasLiveBattery,
    needsAttention,
    networkIconNames,
    notificationPulseOpacities,
    normalizePhoneStatus,
    signalBarStates,
    SIGNAL_BAR_COUNT,
    unreadLabel,
} from '../relay@foresight.app/phoneStatus.js';

let failures = 0;

function check(name, condition) {
    if (condition) {
        print(`  ok   ${name}`);
    } else {
        print(`  FAIL ${name}`);
        failures += 1;
    }
}

const identity = text => text;

const connectedPhone = {
    deviceId: 'kdeconnect:abc',
    displayName: 'Redmi Note 14 Pro',
    deviceType: 'mobile',
    connected: true,
    paired: true,
    batteryIsStale: false,
    supportsFindDevice: true,
    supportsClipboard: true,
    supportsMessages: false,
    supportsNotifications: true,
    phoneCount: 1,
    lastUpdated: 1,
};

print('normalizePhoneStatus');
check('a connected phone survives intact', normalizePhoneStatus(connectedPhone).displayName === 'Redmi Note 14 Pro');
check('a snapshot without a device id is no phone', normalizePhoneStatus({displayName: 'X'}) === null);
check('an empty snapshot is no phone', normalizePhoneStatus({}) === null);
check('a null snapshot is no phone', normalizePhoneStatus(null) === null);
check('a non-object snapshot is no phone', normalizePhoneStatus('nonsense') === null);
check('an array is no phone', normalizePhoneStatus(['nonsense']) === null);
check('an empty name falls back', normalizePhoneStatus({...connectedPhone, displayName: '  '}).displayName === 'Phone');

print('battery');
check('an absent battery stays absent', normalizePhoneStatus(connectedPhone).batteryPercentage === null);
check('an absent battery has no charge state', normalizePhoneStatus(connectedPhone).batteryIsCharging === null);
check('zero percent is a real reading', normalizePhoneStatus({...connectedPhone, batteryPercentage: 0}).batteryPercentage === 0);
check('a full battery is a real reading', normalizePhoneStatus({...connectedPhone, batteryPercentage: 100}).batteryPercentage === 100);
check('an impossible battery is dropped', normalizePhoneStatus({...connectedPhone, batteryPercentage: 400}).batteryPercentage === null);
check('a negative battery is dropped', normalizePhoneStatus({...connectedPhone, batteryPercentage: -5}).batteryPercentage === null);
check('a non-numeric battery is dropped', normalizePhoneStatus({...connectedPhone, batteryPercentage: '67'}).batteryPercentage === null);
check('charging is kept alongside a reading', normalizePhoneStatus({...connectedPhone, batteryPercentage: 67, batteryIsCharging: true}).batteryIsCharging);
check('a live battery is live', hasLiveBattery(normalizePhoneStatus({...connectedPhone, batteryPercentage: 67})));
check('a stale battery is not live', !hasLiveBattery(normalizePhoneStatus({...connectedPhone, batteryPercentage: 67, batteryIsStale: true})));
check('an offline battery is not live', !hasLiveBattery(normalizePhoneStatus({...connectedPhone, connected: false, batteryPercentage: 67})));

print('battery icons');
check('67% picks the 70 step', batteryIconNames(normalizePhoneStatus({...connectedPhone, batteryPercentage: 67}))[0] === 'battery-level-70-symbolic');
check('charging picks a charging icon',
    batteryIconNames(normalizePhoneStatus({...connectedPhone, batteryPercentage: 40, batteryIsCharging: true}))[0] === 'battery-level-40-charging-symbolic');
check('a charged battery reads as charged',
    batteryIconNames(normalizePhoneStatus({...connectedPhone, batteryPercentage: 100, batteryIsCharging: true, batteryIsFull: true}))[0] ===
        'battery-level-100-charged-symbolic');
check('no reading picks the missing icon', batteryIconNames(normalizePhoneStatus(connectedPhone))[0] === 'battery-missing-symbolic');
check('every icon chain has a fallback', batteryIconNames(normalizePhoneStatus(connectedPhone)).length > 1);

print('network');
check('an absent network stays absent', normalizePhoneStatus(connectedPhone).networkLabel === null);
check('a reported network survives', normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', networkLabel: '5G'}).networkLabel === '5G');
check('a signal without a label still survives', normalizePhoneStatus({...connectedPhone, signalLevel: 3}).signalLevel === 3);
check('a signal with a network survives', normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: 3}).signalLevel === 3);
check('an absurd signal is dropped', normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: -1000}).signalLevel === null);
check('unknown signal uses signal-none', networkIconNames(normalizePhoneStatus(connectedPhone))[0] === 'network-cellular-signal-none-symbolic');
for (const [level, name] of ['none', 'weak', 'ok', 'good', 'excellent'].entries()) {
    check(`signal ${level} picks ${name}`, networkIconNames(normalizePhoneStatus({...connectedPhone, signalLevel: level}))[0] ===
        `network-cellular-signal-${name}-symbolic`);
}
check('cellular picks a cellular icon',
    networkIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: 4}))[0] === 'network-cellular-signal-excellent-symbolic');
check('wifi picks a wireless icon',
    networkIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'wifi', signalLevel: 2}))[0] === 'network-wireless-signal-ok-symbolic');

print('signal bars');
check('SIGNAL_BAR_COUNT is 4', SIGNAL_BAR_COUNT === 4);
check('unknown signal has 4 bars', signalBarStates(null).length === 4);
check('unknown signal all bars inactive', signalBarStates(null).every(s => s === false));
check('level 0 has 4 bars', signalBarStates(0).length === 4);
check('level 0 all bars inactive', signalBarStates(0).every(s => s === false));
check('level 1 has 4 bars', signalBarStates(1).length === 4);
check('level 1 bar 1 active', signalBarStates(1)[0] === true);
check('level 1 bars 2-4 inactive', signalBarStates(1)[1] === false && signalBarStates(1)[2] === false && signalBarStates(1)[3] === false);
check('level 2 bars 1-2 active', signalBarStates(2)[0] === true && signalBarStates(2)[1] === true);
check('level 2 bars 3-4 inactive', signalBarStates(2)[2] === false && signalBarStates(2)[3] === false);
check('level 3 bars 1-3 active', signalBarStates(3)[0] === true && signalBarStates(3)[1] === true && signalBarStates(3)[2] === true);
check('level 3 bar 4 inactive', signalBarStates(3)[3] === false);
check('level 4 all active', signalBarStates(4).every(s => s === true));
check('undefined signal has 4 bars all inactive', signalBarStates(undefined).length === 4 && signalBarStates(undefined).every(s => s === false));

print('battery slot state');
check('connected with battery: visible', batterySlotState(normalizePhoneStatus({...connectedPhone, batteryPercentage: 53})).visible === true);
check('connected with battery: not muted', batterySlotState(normalizePhoneStatus({...connectedPhone, batteryPercentage: 53})).muted === false);
check('connected with battery: label 53%', batterySlotState(normalizePhoneStatus({...connectedPhone, batteryPercentage: 53})).label === '53%');
check('connected no battery: visible', batterySlotState(normalizePhoneStatus(connectedPhone)).visible === true);
check('connected no battery: muted', batterySlotState(normalizePhoneStatus(connectedPhone)).muted === true);
check('connected no battery: label is dash', batterySlotState(normalizePhoneStatus(connectedPhone)).label === '\u2014%');
check('stale battery: visible and muted', (() => {
    const s = batterySlotState(normalizePhoneStatus({...connectedPhone, batteryPercentage: 53, batteryIsStale: true}));
    return s.visible === true && s.muted === true;
})());
check('disconnected: not visible', batterySlotState(normalizePhoneStatus({...connectedPhone, connected: false})).visible === false);

print('bell state');
check('connected 0 notifications: visible', bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 0})).visible === true);
check('connected 0 notifications: not active', bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 0})).active === false);
check('connected 1 notification: visible', bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 1})).visible === true);
check('connected 1 notification: active', bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 1})).active === true);
check('connected 5 notifications: active', bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 5})).active === true);
check('connected null notifications: visible', bellState(normalizePhoneStatus(connectedPhone)).visible === true);
check('connected null notifications: not active', bellState(normalizePhoneStatus(connectedPhone)).active === false);
check('disconnected: not visible', bellState(normalizePhoneStatus({...connectedPhone, connected: false})).visible === false);
check('null status: not visible', bellState(null).visible === false);

print('messages');
check('an absent count stays absent', normalizePhoneStatus(connectedPhone).unreadMessageCount === null);
check('zero unread is a real answer', normalizePhoneStatus({...connectedPhone, unreadMessageCount: 0}).unreadMessageCount === 0);
check('a negative count is dropped', normalizePhoneStatus({...connectedPhone, unreadMessageCount: -3}).unreadMessageCount === null);
check('a count is drawn literally', unreadLabel(2) === '2');
check('ninety-nine is drawn literally', unreadLabel(99) === '99');
check('a hundred collapses', unreadLabel(100) === '99+');

print('attention');
check('a settled phone asks for nothing', !needsAttention(normalizePhoneStatus({...connectedPhone, notificationCount: 0})));
check('an absent count asks for nothing', !needsAttention(normalizePhoneStatus(connectedPhone)));
check('a standing notification asks for the user', needsAttention(normalizePhoneStatus({...connectedPhone, notificationCount: 3})));
check('an unread message asks for the user', needsAttention(normalizePhoneStatus({...connectedPhone, unreadMessageCount: 1})));
check('an absent phone asks for nothing', !needsAttention(null));
check('an offline phone asks for nothing', !needsAttention(normalizePhoneStatus({...connectedPhone, connected: false, notificationCount: 3})));
check('zero notifications is a real answer', normalizePhoneStatus({...connectedPhone, notificationCount: 0}).notificationCount === 0);
check('a negative notification count is dropped', normalizePhoneStatus({...connectedPhone, notificationCount: -2}).notificationCount === null);
check('an absent notification count stays absent', normalizePhoneStatus(connectedPhone).notificationCount === null);

print('notification pulse');
check('zero notifications never pulse', notificationPulseOpacities(0, 0, true).length === 0);
check('a new notification has three finite pulses', notificationPulseOpacities(0, 1, true).length === 6);
check('a larger count pulses again', notificationPulseOpacities(1, 3, true).length === 6);
check('a stable count does not pulse', notificationPulseOpacities(3, 3, true).length === 0);
check('a cleared count does not pulse', notificationPulseOpacities(3, 0, true).length === 0);
check('reduced motion disables the pulse', notificationPulseOpacities(0, 1, false).length === 0);
check('every pulse terminates fully visible', notificationPulseOpacities(0, 100, true).at(-1) === 255);

print('accessible name');
check('an absent Relay is announced', accessibleName(null, false, identity) === 'Relay phone, not running');
check('an absent phone is announced', accessibleName(null, true, identity) === 'Relay phone, no phone connected');
check('a plain phone announces its name and state',
    accessibleName(normalizePhoneStatus(connectedPhone), true, identity) === 'Relay phone, Redmi Note 14 Pro, connected, signal unknown');
check('an unknown battery is not announced',
    !accessibleName(normalizePhoneStatus(connectedPhone), true, identity).includes('battery'));
check('a known battery is announced',
    accessibleName(normalizePhoneStatus({...connectedPhone, batteryPercentage: 67, batteryIsCharging: true}), true, identity) ===
        'Relay phone, Redmi Note 14 Pro, connected, signal unknown, battery 67 percent, charging');
check('zero notifications use plural grammar',
    accessibleName(normalizePhoneStatus({...connectedPhone, notificationCount: 0}), true, identity).includes('0 notifications'));
check('one notification uses singular grammar',
    accessibleName(normalizePhoneStatus({...connectedPhone, notificationCount: 1}), true, identity).includes('1 notification'));
check('two notifications use plural grammar',
    accessibleName(normalizePhoneStatus({...connectedPhone, notificationCount: 2}), true, identity).includes('2 notifications'));
check('unread messages are announced',
    accessibleName(normalizePhoneStatus({...connectedPhone, unreadMessageCount: 2}), true, identity).includes('2 unread messages'));
check('notifications are announced',
    accessibleName(normalizePhoneStatus({...connectedPhone, notificationCount: 3}), true, identity).includes('3 notifications'));
check('the phone name is always announced even though the pill does not draw it',
    accessibleName(normalizePhoneStatus(connectedPhone), true, identity).includes('Redmi Note 14 Pro'));
check('no device id is announced',
    !accessibleName(normalizePhoneStatus(connectedPhone), true, identity).includes('kdeconnect'));

print(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
if (failures > 0)
    throw new Error(`${failures} check(s) failed`);
