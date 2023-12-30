# pwdrive

pwdrive is a GnuPG and Google Drive-based password vault written in Bash.
Passwords are stored as GnuPG-encrypted files on Google Drive.

### Synopsis

    $ pwdrive set aol       # Store encrypted secret
    Enter secret:...
    Enter secret again:...
    $ pwdrive ls            # List entries
    aol
    $ pwdrive copy aol      # Fetch and decrypt secret onto clipboard
    ...

### Requirements

You need a working GPG setup: https://www.gnupg.org/gph/en/manual/c14.html

In addition to Bash, the following programs need to be in `PATH`:

    gpg curl grep mktemp mkdir cat base64 sort ( nc | ncat )

netcat can be either the BSD or traditional version.

The `copy` command requires `xclip` by default, but can be customized via the
`PWDRIVE_COPY_CMD` environment variable.

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
        ls <str>              List all entries prefixed by str
        set <entry>           Set secret for entry via prompt
        set <entry> -         Set secret for entry from stdin
        set <entry> <pass>    Set secret for entry (not preferred)
        get <entry>           Print secret for entry on stdout
        copy <entry>          Copy secret to clipboard (via $PWDRIVE_COPY_CMD)
        lget <str>            Get entry matching str, or ls if multiple
        lcopy <str>           Copy entry matching str, or ls if multiple
        grep <str>            Print entries matching str
        edit <entry>          Edit secret for entry (via $EDITOR)
        rm <entry>            Remove entry
        mv <from> <to>        Rename entry
        token                 Print an access token
        gen                   Generate some random passwords
        help                  Show pwdrive usage

    Environment:
        EDITOR                Editor to use with edit (vim)
        PWDRIVE_ACCESS_TOKEN  Use this access token instead of fetching one
        PWDRIVE_HOME          Home dir of pwdrive (~/.pwdrive)
        PWDRIVE_GPG_ARGS      Extra args for get/set (--no-options --default-recipient-self --quiet)
        PWDRIVE_COPY_CMD      Copy command (xclip -sel c)
        PWDRIVE_PORT          Port to listen on for OAuth callback (49871)
        PWDRIVE_NO_AUTO_LSW   If non-empty, disable auto update of ~/.pwdrive/entries

### Installing

To install to `/usr/local/bin`:

    # make install

To install to a custom directory, supply `DESTDIR`, e.g.:

    # DESTDIR=/usr/bin make install

### Android

pwdrive is confirmed to work on Android 11 with
[Termux](https://termux.com/) 0.117. Earlier versions may work as well.

### Tip

In order to minimize dependencies, `grep -P` is used to extract JSON fields
from the Google Drive API. Naturally this is not ideal. If you stick to
ascii-only for `entry` params, things should work.
