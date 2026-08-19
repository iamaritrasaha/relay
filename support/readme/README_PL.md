# Relay

[![CI status][ci-badge]][ci-workflow]

[ci-badge]: https://github.com/relay/relay/actions/workflows/ci.yml/badge.svg
[ci-workflow]: https://github.com/relay/relay/actions/workflows/ci.yml

[Strona główna][homepage] • [Discord][discord] • [GitHub][github] • [Codeberg][codeberg]

[English (Default)](/README.md) • [Español](README_ES.md) • [فارسی](README_FA.md) • [Filipino](README_PH.md) • [Français](README_FR.md) • [Indonesia](README_ID.md) • [Italiano](README_IT.md) • [日本語](README_JA.md) • [ភាសាខ្មែរ](README_KM.md) • [한국어](README_KO.md) • [Polski](README_PL.md) • [Português Brasil](README_PT_BR.md) • [Русский](README_RU.md) • [ภาษาไทย](README_TH.md) • [Turkish](README_TR.md) • [Українська](README_UK.md) • [Tiếng Việt](README_VI.md) • [中文](README_ZH.md)

[homepage]: https://relay.org
[discord]: https://discord.gg/GSRWmQNP87
[github]: https://github.com/relay/relay
[codeberg]: https://codeberg.org/relay/relay

Relay jest darmową, otwartoźródłową aplikacją, która umożliwia Ci bezpiecznie udostępnianie plików oraz wiadomości pobliskim urządzeniom w Twojej sieci lokalnej bez konieczności połączenia z internetem.

- [O projekcie](#O-projekcie)
- [Zrzuty ekranu](#Zrzuty-ekranu)
- [Pobieranie](#Pobieranie)
- [Jak to działa?](#Jak-to-działa)
- [Pierwsze kroki](#Pierwsze-kroki)
- [Wnoszenie wkładu](#Wnoszenie-wkładu)
  - [Tłumaczenie](#Tłumaczenie)
  - [Poprawki błędów i ulepszenia](#Poprawki-błędów-i-ulepszenia)
- [Budowanie](#Budowanie)
  - [Android](#android)
  - [iOS](#ios)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Linux](#linux)

## O projekcie

Relay jest wieloplatformową aplikacją, która umożliwia bezpieczną komunikację między urządzeniami przy użyciu REST API oraz szyfrowania HTTPS. W przeciwieństwie do innych aplikacji, które bazują na zewnętrznych serwerach, Relay nie wymaga połączenia z internetem ani serwerów osób trzecich, co czyni go szybkim i niezawodnym rozwiązaniem dla lokalnej komunikacji.

## Zrzuty ekranu

<img src="https://relay.org/img/screenshot-iphone.webp" alt="iPhone screenshot" height="300"/> <img src="https://relay.org/img/screenshot-pc.webp" alt="PC screenshot" height="300"/>

## Pobieranie

Zaleca się pobranie aplikacji ze sklepu z aplikacjami albo menedżera paczek, ponieważ aplikacja nie posiada automatycznych aktualizacji.

| Windows                 | macOS                   | Linux              | Android        | iOS           | Fire OS    |
|-------------------------|-------------------------|--------------------|----------------|---------------|------------|
| [Winget][]              | [App Store][]           | [Flathub][]        | [Sklep Play][] | [App Store][] | [Amazon][] |
| [Scoop][]               | [Homebrew][]            | [Nixpkgs][]        | [F-Droid][]    |               |            |
| [Chocolatey][]          | [DMG Installer][latest] | [Snap][]           | [APK][latest]  |               |            |
| [EXE Installer][latest] |                         | [AUR][]            |                |               |            |
| [Portable ZIP][latest]  |                         | [TAR][latest]      |                |               |            |
|                         |                         | [DEB][latest]      |                |               |            |
|                         |                         | [AppImage][latest] |                |               |            |

Dowiedz się więcej o [kanałach dystrybucji][].

[windows store]: https://www.microsoft.com/store/apps/9NCB4Z0TZ6RR
[app store]: https://apps.apple.com/us/app/relay/id1661733229
[sklep play]: https://play.google.com/store/apps/details?id=com.foresight.app.relay
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
[kanałach dystrybucji]: https://github.com/relay/relay/blob/main/CONTRIBUTING.md#distribution

**Kompatybilność**

| Platforma | Minimalna Wersja | Uwaga                                                                                                                       |
|-----------|------------------|-----------------------------------------------------------------------------------------------------------------------------|
| Android   | 5.0              | -                                                                                                                           |
| iOS       | 12.0             | -                                                                                                                           |
| macOS     | 11 Big Sur       | Użyj OpenCore Legacy Patcher 2.0.2 (Zobacz [#1005](https://github.com/relay/relay/issues/1005#issuecomment-2449899384)) |
| Windows   | 10               | Ostatnia wersja wspierająca Windows 7 to v1.15.4. W przyszłości mogą pojawić się backporty nowszych wersji dla Windows 7.   |
| Linux     | N.A.             | Zależności: Gnome: `xdg-desktop-portal` i `xdg-desktop-portal-gtk`, KDE: `xdg-desktop-portal` i `xdg-desktop-portal-kde`    |

## Instalacja

W większości przypadków Relay powinien działać od razu po instalacji. Jednakże, jeśli masz problemy z wysyłaniem lub odbieraniem plików, może być konieczne skonfigurowanie Twojej zapory sieciowej, aby umożliwić Relay komunikację przez sieć lokalną.

| Typ ruchu    | Protokół | Port    | Akcja  |
|--------------|----------|---------|--------|
| Przychodzący | TCP, UDP | 53317   | Zezwól |
| Wychodzący   | TCP, UDP | każdy   | Zezwól |

Również, upewnij się, że izolacja klientów na Twoim routerze jest wyłączona. Zwykle powinna być ona domyślnie wyłączona, ale niektóre routery mogą mieć ją włączoną (szczególnie sieci gościnne).

**Tryb przenośny (portable)**

(Wprowadzony w v1.13.0)

Stwórz plik o nazwie `settings.json` znajdujący się w tym samym katalogu, co plik wykonywalny.
Plik może być pusty.
Aplikacja będzie używać tego pliku do przechowywania ustawień zamiast domyślnej lokalizacji.

**Uruchom w zasobniku (w tle)**

(Zaktualizowano w v1.15.0)

Aby uruchomić aplikację do zasobnika, użyj flagi `--hidden` (przykład: `relay.exe --hidden`).

W wersji v1.14.0 i wcześniejszych aplikacja uruchamia się do zasobnika, jeśli ustawiona jest flaga `autostart`, a ustawienie uruchamiania do zasobnika jest włączone.

## Jak to działa?

Relay korzysta z bezpiecznego protokołu komunikacyjnego, który pozwala urządzeniom komunikować się ze sobą za pomocą interfejsu API REST. Wszystkie dane są bezpiecznie przesyłane przez HTTPS, a certyfikat TLS/SSL jest generowany automatycznie na każdym urządzeniu, gwarantując maksymalne bezpieczeństwo.

Więcej informacji na temat protokołu Relay można znaleźć w [dokumentacji](https://github.com/relay/protocol).

## Pierwsze kroki

Aby skompilować Relay z kodu źródłowego, wykonaj następujące czynności:

1. Zainstaluj Flutter [bezpośrednio](https://flutter.dev) lub używając [fvm](https://fvm.app) (zobacz [wymaganą wersję](.fvmrc))
2. Sklonuj repozytorium `Relay`
3. Wykonaj `cd app`, aby wejść do katalogu `app`
4. Wykonaj `flutter pub get`, aby pobrać zależności
5. Wykonaj `flutter run`, aby uruchomić aplikację

> [!NOTE]
> Relay obecnie wymaga starszej wersji Fluttera (określonej w [.fvmrc](.fvmrc))
> a tym samym problemy z kompilacją mogą być spowodowane niedopasowaniem wymaganej i zainstalowanej (w obrębie całego systemu) wersji Fluttera.  
> Aby uczynić rozwój bardziej spójnym, Relay używa [fvm](https://fvm.app) do zarządzania wersją projektu Flutter.
> Po zainstalowaniu `fvm`, wykonaj `fvm flutter` zamiast `flutter`.

## Wnoszenie wkładu

Zapraszamy wszystkich tych, którzy chcą pomóc w ulepszaniu Relay. Jeśli chcesz wnieść swój wkład, możesz zaangażować się na kilka sposobów:

### Tłumaczenie

Możesz pomóc tłumaczyć Relay na inne języki! **Rekomendowana metoda**: Używaj platformy [Weblate](https://hosted.weblate.org/projects/relay/app) do zarządzania tłumaczeniami.

**Alternatywnie**: Możesz również wnieść wkład rozwidlając to repozytorium i dodając tłumaczenia ręcznie.

Tłumaczenia znajdują się w katalogu [app/assets/i18n](https://github.com/relay/relay/tree/main/app/assets/i18n). Edytuj plik `_missing_translations_<locale>.json` lub `strings_<locale>.i18n.json`, aby dodać lub zaktualizować tłumaczenia.

<a href="https://hosted.weblate.org/engage/relay/">
<img src="https://hosted.weblate.org/widget/relay/app/multi-auto.svg" alt="Status tłumaczenia" />
</a>

**_Zwróć uwagę:_ Pola oznaczone `@` nie są przeznaczone do tłumaczenia; nie są one używane w aplikacji w żaden sposób, będąc jedynie tekstem informacyjnym o pliku lub w celu nadania kontekstu tłumaczowi.**

### Poprawki błędów i ulepszenia

- **Poprawki błędów:** Jeśli znajdziesz błąd, utwórz pull request z jasnym opisem błędu i sposobem jego naprawienia.
- **Ulepszenia:** Masz pomysł, jak ulepszyć Relay? Najpierw utwórz problem, aby przedyskutować, dlaczego ulepszenie jest potrzebne.

Więcej informacji można znaleźć w [przewodniku dla współtwórców](https://github.com/relay/relay/blob/main/CONTRIBUTING.md).

## Rozwiązywanie problemów

| Problem              | Platforma (Wysyłanie) | Platforma (Odbiór) | Rozwiązanie                                                                                                                             |
|----------------------|-----------------------|--------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| Urządzenie niewidoczne | Dowolna               | Dowolna            | Upewnij się, że wyłączono izolację AP na routerze. Jeśli jest włączona, połączenia między urządzeniami są zabronione.                   |
| Urządzenie niewidoczne | Dowolna               | Windows            | Upewnij się, że skonfigurowałeś sieć jako sieć "prywatną". Windows może być bardziej restrykcyjny, gdy sieć jest skonfigurowana jako publiczna. |
| Urządzenie niewidoczne | macOS, iOS            | Dowolna            | Możesz spróbować przełączyć uprawnienie "Sieć lokalna" w "Prywatność" w ustawieniach systemu operacyjnego.                              |
| Za niska prędkość    | Dowolna               | Dowolna            | Użyj 5 GHz; Wyłącz szyfrowanie na obu urządzeniach                                                                                      |
| Za niska prędkość    | Dowolna               | Android            | Znany problem. https://github.com/flutter-cavalry/saf_stream/issues/4                                                                   |

