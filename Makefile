# Build this Debian package into dist/.
#   make                     build dist/<package>_<version>_all.deb
#   make VERSION=1.3.1       build another version
#   make clean               remove build output
PACKAGE    := $(shell sed -n 's/^Package: //p' debian/control)
VERSION    ?= 1.3.0
MAINTAINER ?= iiidefix <iiidefix@git.iiidefix.net>
DEB        := dist/$(PACKAGE)_$(VERSION)_all.deb
ROOT       := build/root

.PHONY: all clean
all: $(DEB)

$(DEB): Makefile $(shell find debian files -type f)
	rm -rf build
	mkdir -p $(ROOT)/DEBIAN dist
	cp -a files/. $(ROOT)/
	cp -a debian/. $(ROOT)/DEBIAN/
	find $(ROOT) -type d -exec chmod 0755 {} +
	find $(ROOT) -type f -exec chmod 0644 {} +
	chmod 0755 $(ROOT)/usr/sbin/* $(ROOT)/usr/lib/wwan-manager/*
	for s in preinst postinst prerm postrm; do [ ! -f $(ROOT)/DEBIAN/$$s ] || chmod 0755 $(ROOT)/DEBIAN/$$s; done
	for f in $(ROOT)/usr/sbin/* $(ROOT)/usr/share/bash-completion/completions/*; do bash -n $$f; done
	bash -n $(ROOT)/usr/share/wwan-manager/config.sh
	for f in $(ROOT)/usr/lib/wwan-manager/*; do python3 -m py_compile $$f; done
	rm -rf $(ROOT)/usr/lib/wwan-manager/__pycache__
	sed -i -e 's/@VERSION@/$(VERSION)/g' -e 's/@MAINTAINER@/$(MAINTAINER)/' $(ROOT)/DEBIAN/control
	echo "Installed-Size: $$(du -sk --exclude=DEBIAN $(ROOT) | cut -f1)" >> $(ROOT)/DEBIAN/control
	dpkg-deb --root-owner-group -Zxz --build $(ROOT) $@
	rm -rf build

clean:
	rm -rf build dist
