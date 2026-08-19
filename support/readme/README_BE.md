# Relay

[![CI status][ci-badge]][ci-workflow]
[![Translations][translate-badge]][translate-link]
[![Packaging status][packaging-badge]][packaging-link]

[ci-badge]: https://github.com/relay/relay/actions/workflows/ci.yml/badge.svg
[ci-workflow]: https://github.com/relay/relay/actions/workflows/ci.yml
[translate-badge]: https://hosted.weblate.org/widget/relay/app/svg-badge.svg
[translate-link]: https://hosted.weblate.org/engage/relay/
[packaging-badge]: https://repology.org/badge/tiny-repos/relay.svg
[packaging-link]: https://repology.org/project/relay/versions

[Галоўная старонка][homepage] • [Discord][discord] • [GitHub][github] • [Codeberg][codeberg]

[English (Default)](/README.md) • [Беларуская](README_BE.md) • [Español](README_ES.md) • [فارسی](README_FA.md) • [Filipino](README_PH.md) • [Français](README_FR.md) • [Indonesia](README_ID.md) • [Italiano](README_IT.md) • [日本語](README_JA.md) • [ភាសាខ្មែរ](README_KM.md) • [한국어](README_KO.md) • [Polski](README_PL.md) • [Português Brasil](README_PT_BR.md) • [Русский](README_RU.md) • [ภาษาไทย](README_TH.md) • [Türkçe](README_TR.md) • [Українська](README_UK.md) • [Tiếng Việt](README_VI.md) • [中文](README_ZH.md)

[homepage]: https://relay.org
[discord]: https://discord.gg/GSRWmQNP87
[github]: https://github.com/relay/relay
[codeberg]: https://codeberg.org/relay/relay

Relay — гэта бясплатная праграма з адкрытым зыходным кодам, якая дазваляе бяспечна абменьвацца файламі і паведамленнямі з прыладамі побач праз лакальную сетку без інтэрнэт-злучэння.

- [Пра Relay](#пра-relay)
- [Спонсары](#спонсары)
- [Здымкі экрана](#здымкі-экрана)
- [Спампаванне](#спампаванне)
- [Як гэта працуе](#як-гэта-працуе)
- [Іерархія залежнасцей](#іерархія-залежнасцей)
- [Пачатак працы](#пачатак-працы)
- [Унёсак у праект](#унёсак-у-праект)
  - [Пераклад](#пераклад)
  - [Выпраўленне памылак і паляпшэнні](#выпраўленне-памылак-і-паляпшэнні)
- [Выпраўленне непаладак](#выпраўленне-непаладак)
- [Зборка](#зборка)
  - [Android](#android)
  - [iOS](#ios)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Linux](#linux)

## Пра Relay

Relay — гэта кросплатформенная праграма для бяспечнай сувязі паміж прыладамі праз REST API і шыфраванне HTTPS. У адрозненне ад іншых праграм для абмену паведамленнямі, што абапіраюцца на знешнія серверы, Relay не патрабуе ні інтэрнэт-злучэння, ні старонніх сервераў, і таму з'яўляецца хуткім і надзейным рашэннем для лакальнай сувязі.

## Спонсары

Тэсціраванне ў браўзерах забяспечвае

<a href="https://www.testmuai.com/?utm_medium=sponsor&utm_source=relay" target="_blank">
    <img src="https://relay.org/img/sponsors/tesmu.svg" style="vertical-align: middle;" width="250" height="45" />
</a>

## Здымкі экрана

<img src="https://relay.org/img/screenshot-iphone.webp" alt="iPhone screenshot" height="300"/> <img src="https://relay.org/img/screenshot-pc.webp" alt="PC screenshot" height="300"/>

## Спампаванне

[![Packaging status](https://repology.org/badge/tiny-repos/relay.svg)](https://repology.org/project/relay/versions)

Праграму раім спампоўваць з крамы праграм або праз менеджар пакетаў, бо яна не мае аўтаматычнага абнаўлення.

| Windows                 | macOS                   | Linux              | Android        | iOS           | Fire OS    |
|-------------------------|-------------------------|--------------------|----------------|---------------|------------|
| [Winget][]              | [App Store][]           | [Flathub][]        | [Play Store][] | [App Store][] | [Amazon][] |
| [Scoop][]               | [Homebrew][]            | [Nixpkgs][]        | [F-Droid][]    |               |            |
| [Chocolatey][]          | [DMG Installer][latest] | [Snap][]           | [APK][latest]  |               |            |
| [EXE Installer][latest] |                         | [AUR][]            |                |               |            |
| [Portable ZIP][latest]  |                         | [TAR][latest]      |                |               |            |
|                         |                         | [DEB][latest]      |                |               |            |
|                         |                         | [AppImage][latest] |                |               |            |

Падрабязней пра [каналы распаўсюджвання][].

Двайковыя файлы для Windows падпісаныя. Падрабязней у [палітыцы падпісвання коду][].

> [!CAUTION]
> **Неафіцыйная зборка MSIX:** зборкі з апошніх камітаў можна паспрабаваць на [relay.ob-buff.dev](https://relay.ob-buff.dev/). Стабільнасць не гарантуецца, а ўсе змяненні ў кодзе пералічаны на тым жа сайце.

[windows store]: https://www.microsoft.com/store/apps/9NCB4Z0TZ6RR
[app store]: https://apps.apple.com/us/app/relay/id1661733229
[play store]: https://play.google.com/store/apps/details?id=com.foresight.app.relay
[f-droid]: https://f-droid.org/packages/com.foresight.app.relay
[amazon]: https://www.amazon.com/dp/B0BW6MP732
[winget]: https://github.com/microsoft/winget-pkgs/tree/master/manifests/l/Relay/Relay
[scoop]: https://scoop.sh/#/apps?s=0&d=1&o=true&q=relay&id=fb88113be361ca32c0dcac423cb4afdeda0b0c66
[chocolatey]: https://community.chocolatey.org/packages/relay
[homebrew]: https://formulae.brew.sh/cask/relay
[flathub]: https://flathub.org/apps/details/com.foresight.app.relay
[nixpkgs]: https://search.nixos.org/packages?show=relay
[snap]: https://snapcraft.io/relay
[aur]: https://aur.archlinux.org/packages/relay-bin
[latest]: https://github.com/relay/relay/releases/latest
[каналы распаўсюджвання]: https://github.com/relay/relay/blob/main/CONTRIBUTING.md#distribution
[палітыцы падпісвання коду]: https://github.com/relay/relay/blob/main/CODE_SIGNING.md

**Сумяшчальнасць**

| Платформа | Мінімальная версія | Заўвага                                                                                                                                  |
|-----------|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Android   | 5.0                | -                                                                                                                                        |
| iOS       | 12.0               | -                                                                                                                                        |
| macOS     | 11 Big Sur         | Скарыстайцеся OpenCore Legacy Patcher 2.0.2 (гл. [#1005](https://github.com/relay/relay/issues/1005#issuecomment-2449899384))    |
| Windows   | 10                 | Апошняя версія з падтрымкай Windows 7 — v1.15.4. У будучыні магчымы зваротныя порты навейшых версій для Windows 7.                       |
| Linux     | Н/Д                | Залежнасці: Gnome: `xdg-desktop-portal` і `xdg-desktop-portal-gtk`, KDE: `xdg-desktop-portal` і `xdg-desktop-portal-kde`                 |

## Наладжванне

У большасці выпадкаў Relay працуе адразу пасля ўсталявання. Але калі ў вас узнікаюць цяжкасці з адпраўкай ці атрыманнем файлаў, магчыма, спатрэбіцца наладзіць міжсеткавы экран так, каб Relay мог абменьвацца данымі ў вашай лакальнай сетцы.

| Тып трафіку | Пратакол | Порт  | Дзеянне   |
|-------------|----------|-------|-----------|
| Уваходны    | TCP, UDP | 53317 | Дазволіць |
| Выходны     | TCP, UDP | Любы  | Дазволіць |

Таксама ўпэўніцеся, што на маршрутызатары адключана ізаляцыя пунктаў доступу. Звычайна яна адключана прадвызначана, але на некаторых маршрутызатарах можа быць уключана (асабліва ў гасцявых сетках).
Падрабязней у раздзеле [Выпраўленне непаладак](#выпраўленне-непаладак).

**Партатыўны рэжым**

(з'явіўся ў v1.13.0)

Стварыце файл з назвай `settings.json` у той жа папцы, што і выканальны файл.
Файл можа быць пусты.
Праграма будзе захоўваць налады ў ім замест прадвызначанага месца.

**Схаваны запуск**

(абноўлена ў v1.15.0)

Каб запусціць праграму схавана (толькі ў вобласці апавяшчэнняў), скарыстайцеся параметрам `--hidden` (напрыклад: `relay.exe --hidden`).

У версіях v1.14.0 і ранейшых праграма запускаецца схавана, калі зададзены параметр `autostart` і ўключана налада схаванага запуску.

## Як гэта працуе

Relay выкарыстоўвае бяспечны пратакол сувязі, які дазваляе прыладам абменьвацца данымі праз REST API. Усе даныя перадаюцца праз HTTPS, а сертыфікат TLS/SSL ствараецца на ляту на кожнай прыладзе, што забяспечвае максімальную бяспеку.

Падрабязней пра пратакол Relay — у [дакументацыі](https://github.com/relay/protocol).

## Іерархія залежнасцей

![Іерархія залежнасцей](/support/docs/dependency-hierarchy.svg)

## Пачатак працы

Каб сабраць Relay з зыходнага коду, выканайце наступныя крокі:

1. Усталюйце Flutter [напрамую](https://flutter.dev) або праз [fvm](https://fvm.app) (гл. [патрэбную версію](/.fvmrc))
2. Усталюйце [Rust](https://www.rust-lang.org/tools/install)
3. Кланіруйце рэпазіторый `Relay`
4. Выканайце `cd app`, каб перайсці ў папку праграмы
5. Выканайце `flutter pub get`, каб спампаваць залежнасці
6. Выканайце `flutter run`, каб запусціць праграму

> [!NOTE]
> Цяпер Relay патрабуе старэйшай версіі Flutter (яна ўказана ў [.fvmrc](/.fvmrc)),
> таму праблемы са зборкай могуць узнікаць з-за неадпаведнасці паміж патрэбнай версіяй і той, што ўсталявана ў сістэме.  
> Каб распрацоўка была больш прадказальнай, Relay кіруе версіяй Flutter праз [fvm](https://fvm.app).
> Пасля ўсталявання `fvm` выконвайце `fvm flutter` замест `flutter`.

## Унёсак у праект

Мы вітаем унёсак ад кожнага, хто хоча дапамагчы палепшыць Relay. Далучыцца можна некалькімі спосабамі.

### Пераклад

Вы можаце дапамагчы з перакладам Relay на іншыя мовы. Для кіравання перакладамі мы карыстаемся платформай [Weblate](https://hosted.weblate.org/projects/relay/app).

Акрамя таго, можна зрабіць развілку (fork) гэтага рэпазіторыя і дадаць пераклады ўручную.

Пераклады знаходзяцца ў папцы [app/assets/i18n](https://github.com/relay/relay/tree/main/app/assets/i18n). Каб дадаць ці абнавіць пераклад, рэдагуйце файл `_missing_translations_<locale>.json` або `<locale>.json`.

<a href="https://hosted.weblate.org/engage/relay/">
<img src="https://hosted.weblate.org/widget/relay/app/multi-auto.svg" alt="Translation status" />
</a>

**_Заўвага:_ палі, пазначаныя `@`, перакладаць не трэба; праграма іх ніяк не выкарыстоўвае, гэта проста звесткі пра файл або кантэкст для перакладчыка.**

### Выпраўленне памылак і паляпшэнні

- **Выпраўленне памылак:** калі вы знайшлі памылку, стварыце запыт на зліванне (pull request) з выразным апісаннем праблемы і спосабу яе выпраўлення.
- **Паляпшэнні:** маеце ідэю, як палепшыць Relay? Спачатку стварыце паведамленне пра праблему (issue), каб абмеркаваць, навошта гэта паляпшэнне патрэбна.

Падрабязней — у [дапаможніку па ўнёску ў праект](https://github.com/relay/relay/blob/main/CONTRIBUTING.md).

## Выпраўленне непаладак

| Праблема              | Платформа (адпраўка) | Платформа (атрыманне) | Рашэнне                                                                                                                                  |
|-----------------------|----------------------|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Прылада не бачная     | Любая                | Любая                 | Упэўніцеся, што на маршрутызатары адключана ізаляцыя пунктаў доступу. Калі яна ўключана, злучэнні паміж прыладамі забаронены.            |
| Прылада не бачная     | Любая                | Windows               | Упэўніцеся, што сетка наладжана як «прыватная». Для сетак, наладжаных як агульнадаступныя, Windows можа быць больш строгай.              |
| Прылада не бачная     | macOS, iOS           | Любая                 | Паспрабуйце пераключыць дазвол «Лакальная сетка» ў раздзеле «Прыватнасць» у наладах сістэмы.                                              |
| Занадта нізкая хуткасць | Любая              | Любая                 | Карыстайцеся 5 ГГц; адключыце шыфраванне на абедзвюх прыладах                                                                            |
| Занадта нізкая хуткасць | Любая              | Android               | Вядомая праблема. https://github.com/flutter-cavalry/saf_stream/issues/4                                                                |

## Зборка

Гэтыя каманды прызначаны толькі для тых, хто вядзе праект. Выконвайце іх з папкі `app`.

### Android

Звычайны APK

```bash
flutter build apk
```

AppBundle для Google Play

```bash
flutter build appbundle
```

### iOS

```bash
flutter build ipa
```

### macOS

```bash
flutter build macos
```

### Windows

**Звычайная**

```bash
flutter build windows
```

**Лакальная праграма MSIX**

```bash
flutter pub run msix:create
```

**Гатовая для крамы**

```bash
flutter pub run msix:create --store
```

### Linux

**Звычайная**

```bash
flutter build linux
```

**AppImage**

```bash
appimage-builder --recipe AppImageBuilder.yml
```

**Snap**

Інструкцыі ў [relay/snap/README.md](https://github.com/relay/snap/blob/main/README.md)

## Суаўтары

<a href="https://github.com/relay/relay/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=relay/relay"  alt="Relay Contributors"/>
</a>
