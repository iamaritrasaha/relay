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
    hasLiveBattery,
    needsAttention,
    networkIconNames,
    normalizePhoneStatus,
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
check('a signal without a network is dropped', normalizePhoneStatus({...connectedPhone, signalLevel: 3}).signalLevel === null);
check('a signal with a network survives', normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: 3}).signalLevel === 3);
check('an absurd signal is dropped', normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: -1000}).signalLevel === null);
check('cellular picks a cellular icon',
    networkIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: 4}))[0] === 'network-cellular-signal-excellent-symbolic');
check('wifi picks a wireless icon',
    networkIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'wifi', signalLevel: 2}))[0] === 'network-wireless-signal-ok-symbolic');

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

print('accessible name');
check('an absent Relay is announced', accessibleName(null, false, identity) === 'Relay, not running');
check('an absent phone is announced', accessibleName(null, true, identity) === 'Relay, no phone connected');
check('a plain phone announces its name and state',
    accessibleName(normalizePhoneStatus(connectedPhone), true, identity) === 'Relay, Redmi Note 14 Pro, connected');
check('an unknown battery is not announced',
    !accessibleName(normalizePhoneStatus(connectedPhone), true, identity).includes('battery'));
check('a known battery is announced',
    accessibleName(normalizePhoneStatus({...connectedPhone, batteryPercentage: 67, batteryIsCharging: true}), true, identity) ===
        'Relay, Redmi Note 14 Pro, connected, battery 67 percent, charging');
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
