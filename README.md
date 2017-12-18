# pwdrive

pwdrive is a GnuPG and Google Drive-based password vault written in Bash.
Passwords are stored as GnuPG-encrypted files on Google Drive.

### Synopsis

    $ pwdrive set aol leetpw    # Store encrypted entry
    $ pwdrive ls                # List entries
    aol
    $ pwdrive get aol           # Fetch and decrypt entry
    leetpw

### Requirements

In addition to Bash, the following programs need to be in `PATH`:

    gpg curl grep mktemp mkdir cat base64

You also need a working GPG setup:

https://www.gnupg.org/gph/en/manual/c14.html

### How it works

For the encryption half, passwords are encrypted via GnuPG in 2048-bit RSA by
default. They are then base64-encoded and uploaded to Google Drive storage.
Access to Google Drive requires an OAuth token (granted by the end-user) which
is stored at `~/.pwdrive/refresh_token` by default.

For the decryption half, again an OAuth token is required to download the
encrypted password via the Google Drive API. The same private key used to
encrypt the password is needed at decrypt time. If the key is password-protected
(recommended) you need that as well. Note that there may be an agent running on
your system that remembers your GPG key passwords for some period of time.

All traffic to and from Google is transported over HTTPS.

So, as per usual, the main thing to keep safe is your GPG key.

The OAuth token in `~/.pwdrive` is regenerateable if it is lost or if it
expires. Simply delete it and pwdrive will prompt you to create another one. If
the token is stolen, an attacker will have access to encrypted password content
which is very difficult to brute force without the GPG key.

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

### Installing

To install to `/usr/local/bin`:

    # make install

To install to a custom directory, supply `DESTDIR`, e.g.:

    # DESTDIR=/usr/bin make install

### Tip

In order to minimize dependencies, `grep -P` is used to extract JSON fields
from the Google Drive API. Naturally this is not ideal. If you stick to
ascii-only for `entry` params, things should work.
