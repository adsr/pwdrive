DESTDIR?=/usr/local/bin

all:

install: pwdrive.sh
	install -v -m 755 pwdrive.sh $(DESTDIR)/pwdrive

.PHONY: all install
