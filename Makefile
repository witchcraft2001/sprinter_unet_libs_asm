.PHONY: all build netinfo ping httpget udpecho check image update-dlls package clean

all: build

build:
	tools/build.sh all

netinfo:
	tools/build.sh netinfo

ping:
	tools/build.sh ping

httpget:
	tools/build.sh httpget

udpecho:
	tools/build.sh udpecho

check:
	tools/check_dlls.py

image: build
	tools/image.sh

update-dlls:
	tools/update_dlls.sh

package: build
	tools/package.sh

clean:
	rm -rf build distr
