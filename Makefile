DESTDIR?=/usr/local/bin
BASH_COMP_D?=/etc/bash_completion.d

all:

install: pwdrive.sh completion.bash
	install -v -m 755 pwdrive.sh $(DESTDIR)/pwdrive
	[ ! -d $(BASH_COMP_D) ] || install -v -m 644 completion.bash $(BASH_COMP_D)/pwdrive

.PHONY: all install
