# Many Machines

Many Machines is a Linux VPS admin automation tool
and application deployment tool written in Bash.

MM keeps a database of your machines and deployments and provides you with
a command-line UI from which to perform and automate all your sysadmin tasks
like SSH key management, scheduled backups, automated deployments,
SSL certificate issuing, real-time app monitoring, etc.

Accompanying that is a web server with a web UI for real-time monitoring
and performing admin tasks, which also exposes a HTTP API for automation.
The server is written in Lua using the [Allegory SDK]. The web UI is written
in Lua and JavaScript using the Allegory SDK and [Canvas-UI].

[Allegory SDK] : https://github.com/allegory-software/allegory-sdk
[Canvas-UI]    : https://github.com/allegory-software/canvas-ui

One notable feature of MM that's less common in tools of this type is
the presence of Windows-native sysadmin tools like sshfs, putty, etc.

# Design

* File-based config database
  * no need to develop a CRUD UI, and then have people learn how to use it;
  just use mc for CRUD which people already know, can do bulk ops, and you can
  inspect and repair the data if something goes wrong.
  * single-value-per-file for fast and robust CRUD scripting without sed.
  * simple backup and restore with tar, gz, gpg and rsync or even git.
  * shared config groups with include dirs (think multiple inheritance with overrides).
  * linked entities with symlinks.
* Written in Bash
  * no dependencies, so less bit rot.
  * expandable, meaning you can add:
    * commands and command aliases
    * function libraries with new functions and overrides
    * custom install functions for installing packages
    * custom listing commands
    * field getters for custom listing commands
* Universal support for bulk ops
  * All ops apply to one/many/all machines and/or deployments.
  * Machines and deployments are identified by name only.
  * Machines can be identified indirectly by deployment name.
* Sweet, sweet developer experience
  * sub-second, no extra-steps dev-run cycle: all code is uploaded
  on each invocation, there's no extra "syncing" or "cache clearing" step,
  and you can't run stale code.
  * command tracing, error handling and arg checking vocabulary (see die.sh).

# Functionality

* SSH
  * key management
    * host fingerprint list & update
    * private key gen
    * pubkey list & update
  * operation
    * remote shell
    * remote commands
    * remote scripts
    * tunnels
    * ssh-fs
* Git
  * SSH key management
    * multiple git hosting providers
    * private key update
* MySQL
  * password management
    * password gen
    * password list & update
  * operation
    * remote SQL
    * listing databases, tables, table structure

# Status

In active development, see TODO.txt.
