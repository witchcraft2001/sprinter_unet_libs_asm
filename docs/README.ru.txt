sprinter_unet_libs_asm - примеры UNET

В этом наборе:

  NETINFO.EXE  - определяет сетевой бекенд по переменной NET, загружает
                 его DLL и выводит возможности (capabilities), версию ABI
                 и параметры сети (IP, MAC, шлюз и т.д.).
  PING.EXE     - PING <хост>. Проверяет доступность узла.
  HTTPGET.EXE  - HTTPGET <хост> [порт]. Забирает страницу по HTTP/1.0
                 (порт по умолчанию 80, например HTTPGET info.cern.ch).
  UDPECHO.EXE  - UDPECHO <хост> <порт> [текст]. Отправляет одну UDP-
                 датаграмму и печатает ответ.
  UNETESP.DLL  - бекенд WiFi (ESP8266 / ESP-AT).
  UNETRTL.DLL  - бекенд ISA-карты RTL8019A.

Перед запуском примеров настройте сеть инструментом своего бекенда - он
сам опубликует переменную среды NET, вручную её задавать не нужно:

  WiFi:  запустите NETUP.EXE            (публикует NET=WIFI)
  RTL:   запустите NETCFG -i, затем IFUP.EXE   (публикуют NET=RTL)

Где взять инструменты настройки:
  NETUP        - в дистрибутиве WiFi-кита (sprinter_net)
  NETCFG, IFUP - в дистрибутиве RTL-кита (sprinter-rtl8019a)

Пример (WiFi):
  NETUP
  NETINFO
  PING 8.8.8.8
  HTTPGET info.cern.ch

Подробности и исходный код: https://github.com/witchcraft2001/sprinter_unet_libs_asm
