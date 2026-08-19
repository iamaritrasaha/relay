# Relay

[![CI status][ci-badge]][ci-workflow]

[ci-badge]: https://github.com/relay/relay/actions/workflows/ci.yml/badge.svg
[ci-workflow]: https://github.com/relay/relay/actions/workflows/ci.yml

[Ana Sayfa][homepage] • [Discord][discord] • [GitHub][github] • [Codeberg][codeberg]

[English (Default)](/README.md) • [Español](README_ES.md) • [فارسی](README_FA.md) • [Filipino](README_PH.md) • [Français](README_FR.md) • [Indonesia](README_ID.md) • [Italiano](README_IT.md) • [日本語](README_JA.md) • [ភាសាខ្មែរ](README_KM.md) • [한국어](README_KO.md) • [Polski](README_PL.md) • [Português Brasil](README_PT_BR.md) • [Русский](README_RU.md) • [ภาษาไทย](README_TH.md) • [Turkish](README_TR.md) • [Українська](README_UK.md) • [Tiếng Việt](README_VI.md) • [中文](README_ZH.md)

[homepage]: https://relay.org
[discord]: https://discord.gg/GSRWmQNP87
[github]: https://github.com/relay/relay
[codeberg]: https://codeberg.org/relay/relay

Relay, internet bağlantısına ihtiyaç duymadan, yerel ağ üzerinden yakın cihazlarla güvenli bir şekilde dosya ve mesaj paylaşmanıza olanak tanıyan ücretsiz, açık kaynaklı bir uygulamadır.

- [Hakkında](#hakkında)
- [Ekran Görüntüleri](#ekran-görüntüleri)
- [İndir](#i̇ndir)
- [Nasıl Çalışır](#nasıl-çalışır)
- [Başlarken](#başlarken)
- [Katkıda Bulunma](#katkıda-bulunma)
  - [Çeviri](#çeviri)
  - [Hata Düzeltmeleri ve İyileştirmeler](#hata-düzeltmeleri-ve-i̇yileştirmeler)
- [Sorun Giderme](#sorun-giderme)
- [Derleme](#derleme)
  - [Android](#android)
  - [iOS](#ios)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Linux](#linux)
- [Katkıda Bulunanlar](#katkıda-bulunanlar)

## Hakkında

Relay, cihazlar arasında güvenli iletişim sağlamak için REST API ve HTTPS şifrelemesi kullanan, çoklu platform desteğine sahip bir uygulamadır. Diğer mesajlaşma uygulamalarının dış sunuculara bağımlı olmasının aksine, Relay internet bağlantısına veya üçüncü taraf sunuculara ihtiyaç duymaz; bu da yerel iletişim için hızlı ve güvenilir bir çözüm sunar.

## Ekran Görüntüleri

<img src="https://relay.org/img/screenshot-iphone.webp" alt="iPhone screenshot" height="300"/> <img src="https://relay.org/img/screenshot-pc.webp" alt="PC screenshot" height="300"/>

## İndir

Uygulamayı, otomatik güncelleme özelliği olmadığı için bir uygulama mağazasından veya bir paket yöneticisinden indirmeniz önerilir.

| Windows                 | macOS                   | Linux              | Android        | iOS           | Fire OS    |
| ----------------------- | ----------------------- | ------------------ | -------------- | ------------- | ---------- |
| [Winget][]              | [App Store][]           | [Flathub][]        | [Play Store][] | [App Store][] | [Amazon][] |
| [Scoop][]               | [Homebrew][]            | [Nixpkgs][]        | [F-Droid][]    |               |            |
| [Chocolatey][]          | [DMG Installer][latest] | [Snap][]           | [APK][latest]  |               |            |
| [EXE Installer][latest] |                         | [AUR][]            |                |               |            |
| [Portable ZIP][latest]  |                         | [TAR][latest]      |                |               |            |
|                         |                         | [DEB][latest]      |                |               |            |
|                         |                         | [AppImage][latest] |                |               |            |

Hakkında daha fazla bilgi edinin [distribution channels][].

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
[distribution channels]: https://github.com/relay/relay/blob/main/CONTRIBUTING.md#distribution

**Uyumluluk**

| Platform | Minimum Sürüm | Not                                                                                                                               |
| -------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Android  | 5.0           | -                                                                                                                                 |
| iOS      | 12.0          | -                                                                                                                                 |
| macOS    | 11 Big Sur    | OpenCore Legacy Patcher 2.0.2 kullanın (Bkz. [#1005](https://github.com/relay/relay/issues/1005#issuecomment-2449899384)) |
| Windows  | 10            | Windows 7'yi destekleyen son sürüm v1.15.4’tür. Daha yeni sürümler için Windows 7'ye yönelik backport'lar olabilir.               |
| Linux    | N.A.          | -                                                                                                                                 |

## Kurulum

Çoğu durumda, Relay kutudan çıkar çıkmaz çalışmalıdır. Ancak, dosya gönderme veya alma konusunda sorun yaşıyorsanız, Relay'in yerel ağ üzerinden iletişim kurabilmesi için güvenlik duvarınızı yapılandırmanız gerekebilir.

| Trafik Türü | Protokol | Port     | Aksiyon  |
| ----------- | -------- | -------- | -------- |
| Gelen       | TCP, UDP | 53317    | İzin Ver |
| Giden       | TCP, UDP | Herhangi | İzin Ver |

Ayrıca, yönlendiricinizde AP izolasyonunu devre dışı bıraktığınızdan emin olun. Genellikle varsayılan olarak devre dışı olmalıdır, ancak bazı yönlendiriciler bunu etkinleştirmiş olabilir (özellikle misafir ağlarında).

**Taşınabilir Mod**

(v1.13.0 sürümünde tanıtıldı)

Çalıştırılabilir dosyayla aynı dizinde `settings.json` adında bir dosya oluşturun.
Bu dosya boş olabilir.
Uygulama, ayarları varsayılan konum yerine bu dosyada saklamak için bu dosyayı kullanacaktır.

**Gizli Başlat**

(v1.15.0 sürümünde güncellendi)

Uygulamayı gizli başlatmak için (yalnızca sistem tepsisinde), `--hidden` bayrağını kullanın (örnek: `relay.exe --hidden`).

v1.14.0 ve önceki sürümlerde, `autostart` bayrağı ayarlandığında ve gizli ayarı etkinleştirildiğinde uygulama gizli başlar.

## Nasıl Çalışır

Relay, cihazların birbirleriyle iletişim kurmasını sağlayan güvenli bir iletişim protokolü kullanır ve bu iletişim REST API aracılığıyla gerçekleştirilir. Tüm veriler HTTPS üzerinden güvenli bir şekilde iletilir ve her cihazda anlık olarak oluşturulan TLS/SSL sertifikası ile maksimum güvenlik sağlanır.

Relay Protokolü hakkında daha fazla bilgi için [dökümantasyon](https://github.com/relay/protocol).

## Başlarken

Relay'i kaynak kodundan derlemek için şu adımları izleyin:

1. Flutter'ı [doğrudan](https://flutter.dev) veya [fvm](https://fvm.app) kullanarak kurun (gerekli [sürüm](.fvmrc) için bakın.)
2. [Rust'ı](https://www.rust-lang.org/tools/install) yükleyin
3. `Relay` reposunu klonlayın.
4. `cd app` komutunu çalıştırarak uygulama dizinine girin.
5. Bağımlılıkları indirmek için `flutter pub get` komutunu çalıştırın
6. Uygulamayı başlatmak için `flutter run` komutunu çalıştırın

> [!NOT]
> Relay, şu anda daha eski bir Flutter sürümünü gerektiriyor(gerekli sürüm [.fvmrc](.fvmrc) dosyasında belirtilmiştir)
> bu nedenle gerekli sürüm ile (sistem genelinde) yüklü olan Flutter sürümü arasındaki uyumsuzluk derleme sorunlarına yol açabilir.
> Geliştirmeyi daha tutarlı hale getirmek için Relay, proje Flutter sürümünü yönetmek için [fvm](https://fvm.app) kullanır.
> `fvm`'yi kurduktan sonra, `flutter` yerine `fvm flutter` komutunu çalıştırın.

## Katkıda Bulunma

Relay'i geliştirmekle ilgilenen herkesten katkı bekliyoruz. Katkıda bulunmak isterseniz, dahil olmanın birkaç yolu vardır:

### Çeviri

Relay'i diğer dillere çevirmeye yardımcı olabilirsiniz! **Önerilen yöntem**: Çevirileri yönetmek için [Weblate](https://hosted.weblate.org/projects/relay/app) platformunu kullanın.

**Alternatif**: Bu depoyu fork'layarak ve çevirileri manuel olarak ekleyerek de katkıda bulunabilirsiniz.

Çeviriler [app/assets/i18n](https://github.com/relay/relay/tree/main/app/assets/i18n) dizininde bulunmaktadır. Çeviri eklemek veya güncellemek için `_missing_translations_<locale>.json` veya `strings_<locale>.i18n.json` dosyasını düzenleyebilirsiniz.

<a href="https://hosted.weblate.org/engage/relay/">
<img src="https://hosted.weblate.org/widget/relay/app/multi-auto.svg" alt="Çeviri durumu" />
</a>

**_Take note:_ `@` ile süslenmiş alanlar çevrilmek için değildir; bu alanlar uygulamada herhangi bir şekilde kullanılmaz, yalnızca dosya hakkında bilgi veren veya çevirmen için bağlam sağlayan bilgilendirici metinlerdir.**

### Hata Düzeltmeleri ve İyileştirmeler

- **Hata Düzeltmeleri:** Bir hata bulursanız, lütfen sorunun ve nasıl düzeltileceğinin açık bir tanımıyla bir pull request oluşturun.
- **İyileştirmeler:** Relay'i geliştirmek için bir fikriniz var mı? Lütfen önce neden bu iyileştirmenin gerekli olduğunu tartışmak için bir issue oluşturun.

Daha fazla bilgi için [katkı sağlama kılavuzuna](https://github.com/relay/relay/blob/main/CONTRIBUTING.md) bakın.

## Sorun Giderme

| Sorun            | Platform (Gönderici)  | Platform (Alıcı)      | Çözüm                                                                                                                                  |
| ---------------- | --------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Cihaz görünmüyor | Herhangi bir platform | Herhangi bir platform | Yönlendiricinizde AP-İzolasyonunu devre dışı bıraktığınızdan emin olun. Bu özellik etkinse cihazlar arası bağlantılar engellenir.      |
| Cihaz görünmüyor | Herhangi bir platform | Windows               | Ağınızı "özel" bir ağ olarak yapılandırdığınızdan emin olun. Windows, ağ "genel" olarak yapılandırıldığında daha kısıtlayıcı olabilir. |
| Cihaz görünmüyor | macOS, iOS            | Herhangi bir platform | İşletim sistemi ayarlarında "Gizlilik" altında "Yerel Ağ" iznini açıp kapatmayı deneyebilirsiniz.                                      |
| Hız çok yavaş    | Herhangi bir platform | Herhangi bir platform | 5 Ghz kullanın; her iki cihazda da şifrelemeyi devre dışı bırakın.                                                                     |
| Hız çok yavaş    | Herhangi bir platform | Android               | Bilinen bir sorun. https://github.com/flutter-cavalry/saf_stream/issues/4                                                              |

