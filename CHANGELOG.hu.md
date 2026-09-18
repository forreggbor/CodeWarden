# Változásnapló

A projekt összes jelentős változása ebben a fájlban van dokumentálva.

## [v1.08.01] - 2026-09-18

| Kategória   | Leírás                                                                          |
|-------------|-----------------------------------------------------------------------------------|
| Módosítva   | A `storage` és `doc` mappa alapból ki van zárva a vizsgálatból, mint a `vendor`/`database` |

### Módosítva
- A `storage` és `doc` mappák mostantól alapból ki vannak zárva a vizsgálatból, bármilyen
  mélységben — ugyanaz a "névre illesztve, a fa bármely pontján kizárva" szabály
  érvényes rájuk, mint eddig is a `vendor`, `database` és `locale` mappákra. Egy
  projektben nem várt, hogy ezekben vizsgálandó kód legyen, és pont ezek azok a helyek,
  ahol nagy bináris tartalom (mentések, generált PDF-ek, referenciaanyagok)
  felhalmozódik. Ez váltja fel a korábbi, csak gyökérszintű `storage/` utószűrést, ami a
  találatok közül kivette a storage-beli egyezéseket, de a vizsgálat addig még minden
  bájtjukat beolvasta.

## [v1.08.00] - 2026-09-18

| Kategória   | Leírás                                                                                |
|-------------|----------------------------------------------------------------------------------------|
| Hozzáadva   | `-L`/`--lib-locales`: a `lib/*/locale/{LANG}/messages.php` kulcsok is definiáltnak számítanak |
| Javítva     | A hiányzó-kulcs ellenőrzés többé nem jelez fordítási kulcsnak nem számító string literálokat |
| Javítva     | A hiányzó-kulcs ellenőrzés felismeri a `'PREFIX' . $var . 'SUFFIX'` összefűzést        |
| Javítva     | A vizsgálat nagy bináris tartalmú projekteken sem akadhat percekig                     |

### Hozzáadva
- Új `-L`/`--lib-locales` kapcsoló: a `lib/*/locale/{LANG}/messages.php` fájlokat (a
  Reusables vendorolt-modul konvenció) is érvényes kulcs-definíciónak tekinti a Missing,
  Dynamic Matches és Duplicate Definitions ellenőrzésekhez. Szándékosan nem érinti a
  Sync Check-et (az a projekt saját HU/EN párosítására korlátozódik marad) és az Unused
  ellenőrzést sem (egy modul kulcsa, amit ez a projekt nem használ, más, ugyanazt a
  modult használó projektben még lehet élő — hogy "halott kód"-e, csak a modul saját
  forrásrepója szintjén dönthető el). Csak PHP-array projekteknél működik; Gettext
  projektnél a kapcsoló figyelmeztetéssel no-op.

### Javítva
- A kulcsdetektálás mostantól megköveteli, hogy a talált token egy egész, idézőjelek
  közötti string literál legyen, ne csak bármilyen `TEXT_` alakú karaktersorozat egy
  fájlban bárhol. Ez megszünteti a hamis "missing" jelzéseket olyan esetekben, amik
  sosem voltak fordítási hívások: PHPDoc példaszövegek, JS/PHP konstans-hivatkozások
  (`Node.TEXT_NODE`, `MyClass::TEXT_X`).
- A `'PREFIX' . $var . 'SUFFIX'` alakú string-összefűzést (amikor egy változó a két
  literál szegmens közé ékelődik) mostantól ugyanúgy dinamikus kulcs-építésként ismeri
  fel, mint a már korábban is kezelt `'PREFIX_' . $var` mintát. Korábban a literál
  `PREFIX` rész statikus, hiányzó kulcsként jelent meg még akkor is, ha a valódi
  (utótaggal ellátott) kulcsok léteztek.
- A rekurzív vizsgálat többé nem olvassa be teljesen a bináris fájlok (mentések, PDF-ek,
  képek, archívumok) tartalmát kulcskeresés céljából. Egy projekt, amely több
  gigabájtnyi ilyen tartalmat tart egy vizsgált útvonal alatt, korábban egy másodperc
  alatti vizsgálatot sok perces vagy beragadni látszó futássá változtathatott.

## [v1.07.00] - 2026-06-02

| Kategória   | Leírás                                                                              |
|-------------|-------------------------------------------------------------------------------------|
| Hozzáadva   | Animált folyamatjelző az összes aktív szekcióhoz                                    |
| Hozzáadva   | Twig- és SQL-fájlok is vizsgálva a fordítási kulcsok használatára                   |
| Módosítva   | A PHP-FPM újraindítása automatikusan felismeri a futó verziót                       |

### Hozzáadva
- Animált braille-pörgettyű jelzi a folyamatot a hosszabb műveletek során (fordítási elemzés, PO fordítás, FPM újraindítás, tulajdonos- és jogosultságbeállítás, gazdagépnév-változtatás); minden szekció saját felirattal mutatja az éppen futó lépést
- A pörgettyű kizárólag a hibakimenetre (stderr) ír — az elemzési jelentés és a fájlba mentett kimenet (`-f`) nem változik
- Ha a hibakimenet nem interaktív terminál (CI, cső, átirányítás): egyszerű szöveges feliratot ír, ANSI escape kódok nélkül
- A kurzor automatikusan visszaáll kilépéskor, megszakításkor (Ctrl-C) és leállítási jelzés esetén — nem marad háttérfolyamat és nem marad rejtett kurzor
- A Twig-sablonokban (`.twig`) talált fordítási kulcsok mostantól használtnak számítanak, nem kerülnek árva kulcsként jelölésre
- Az SQL-fájlokban (`.sql`) adatértékként tárolt fordítási kulcsok szintén használtnak számítanak, séma- és migrációs fájlokban egyaránt

### Módosítva
- A PHP-FPM újraindítása (`-r`) automatikusan megkeresi a futó FPM-szolgáltatás nevét a hardkódolt `php8.4-fpm` helyett; a legmagasabb verziószámú futó példányt választja, visszaesési lehetőséggel az aktív, majd a telepített egységekre
