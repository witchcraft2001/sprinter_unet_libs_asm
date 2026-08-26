# sprinter_unet_libs_asm

Единая точка подключения поддержки сети UNET в проект Sprinter (Z80 / DSS)
в виде git-сабмодуля. В комплекте:

- готовые бинарники бекендов `UNETESP.DLL` (WiFi/ESP8266) и `UNETRTL.DLL`
  (ISA-карта RTL8019A) — оба реализуют один замороженный
  [UNET ABI](docs/UNETAPIRU.md);
- [libman](https://github.com/witchcraft2001/sprinter-libman) вложенным
  git-сабмодулем — загрузчик/диспетчер DLL, под который собраны оба
  бекенда;
- `include/unetld.asm` — небольшой include для SjASMPlus, который читает
  переменную среды `NET`, загружает соответствующую DLL, проверяет её и
  даёт тонкую обёртку вызова плюс жизненный цикл NETINIT/NETDONE — см.
  [docs/UNETLDRU.md](docs/UNETLDRU.md);
- четыре рабочих примера (`NETINFO`, `PING`, `HTTPGET`, `UDPECHO`).

Инструментарий: [sjasmplus](https://github.com/z00m128/sjasmplus). Проект
только на Z80 asm — биндинги для C/Pascal вынесены в отдельный проект.

Вся документация ведётся на двух языках; английские версии — без суффикса
`RU`: [README.md](README.md), [docs/UNETLD.md](docs/UNETLD.md),
[docs/UNETAPI.md](docs/UNETAPI.md).

## Подключение как сабмодуля

```sh
git submodule add https://github.com/witchcraft2001/sprinter_unet_libs_asm.git extern/unet_libs_asm
```

Клонировать (или обновлять) нужно рекурсивно, чтобы подтянулся и вложенный
сабмодуль `libman`:

```sh
git clone --recursive <ваш-репозиторий>
# или в уже существующем чекауте:
git submodule update --init --recursive
```

## Интеграция сборки

Добавьте два пути `-I` в вызов `sjasmplus`:

```sh
sjasmplus -I extern/unet_libs_asm/include -I extern/unet_libs_asm/extern/libman/libman ...
```

Затем в исходнике задайте опции libman через DEFINE *до* его подключения, а
`unetld.asm` подключите ВНЕ своего `MODULE` (он открывает собственный
`MODULE UNETLD`):

```asm
        DEVICE  NOSLOT64K
        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        DEFINE  LIBMAN_DIAGNOSTICS      ; необязательно, но рекомендуется:
                                        ; даёт LIBMAN.l_reason/l_dss_error/...
                                        ; при неудачной загрузке
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  MYAPP
        ; ... ваша программа, включая вызовы UNETLD.* ...
        ENDMODULE

        INCLUDE "unetld.asm"
        INCLUDE "libman.asm"
```

У `unetld.asm` два режима размещения состояния — выбор и точный контракт
описаны в [docs/UNETLDRU.md](docs/UNETLDRU.md#два-режима-размещения-состояния).
Коротко: самый простой вариант — включить без
дополнительной настройки (состояние ~315 байт едет прямо в образе EXE),
либо задать `DEFINE UNETLD_STATE_BASE <адрес>` заранее для сборки без этих
315 байт (и один раз вызвать `UNETLD.RESET` перед любым другим вызовом).
Все четыре примера в этом репозитории — рабочие эталоны для обоих режимов:
`examples/netinfo` использует простой, остальные три — компактный.

Поскольку `libman.asm` подключает ваша программа, полный API
`LIBMAN.l_load`/`l_call`/`l_info`/`l_free` остаётся доступен вашему коду
для загрузки собственных DLL (шрифты, графика, ...) параллельно с
UNET-бекендом — достаточно поднять `LIBMAN_MAX_LIBS` до числа одновременно
загруженных DLL. См.
[docs/UNETLDRU.md](docs/UNETLDRU.md#загрузка-собственных-dll-рядом-с-unet).

Скопируйте `dll/UNETESP.DLL` и `dll/UNETRTL.DLL` рядом с собранным EXE (или
в образ дискеты/zip своего дистрибутива) — libman ищет простое имя DLL
сначала в каталоге EXE (через DSS `APPINFO`), затем в текущем каталоге. Обе
DLL можно не поставлять, если нужен только один бекенд, но именно
совместная поставка обеих позволяет одному и тому же EXE работать с любой
картой.

## Переменные среды

`NET` выбирает бекенд: её значение (3–4 символа, `[A-Z0-9]`, регистр не
важен) напрямую становится именем DLL — `NET=RTL` загружает
`UNETRTL.DLL`, `NET=WIZ` загрузил бы `UNETWIZ.DLL` и так далее. `WIFI` —
единственное встроенное исключение, алиас на `UNETESP.DLL` для
совместимости с существующими инструментами. Как в эту схему добавить
новый бекенд — см.
[docs/UNETLDRU.md](docs/UNETLDRU.md#добавление-бекенда).

`NET` *публикуется инструментом настройки бекенда* вместе с остальной его
конфигурацией — пользователи (и программы-потребители) не задают её
вручную. Если переменной нет, правильное действие всегда «запустить
инструмент настройки», а не `SET NET=...`:

| Бекенд | Инструмент настройки | Публикует |
| --- | --- | --- |
| WiFi (`UNETESP.DLL`) | `NETUP` | `NET=WIFI`, `NET_ESP_*`, `NET_IP`/`NET_MASK`/`NET_GW`/`NET_MAC`/... |
| RTL8019A (`UNETRTL.DLL`) | `NETCFG -i`, затем `IFUP` | `NET=RTL`, `NET_RTL_*`, `NET_IP`/`NET_MASK`/`NET_GW`/`NET_MAC`/... |

Инструменты настройки берите из дистрибутива своего бекенда: `NETUP`
входит в комплект WiFi-кита
([sprinter_net](https://github.com/witchcraft2001/sprinter_net)),
`NETCFG`/`IFUP` — в комплект RTL-кита
([sprinter-rtl8019a](https://github.com/witchcraft2001/sprinter-rtl8019a)).
`UNET_FN_STATUS` с `A=0xFF` (именно это делает
`UNETLD.NETSTART` перед `NETINIT`) проверяет, что эта конфигурация
опубликована, не трогая железо — удобно для дружелюбного сообщения «сначала
запустите NETUP/IFUP». Полный список переменных и справочник функций UNET —
в [docs/UNETAPIRU.md](docs/UNETAPIRU.md).

## Правила работы с памятью

Взяты из самого UNET ABI (см. `include/unet.inc`) и из DSS:

- Загружать DLL только в окно 1 (`0x4000`) или окно 2 (`0x8000`) —
  **никогда в окно 3** (`0xC000`): бекенд ESP отображает туда железо на
  время каждого вызова.
- Любой буфер, переданный в функцию UNET (строки host/port, данные
  send/recv, назначение `GETINFO`), должен целиком лежать ниже `0xC000` и
  вне окна, куда загружена DLL.
- Строка host — не длиннее 128 байт, строка port — не длиннее 15 байт.
- На время вызова UNET должно оставаться не меньше ~256 байт свободного
  стека.
- UNET не реентерабелен — один вызов за раз.
- Для любого вызова `RST 0x10`/`RST 0x08` (DSS/BIOS) `SP` обязан быть в
  диапазоне `0x8000`–`0xBFFF`, а `HL'`/`DE'`/`BC'` зарезервированы
  DSS/BIOS — никогда не делайте `EXX` вокруг вызова DSS.

## Сборка и запуск примеров

```sh
make            # собрать все четыре примера в build/
make netinfo    # или только один
make check      # сверить вендоренные DLL с dll/manifest.json
make image      # собрать + записать distr/unet_libs_asm.img (FAT12, для
                # эмулятора или настоящей дискеты)
make package    # собрать + записать distr/unet_libs_asm.zip
```

Нужен `sjasmplus` в `PATH` (для всех целей) и `mtools` + `iconv` (только для
`image`). Порядок проверки после настройки бекенда — достаточно запустить
его инструмент настройки (`NETUP` либо `NETCFG -i` + `IFUP`): он сам
опубликует `NET`, вручную эту переменную задавать не нужно:

```
NETINFO                      - бекенд, возможности, ABI, IP/MAC/...
PING 8.8.8.8                 - четыре пинга
HTTPGET info.cern.ch         - обычный HTTP GET, вывод ответа
UDPECHO <хост> 7777          - в паре с `python3 tools/udp_echo.py`
```

Матрица ручного тестирования (первые две строки не требуют железа).
Строки с `SET NET=...` — намеренная инъекция ошибок для проверки
диагностики; в нормальной работе `NET` публикует только инструмент
настройки:

| Сценарий | Ожидаемый результат |
| --- | --- |
| `NET` не задана (инструмент настройки не запускался) | «NET is not set» + подсказка bring-up, код выхода 4 |
| `SET NET=XX` вручную (2 символа) | «NET has an invalid value: XX», код выхода 4 |
| `SET NET=FOO` вручную (валидная форма, такой DLL нет) | «Could not load UNETFOO.DLL» + диагностика libman, код выхода 2 |
| после `NETUP` | NETINFO показывает бекенд ESP, caps `0x031F` |
| после `NETCFG -i`/`IFUP` | NETINFO показывает бекенд RTL, caps `0x001F` |
| Esc во время сетевого ожидания | чистый выход с `NERR_CANCEL`; повторный запуск работает (UNLOAD идемпотентен) |

## Обновление вендоренных DLL

```sh
make update-dlls
```

Копирует свежие `UNETESP.DLL`/`UNETRTL.DLL` из соседних чекаутов проектов-
бекендов (переопределяется переменными среды `UNETESP_SRC`/`UNETRTL_SRC`),
обновляет size/sha256 в `dll/manifest.json` (поле `version` правьте
вручную), перезапускает проверку и предупреждает, если `include/unet.inc`
разошёлся с оригиналом, из которого он был вендорен.

Имя DLL в её L1-заголовке при загрузке сверяется только по префиксу
(`UNET` + ваш тег `NET`) — версия в суффиксе намеренно не фиксируется.
Настоящая build-time идентичность — это `sha256` в `dll/manifest.json`.

## Лицензия

BSD 3-Clause, см. [LICENSE](LICENSE). Вендоренные DLL остаются под
лицензиями своих родительских проектов — происхождение указано в
`dll/manifest.json`.
