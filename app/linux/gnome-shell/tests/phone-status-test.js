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

import GLib from 'gi://GLib';

import * as phoneStatus from '../relay@foresight.app/phoneStatus.js';

import {
    accessibleName,
    batteryIconNames,
    bellIconNames,
    batterySlotState,
    batteryMenuLabel,
    batteryPanelLabel,
    networkGenerationLabel,
    chargeAnimationState,
    CHARGE_FADE_MS,
    CHARGE_REST_MS,
    CHARGE_CYCLE_MS,
    bellState,
    hasLiveBattery,
    needsAttention,
    networkIconNames,
    signalIconNames,
    SIGNAL_STRENGTHS,
    bellRestingOpacity,
    bellRingDuration,
    bellRingKeyframes,
    shouldRingBell,
    BELL_READ_OPACITY,
    BELL_UNREAD_OPACITY,
    normalizePhoneStatus,
    signalQualityLabel,
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
check('an empty name falls back', normalizePhoneStatus({...connectedPhone, displayName: '  '}).displayName === 'Phone');
check('presentation flags default to true',
    normalizePhoneStatus(connectedPhone).showNetworkLabel === true &&
    normalizePhoneStatus(connectedPhone).showBatteryPercentage === true &&
    normalizePhoneStatus(connectedPhone).showNotifications === true &&
    normalizePhoneStatus(connectedPhone).chargingAnimationEnabled === true &&
    normalizePhoneStatus(connectedPhone).showSignal === true);
check('presentation flags can be disabled',
    normalizePhoneStatus({...connectedPhone, showNetworkLabel: false, showBatteryPercentage: false}).showNetworkLabel === false &&
    normalizePhoneStatus({...connectedPhone, showNotifications: false}).showNotifications === false);
check('batterySlotState hides percentage when showBatteryPercentage is false',
    batterySlotState(normalizePhoneStatus({...connectedPhone, batteryPercentage: 80, showBatteryPercentage: false})).label === '');
check('bellState hides bell when showNotifications is false',
    bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 2, showNotifications: false})).visible === false);

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
// A missing reading is not zero bars. "none" is itself a reading, so an
// unknown strength asks for the acquiring icon instead of claiming an empty one.
check('unknown signal does not claim zero bars',
    networkIconNames(normalizePhoneStatus(connectedPhone))[0] === 'network-cellular-acquiring-symbolic');
check('unknown signal still falls back to a cellular icon',
    networkIconNames(normalizePhoneStatus(connectedPhone)).includes('network-cellular-symbolic'));
for (const [level, name] of ['none', 'weak', 'ok', 'good', 'excellent'].entries()) {
    check(`signal ${level} picks ${name}`, networkIconNames(normalizePhoneStatus({...connectedPhone, signalLevel: level}))[0] ===
        `network-cellular-signal-${name}-symbolic`);
}
check('cellular picks a cellular icon',
    networkIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: 4}))[0] === 'network-cellular-signal-excellent-symbolic');
check('wifi picks a wireless icon',
    networkIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'wifi', signalLevel: 2}))[0] === 'network-wireless-signal-ok-symbolic');

print('native panel icon mapping');
// Every icon the panel can ask for comes from a family GNOME itself ships, so
// Relay's cluster carries the same weight as the shell's own indicators.
const cellular = level => signalIconNames(normalizePhoneStatus({...connectedPhone, networkKind: 'cellular', signalLevel: level}), true)[0];
check('level 0 maps to none', cellular(0) === 'network-cellular-signal-none-symbolic');
check('level 1 maps to weak', cellular(1) === 'network-cellular-signal-weak-symbolic');
check('level 2 maps to ok', cellular(2) === 'network-cellular-signal-ok-symbolic');
check('level 3 maps to good', cellular(3) === 'network-cellular-signal-good-symbolic');
check('level 4 maps to excellent', cellular(4) === 'network-cellular-signal-excellent-symbolic');
check('the strength ladder has one name per level', SIGNAL_STRENGTHS.length === 5);
check('a disconnected phone reads as offline, not as no bars',
    signalIconNames(normalizePhoneStatus({...connectedPhone, signalLevel: 4}), false)[0] === 'network-cellular-offline-symbolic');
check('an absent phone reads as offline', signalIconNames(null, true)[0] === 'network-cellular-offline-symbolic');
check('every signal chain carries a fallback', cellular(4).length > 0 && signalIconNames(null, false).length > 1);

check('all three panel families are symbolic', [
    cellular(3),
    batteryIconNames(normalizePhoneStatus({...connectedPhone, batteryPercentage: 60}))[0],
    bellIconNames()[0],
].every(name => name.endsWith('-symbolic')));

check('the bell uses one glyph for both states', bellIconNames().length > 1 && bellIconNames()[0] === 'preferences-system-notifications-symbolic');

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

print('bell ring');
// A new notification rings the bell once. Nothing else moves it, and it always
// finishes level so the glyph cannot be left tilted in the panel.
check('zero notifications never ring', shouldRingBell(0, 0, true) === false);
check('a new notification rings', shouldRingBell(0, 1, true) === true);
check('a larger count rings again', shouldRingBell(1, 3, true) === true);
check('a stable count does not ring', shouldRingBell(3, 3, true) === false);
check('a cleared count does not ring', shouldRingBell(3, 0, true) === false);
check('a falling count does not ring', shouldRingBell(5, 2, true) === false);
check('reduced motion disables the ring', shouldRingBell(0, 1, false) === false);
check('an unknown count is treated as none', shouldRingBell(null, null, true) === false);

const ring = bellRingKeyframes();
check('the ring is a five step swing', ring.length === 5);
check('the ring starts by swinging back', ring[0].angle < 0);
check('the ring always ends level', ring.at(-1).angle === 0);
check('the swing decays', ring.every((step, index) =>
    index === 0 || Math.abs(step.angle) <= Math.abs(ring[index - 1].angle) || index === 1));
check('the swing never exceeds six degrees', ring.every(step => Math.abs(step.angle) <= 6));
check('the ring alternates direction', ring.slice(0, 4).every((step, index) =>
    index === 0 || Math.sign(step.angle) !== Math.sign(ring[index - 1].angle)));
check('every step has a positive duration', ring.every(step => step.duration > 0));
check('one ring lasts between 420 and 520 ms', bellRingDuration() >= 420 && bellRingDuration() <= 520);

print('bell resting appearance');
// Unread is a fuller glyph, never a colour and never a badge.
check('nothing unread is subdued', bellRestingOpacity(false) === BELL_READ_OPACITY);
check('unread is fully present', bellRestingOpacity(true) === BELL_UNREAD_OPACITY);
check('the subdued state is around 0.70 to 0.75', BELL_READ_OPACITY / 255 >= 0.70 && BELL_READ_OPACITY / 255 <= 0.75);
check('the unread state is fully opaque', BELL_UNREAD_OPACITY === 255);
check('unread changes only opacity', bellRestingOpacity(true) !== bellRestingOpacity(false));

print('panel labels');
// The panel is a quick glance: a generation and a percentage, nothing that
// changes length while it is being read.
const ltePhone = normalizePhoneStatus({...connectedPhone, networkLabel: 'LTE', signalLevel: 3, batteryPercentage: 52});
check('a generation is stated', networkGenerationLabel(ltePhone, true) === 'LTE');
check('5G is stated', networkGenerationLabel(normalizePhoneStatus({...connectedPhone, networkLabel: '5G'}), true) === '5G');
check('a generation is upper-cased', networkGenerationLabel(normalizePhoneStatus({...connectedPhone, networkLabel: 'lte'}), true) === 'LTE');
check('no generation means no label', networkGenerationLabel(normalizePhoneStatus(connectedPhone), true) === null);
check('a blank generation means no label',
    networkGenerationLabel(normalizePhoneStatus({...connectedPhone, networkLabel: '   '}), true) === null);
// A carrier name in the panel is how the cluster ends up as wide as the clock.
check('a carrier name is not treated as a generation',
    networkGenerationLabel(normalizePhoneStatus({...connectedPhone, networkLabel: 'Vodafone IN'}), true) === null);
check('a disconnected phone states no generation', networkGenerationLabel(ltePhone, false) === null);
check('an absent phone states no generation', networkGenerationLabel(null, true) === null);

check('the charge is stated as a percentage', batteryPanelLabel(ltePhone) === '52%');
check('an unknown charge shows no label rather than a placeholder',
    batteryPanelLabel(normalizePhoneStatus(connectedPhone)) === null);
check('an absent phone shows no charge label', batteryPanelLabel(null) === null);
check('a full charge is stated', batteryPanelLabel(normalizePhoneStatus({...connectedPhone, batteryPercentage: 100})) === '100%');
check('the panel never states signal quality', networkGenerationLabel(ltePhone, true) !== signalQualityLabel(3, value => value));
check('the panel never states the device name',
    networkGenerationLabel(ltePhone, true) !== ltePhone.displayName && batteryPanelLabel(ltePhone) !== ltePhone.displayName);

print('unread is a dot, never a coloured bell');
check('nothing unread leaves the bell inactive', bellState(normalizePhoneStatus(connectedPhone)).active === false);
check('unread notifications activate the bell',
    bellState(normalizePhoneStatus({...connectedPhone, notificationCount: 3})).active === true);
check('the bell glyph is the same in both states', bellIconNames()[0] === bellIconNames()[0]);

print('charging warmth');
// Charging and animated are separate answers: a desktop with animations off
// still has to say the phone is charging, it just says it with the native
// charging icon alone and no warm pulse over it.
const chargingPhone = normalizePhoneStatus({...connectedPhone, batteryPercentage: 40, batteryIsCharging: true});
const restingPhone = normalizePhoneStatus({...connectedPhone, batteryPercentage: 40, batteryIsCharging: false});
const stalePhone = normalizePhoneStatus({...connectedPhone, batteryPercentage: 40, batteryIsCharging: true, batteryIsStale: true});

check('a charging phone pulses when animations are allowed', chargeAnimationState(chargingPhone, true).animated === true);
check('a charging phone is still charging when animations are off', chargeAnimationState(chargingPhone, false).charging === true);
check('reduced motion shows the native charging icon only', chargeAnimationState(chargingPhone, false).animated === false);
check('a phone on battery never pulses', chargeAnimationState(restingPhone, true).animated === false);
check('a phone on battery is not charging', chargeAnimationState(restingPhone, true).charging === false);
check('a stale reading is not presented as live charging', chargeAnimationState(stalePhone, true).charging === false);
check('an absent phone is not charging', chargeAnimationState(null, true).charging === false);
check('a disconnected phone is not charging',
    chargeAnimationState(normalizePhoneStatus({...connectedPhone, batteryPercentage: 40, batteryIsCharging: true, connected: false}), true).charging === false);
check('an unknown charge level does not pulse',
    chargeAnimationState(normalizePhoneStatus({...connectedPhone, batteryPercentage: null, batteryIsCharging: true}), true).animated === false);

// A charging phone must still be drawn with the native charging artwork.
check('charging picks a native charging icon',
    batteryIconNames(chargingPhone)[0] === 'battery-level-40-charging-symbolic');
check('a full charging phone picks the charged icon',
    batteryIconNames(normalizePhoneStatus({...connectedPhone, batteryPercentage: 100, batteryIsCharging: true, batteryIsFull: true}))[0] ===
        'battery-level-100-charged-symbolic');

check('one pulse plus its rest is between two and three seconds', CHARGE_CYCLE_MS >= 2000 && CHARGE_CYCLE_MS <= 3000);
check('the motion itself is between 1.8 and 2.4 seconds', CHARGE_FADE_MS * 2 >= 1800 && CHARGE_FADE_MS * 2 <= 2400);
check('the rest is between 0.6 and 1.0 seconds', CHARGE_REST_MS >= 600 && CHARGE_REST_MS <= 1000);

print('battery menu label');
const id = value => value;
check('an absent status is not reported', batteryMenuLabel(null, id) === 'Not reported');
check('an unknown charge is not reported',
    batteryMenuLabel(normalizePhoneStatus({...connectedPhone, batteryPercentage: null}), id) === 'Not reported');
check('a plain charge is stated alone',
    batteryMenuLabel(normalizePhoneStatus({...connectedPhone, batteryPercentage: 61}), id) === '61%');
check('charging is stated with the charge',
    batteryMenuLabel(normalizePhoneStatus({...connectedPhone, batteryPercentage: 61, batteryIsCharging: true}), id).includes('Charging'));
check('a stale reading is marked last known',
    batteryMenuLabel(normalizePhoneStatus({...connectedPhone, batteryPercentage: 61, batteryIsStale: true}), id).includes('Last known'));
check('the charge is never dropped from the line',
    batteryMenuLabel(normalizePhoneStatus({...connectedPhone, batteryPercentage: 61, batteryIsCharging: true}), id).startsWith('61%'));

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

print('panel is built from native shell primitives');
// Two iterations of hand-drawn Cairo glyphs were rejected for not matching the
// surrounding GNOME icons. These checks read the extension source directly and
// fail if the panel ever goes back to sizing its own artwork.
const [, extensionBytes] = GLib.file_get_contents(
    GLib.build_filenamev([GLib.path_get_dirname(import.meta.url.replace('file://', '')), '..', 'relay@foresight.app', 'extension.js']));
const extensionSource = new TextDecoder().decode(extensionBytes);

const panelIconCount = (extensionSource.match(/style_class: 'system-status-icon/g) ?? []).length;
check('all three panel icons use the stock system-status-icon class', panelIconCount >= 4);
check('the cluster groups each icon with its label',
    extensionSource.includes("style_class: 'relay-group'") && extensionSource.includes("style_class: 'relay-cluster'"));
check('the panel no longer draws its own glyphs', !extensionSource.includes('St.DrawingArea'));
check('no Cairo is left in the panel', !extensionSource.includes("gi://cairo"));
check('no per-icon pixel sizes are declared', !/icon_size:\s*\d/.test(extensionSource));
check('no fixed slot sizes are declared', !extensionSource.includes('STATUS_SLOT_SIZE'));
check('Relay declares no custom panel spacing', !extensionSource.includes('GROUP_GAP'));

const [, cssBytes] = GLib.file_get_contents(
    GLib.build_filenamev([GLib.path_get_dirname(import.meta.url.replace('file://', '')), '..', 'relay@foresight.app', 'stylesheet.css']));
const cssSource = new TextDecoder().decode(cssBytes);
// A named import of something phoneStatus no longer exports is a module link
// failure: the extension loads as valid JavaScript and then dies on import.
// Nothing else in this suite would notice, so it is checked explicitly.
const importBlock = extensionSource.match(/import \{([^}]*)\} from '\.\/phoneStatus\.js';/);
check('the extension imports from phoneStatus', importBlock !== null);
const importedNames = importBlock[1].split(',').map(name => name.trim()).filter(name => name.length > 0);
const moduleExports = Object.keys(phoneStatus);
const unresolved = importedNames.filter(name => !moduleExports.includes(name));
check(`every name the extension imports is exported (${unresolved.join(', ') || 'all resolve'})`, unresolved.length === 0);
const deadImports = importedNames.filter(name => extensionSource.split(name).length <= 2);
check(`no import is left unused (${deadImports.join(', ') || 'all used'})`, deadImports.length === 0);

check('the unread dot is gone from the panel',
    !extensionSource.includes('relay-unread-dot') && !extensionSource.includes('_unreadDot'));
check('no badge or dot actor remains', !cssSource.includes('relay-unread-dot'));
check('the bell swings from where it hangs, not its box centre',
    extensionSource.includes('this._bellStack.set_pivot_point('));
check('the ring always resets the angle',
    extensionSource.includes('this._bellStack.rotation_angle_z = 0'));
// An ordinary status update landing mid-swing must not abandon the ring and
// leave the glyph tilted, so the generation is bumped only when one starts.
const renderBellBody = /_renderBell\(status\) \{[\s\S]*?\n    \}/.exec(extensionSource)?.[0] ?? '';
check('a routine render cannot abandon an in-flight ring',
    !renderBellBody.includes('_notificationPulseGeneration += 1') &&
    !renderBellBody.includes('_notificationPulseGeneration++'));
check('the ring owns its own generation',
    /_ringBell\(\)\s*\{[\s\S]{0,200}\+\+this\._notificationPulseGeneration/.test(extensionSource));
check('the ring rotates the bell rather than scaling or bouncing it',
    extensionSource.includes('rotation_angle_z:') && !extensionSource.includes('this._bellStack.set_scale('));
check('the warmth is a second icon, so the resting bell keeps no colour',
    extensionSource.includes('relay-bell-warm') && !extensionSource.includes('this._bellIcon.add_style_class_name'));
check('the charging warmth is confined to the battery icon',
    extensionSource.includes('this._batteryWarmIcon.ease(') &&
    !extensionSource.includes('this._batteryLabel.ease(') &&
    !extensionSource.includes('this._networkLabel.ease('));
check('the percentage label never animates', !extensionSource.includes('_batteryLabel.ease'));
check('no device name reaches the panel', !extensionSource.includes('this._networkLabel.text = status.displayName'));

check('the stylesheet sets no panel icon box sizes', !/\.relay-status-icon-slot/.test(cssSource));
check('the stylesheet adds colour only for charging and the ring',
    cssSource.includes('.relay-charge-warm') && cssSource.includes('.relay-bell-warm'));
check('the bell is never given a permanent colour class',
    !cssSource.includes('.relay-bell-unread') && !extensionSource.includes('relay-bell-unread'));
check('the stylesheet never overrides icon-size for panel icons',
    !/\.system-status-icon[^{]*\{[^}]*icon-size/.test(cssSource));
check('the panel labels inherit the shell font',
    !/\.relay-panel-label[^{]*\{[^}]*font-family/.test(cssSource) && !/\.relay-panel-label[^{]*\{[^}]*font-size/.test(cssSource));
const clusterSpacing = Number(/\.relay-cluster\s*\{[^}]*spacing:\s*(\d+)px/.exec(cssSource)?.[1]);
const groupSpacing = Number(/\.relay-group\s*\{[^}]*spacing:\s*(\d+)px/.exec(cssSource)?.[1]);
check(`between-group spacing is 8 to 10px (${clusterSpacing})`, clusterSpacing >= 8 && clusterSpacing <= 10);
check(`within-group spacing is 3 to 4px (${groupSpacing})`, groupSpacing >= 3 && groupSpacing <= 4);
check('groups are separated more than their own contents', clusterSpacing > groupSpacing);
check('the bell is spaced like every other group',
    (extensionSource.match(/style_class: 'relay-group'/g) ?? []).length === 2 &&
    !/relay-bell[^']*'\s*,\s*[^}]*margin/.test(extensionSource));
check('the panel labels are not bold', /\.relay-panel-label\s*\{[^}]*font-weight:\s*normal/.test(cssSource));

print(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
if (failures > 0)
    throw new Error(`${failures} check(s) failed`);
