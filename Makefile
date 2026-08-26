.PHONY: all build netinfo ping httpget udpecho check image package clean

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
	LIBMAN_ROOT=extern/libman extern/core/tools/check_dlls.py --require-mkdll

image: build
	tools/image.sh

package: build
	tools/package.sh

clean:
	rm -rf build distr
