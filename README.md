# pwdrive

pwdrive is a GnuPG and Google Drive-based password vault written in Bash.
Passwords are stored as base64-encoded GnuPG-encrypted files on Google Drive.

### Requirements

In addition to Bash, the following programs need to be in `PATH`:

    gpg curl grep mktemp mkdir cat base64

You also need a working GPG setup:

https://www.gnupg.org/gph/en/manual/c14.html

### Installing

To install to `/usr/local/bin`:

    # make install

To install to a custom directory, supply `DESTDIR`, e.g.:

    # DESTDIR=/usr/bin make install

### Usage

    Usage:
        pwdrive <command> [argv]

    Commands:
        ls                    List all entries
        ls <str>              List all entries containing str
        set <entry> <pass>    Set password for entry
        set <entry> -         Set password for entry from stdin
        get <entry>           Get password for entry
        rm <entry>            Remove entry
        token                 Print an access token
        help                  Show pwdrive usage

    Environment:
        PWDRIVE_ACCESS_TOKEN  Use this access token instead of fetching one
        PWDRIVE_HOME          Home dir of pwdrive (~/.pwdrive)
        PWDRIVE_GPG_ARGS      Extra args for get/set (--no-options --default-recipient-self --quiet)

### Tip

In order to minimize dependencies, `grep -P` is used to extract JSON fields
from the Google Drive API. Naturally this is not ideal. If you stick to
ascii-only for `entry` params, things should work.
