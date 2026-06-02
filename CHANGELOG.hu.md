# Változásnapló

A projekt összes jelentős változása ebben a fájlban van dokumentálva.

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
