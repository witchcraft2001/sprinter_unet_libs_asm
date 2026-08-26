# sprinter_unet_libs_asm

Биндинги и примеры для Z80/SjASMPlus для поддержки сети UNET в проекте
Sprinter (Z80 / DSS). Бекенд-DLL, замороженный ABI и справочник API живут в
[sprinter_unet_libs_core](https://github.com/witchcraft2001/sprinter_unet_libs_core)
(подключается как `extern/core`); этот репозиторий добавляет:

- [libman](https://github.com/witchcraft2001/sprinter-libman) вложенным
  git-сабмодулем - загрузчик/диспетчер DLL, под который собраны оба
  бекенда;
- `include/unetld.asm` - небольшой include для SjASMPlus, который читает
  переменную среды `NET`, загружает соответствующую DLL, проверяет её и
  даёт тонкую обёртку вызова плюс жизненный цикл NETINIT/NETDONE - см.
  [docs/UNETLDRU.md](docs/UNETLDRU.md) (asm-специфичный справочник) и
  [UNETLD-SPECRU.md из core](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/docs/UNETLD-SPECRU.md)
  (языко-нейтральная спецификация поведения);
- четыре рабочих примера (`NETINFO`, `PING`, `HTTPGET`, `UDPECHO`).

Инструментарий: [sjasmplus](https://github.com/z00m128/sjasmplus). Биндинги
для Pascal и Solid C живут в своих отдельных репозиториях,
[sprinter_unet_libs_pascal](https://github.com/witchcraft2001/sprinter_unet_libs_pascal)
и [sprinter_unet_libs_c](https://github.com/witchcraft2001/sprinter_unet_libs_c).

Вся документация ведётся на двух языках; английские версии - без суффикса
`RU`: [README.md](README.md), [docs/UNETLD.md](docs/UNETLD.md).

## Подключение как сабмодуля

```sh
git submodule add https://github.com/witchcraft2001/sprinter_unet_libs_asm.git extern/unet_libs_asm
```

Клонировать (или обновлять) нужно рекурсивно, чтобы подтянулись и вложенные
сабмодули `libman` и `core`:

```sh
git clone --recursive <ваш-репозиторий>
# или в уже существующем чекауте:
git submodule update --init --recursive
```

## Интеграция сборки

Добавьте три пути `-I` в вызов `sjasmplus`:

```sh
sjasmplus -I extern/unet_libs_asm/include -I extern/unet_libs_asm/extern/core/bindings/asm -I extern/unet_libs_asm/extern/libman/libman ...
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

У `unetld.asm` два режима размещения состояния - выбор и точный контракт
описаны в [docs/UNETLDRU.md](docs/UNETLDRU.md#два-режима-размещения-состояния).
Коротко: самый простой вариант - включить без
дополнительной настройки (состояние ~315 байт едет прямо в образе EXE),
либо задать `DEFINE UNETLD_STATE_BASE <адрес>` заранее для сборки без этих
315 байт (и один раз вызвать `UNETLD.RESET` перед любым другим вызовом).
Все четыре примера в этом репозитории - рабочие эталоны для обоих режимов:
`examples/netinfo` использует простой, остальные три - компактный.

Поскольку `libman.asm` подключает ваша программа, полный API
`LIBMAN.l_load`/`l_call`/`l_info`/`l_free` остаётся доступен вашему коду
для загрузки собственных DLL (шрифты, графика, ...) параллельно с
UNET-бекендом - достаточно поднять `LIBMAN_MAX_LIBS` до числа одновременно
загруженных DLL. См.
[docs/UNETLDRU.md](docs/UNETLDRU.md#загрузка-собственных-dll-рядом-с-unet).

Скопируйте `extern/core/dll/UNETESP.DLL` и `extern/core/dll/UNETRTL.DLL`
рядом с собранным EXE (или в образ дискеты/zip своего дистрибутива) -
libman ищет простое имя DLL сначала в каталоге EXE (через DSS `APPINFO`),
затем в текущем каталоге. Обе DLL можно не поставлять, если нужен только
один бекенд, но именно совместная поставка обеих позволяет одному и тому
же EXE работать с любой картой.

## Переменные среды и правила работы с памятью

Оба вопроса - свойства самого UNET ABI, а не этого репозитория - см.
[README core](https://github.com/witchcraft2001/sprinter_unet_libs_core#переменные-среды)
про правила выбора `NET` и инструменты настройки, и
[правила работы с памятью в core](https://github.com/witchcraft2001/sprinter_unet_libs_core#правила-работы-с-памятью)
про ограничения по окнам и буферам. Одно asm-специфичное добавление сверх
них: для любого вызова `RST 0x10`/`RST 0x08` (DSS/BIOS) `SP` обязан быть в
диапазоне `0x8000`-`0xBFFF`, а `HL'`/`DE'`/`BC'` зарезервированы DSS/BIOS -
никогда не делайте `EXX` вокруг вызова DSS.

## Сборка и запуск примеров

```sh
make            # собрать все четыре примера в build/
make netinfo    # или только один
make check      # сверить вендоренные DLL с extern/core/dll/manifest.json
make image      # собрать + записать distr/unet_libs_asm.img (FAT12, для
                # эмулятора или настоящей дискеты)
make package    # собрать + записать distr/unet_libs_asm.zip
```

Нужен `sjasmplus` в `PATH` (для всех целей) и `mtools` + `iconv` (только для
`image`). Порядок проверки после настройки бекенда - достаточно запустить
его инструмент настройки (`NETUP` либо `NETCFG -i` + `IFUP`): он сам
опубликует `NET`, вручную эту переменную задавать не нужно:

```
NETINFO                      - бекенд, возможности, ABI, IP/MAC/...
PING 8.8.8.8                 - четыре пинга
HTTPGET info.cern.ch         - обычный HTTP GET, вывод ответа
UDPECHO <хост> 7777          - в паре с `python3 extern/core/tools/udp_echo.py`
```

Матрица ручного тестирования (первые две строки не требуют железа).
Строки с `SET NET=...` - намеренная инъекция ошибок для проверки
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

## Обновление вендоренных DLL и ABI

Оба теперь живут в `sprinter_unet_libs_core` - см.
[README core](https://github.com/witchcraft2001/sprinter_unet_libs_core#обновление-вендоренных-dll)
про `update_dlls.sh` и про работу с источником истины ABI
(`abi/unet_abi.toml` + `gen_bindings.py`). После обновления core обновите
здесь указатель сабмодуля `extern/core`.

## Лицензия

BSD 3-Clause, см. [LICENSE](LICENSE). Вендоренные DLL остаются под
лицензиями своих родительских проектов - происхождение указано в
`extern/core/dll/manifest.json`.
