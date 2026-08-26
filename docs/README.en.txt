sprinter_unet_libs_asm - UNET examples

In this set:

  NETINFO.EXE  - detects the network backend from the NET variable, loads
                 its DLL and prints capabilities, ABI version and network
                 settings (IP, MAC, gateway and so on).
  PING.EXE     - PING <host>. Checks that a host is reachable.
  HTTPGET.EXE  - HTTPGET <host> [port]. Fetches a page over HTTP/1.0
                 (port defaults to 80, e.g. HTTPGET info.cern.ch).
  UDPECHO.EXE  - UDPECHO <host> <port> [text]. Sends one UDP datagram
                 and prints the reply.
  UNETESP.DLL  - WiFi backend (ESP8266 / ESP-AT).
  UNETRTL.DLL  - ISA RTL8019A card backend.

Before running the examples, bring the network up with your backend's own
tool - it publishes the NET environment variable itself, you never set it
by hand:

  WiFi:  run NETUP.EXE                   (publishes NET=WIFI)
  RTL:   run NETCFG -i, then IFUP.EXE    (publish NET=RTL)

Where to get the bring-up tools:
  NETUP        - in the WiFi kit distribution (sprinter_net)
  NETCFG, IFUP - in the RTL kit distribution (sprinter-rtl8019a)

Example (WiFi):
  NETUP
  NETINFO
  PING 8.8.8.8
  HTTPGET info.cern.ch

Details and source code: https://github.com/witchcraft2001/sprinter_unet_libs_asm
