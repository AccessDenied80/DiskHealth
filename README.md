# DiskHealth

Застосунок у рядку меню macOS для моніторингу стану дисків (на кшталт SSD Reporter).
Показує SMART-статус, знос, температуру, обсяг записаних даних, лічильники помилок та історію,
і надсилає системні сповіщення, коли диск починає деградувати.

Дані читає вбудований у `.app` `smartctl` зі [smartmontools](https://www.smartmontools.org/) (GPL-2.0).

## Збирання

Потрібні лише Command Line Tools (Xcode не обов'язковий) і `smartmontools` для копіювання `smartctl` у застосунок:

```bash
brew install smartmontools
scripts/build-app.sh
open build/DiskHealth.app
```

Інший бінарник `smartctl` (наприклад, universal): `scripts/build-app.sh --smartctl /шлях/до/smartctl`.

## Тести

```bash
scripts/test.sh
```

Скрипт додає шляхи до `Testing.framework` з Command Line Tools — звичайний `swift test` без Xcode його не знаходить.

## Перевірка вигляду без екрана

Debug-збірка вміє відрендерити вікна в PNG:

```bash
swift build && .build/debug/DiskHealth --snapshot /tmp/diskhealth-snap
```

## Обмеження

- `smartctl` копіюється з brew, тому працює лише на архітектурі цього Mac. Для Apple Silicon і Intel одночасно
  потрібна universal-збірка smartmontools із сирців.
- Зовнішні USB-диски: SMART доступний, лише якщо міст його пропускає. Деякі мости (наприклад, Realtek RTL9220)
  передають тільки загальний статус PASSED/FAILED без температури та зносу.
- Дані зберігаються в `~/Library/Application Support/DiskHealth/` (історія за 365 днів і стан сповіщень).
