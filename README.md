# :sunglasses: Many Machines

Many Machines is a Linux sysadmin tool and application deployment tool
written in Bash.

MM keeps a database of your machines and deployments and provides you with
a command-line UI from which to perform and automate all your sysadmin tasks
like SSH key management, scheduled backups, automated deployments,
SSL certificate issuing, real-time app monitoring, etc.

MM is the complete opposite of tools like Ansible, Terraform, Puppet, etc.
in that it is a fully programmable, bottom-up, DIY toolbox rather than a
gargantuan black box with 500,000 LOC all trying to convince you that you
don't need to learn programming to be a sysadmin.

# Functionality

* Configuration Management
  * SSH key management
  * user management
  * software installation and configuration
  * git key management
  * mysql user management
  * app user management
  * app deployment
  * SSL certificate management
* Reporting
  * users and password lock status
  * installed software versions
  * app version and version check
  * service running status, app running status
  * disk, RAM, CPU
  * open ports
  * geographical location
  * mysql databases, tables, table structure
  * app users, sessions, tenants
* Ops
  * remote shells, commands, tunnels
  * remote scripts with vars
  * service and app control
  * rsync between machines
  * remote mysql queries
  * mysql database management
  * mysql database backup and restore
  * files backup and restore
* Benchmarking
  * CPU speed test, disk speed test, network speed test

# Design

* File-based single-value-per-file config database
  * no need to develop a CRUD UI, and then have people learn how to use it;
  use mc for CRUD which you already know, can do bulk ops on data,
  and you can inspect and repair the data if something goes wrong.
  * no syntax to learn, no parser to develop, no format to specify.
  * fast and robust CRUD scripting without sed.
  * simple backup and restore with tar, gz, gpg, rsync and git.
  * leverage symlinks for referencing shared values and entities.
  * include dirs (multiple inheritance with overrides in OOP slang),
  a powerful feature that allows defining groups of config values
  and including them into machine and deployment configurations.
* Distributed (like git)
  * MM is an offline tool with a local database. If you have multiple laptops
  you need to sync the db between them manually or push/pull it in the cloud.
* Written in Bash
  * no dependencies, less bit rot.
  * expandable, meaning you can add:
    * commands and command aliases
    * function libraries with new functions and overrides
    * custom install functions for installing packages
    * custom listing commands
    * field getters for custom listing commands
* Sweet, sweet sysadmin experience
  * Bulk ops all the way:
    * all ops apply to one/many/all machines and/or deployments.
  * Easy on your eyes:
    * data gathered from machines is always shown in tabular form,
    not just blurted out as it comes, and you can make custom
    listings with the columns that are relevant to you.
  * Easy on your memory:
    * machines and deployments are identified by name only.
    * machines can be identified indirectly by deployment name.
* Sweet, sweet developer experience
  * sub-second, no extra-steps dev-run cycle: all the code necessary to run
  a command remotely is uploaded on each invocation, there's no extra "syncing"
  or "cache clearing" step, and you can't run stale code on remote machines.
  * command tracing, error handling and arg checking vocabulary (see die.sh).
  * very small and hackable codebase with a meta-programming approach
  that Bash is particularly suited for (you won't believe how little code
  this entire project has for how much it does).

# Getting started

## Installation

	Fork the project.
	Login as root.
	~# git clone git@github.com:YOUR-ACCOUNT/many-machines mm
	~# mm/install

This puts two commands in PATH, `mm` and `mmd`, and also `mmlib` which is
not a command but the MM library to be included in scripts with `. mmlib`.

## Machines

Machines and deployments are what MM is all about, so you need to define
some in order to make MM useful. The MM database is the `var` dir inside mm.
Machines are `var/machines/MACHINE` dirs which must contain at least
the `public_ip` file so that you can run commands on it. So go ahead and
define one machine with its IP address. It can even be the machine that
you are currently on.

Then run `mm pubkey` to see your SSH public key and add it to the machine's
`/root/.ssh/authorized_keys` file so that you can ssh into the machine freely.
You also need to update the machine's figerprint with `mm MACHINE hostkey-update`
before you can ssh into the machine with mm.

Type `mm m` to see your machines. Type `mm free` to check on the machine's
resources. Try some other reporting commands. Type `mm MACHINE` to ssh into it
as root or `mm MACHINE ssh COMMAND ARGS...` to run a command on it.

## Debugging

If anything goes wrong or you want to know what commands do underneath,
type `DEBUG=1 mm ...`. There's an entire vocabulary for printing, tracing,
error reporting and arg checking in `lib/die.sh` that all the scripts use,
so getting familiar with that now will make it easier to read the MM code
in the future.

## SSH Host Fingerprint Management

SSH uses host fingerprints to mitigate MITM. MM keeps these hashes separate
from `~/.ssh/known_hosts` so you need to do `mm MACHINE hostkey-update` before
you can ssh into a machine through MM, since you won't get prompted for that.
The reason for keeping these inside mm's database is so that you don't have
to update them on any new device you happen to work from.

## SSH Key Management

MM assumes key-based auth for SSH. `mm pubkeys` lists the current SSH public
keys found on each machine/user. The `device` column allows you to associate
a pubkey with the device that holds the private key of that pubkey so that
you can keep track of which device has access to which machine/user. To register
the machine you're on right now as a device type `mm set-device DEVICE`.
Type `mm pubkeys` again: you should now see your device showing next to the pubkey.
If your private key gets compromised, refresh it with `mm ssh-keygen` and then
add it to all machines with `mm pubkey-add`. Then remove the old one with
`mm pubkey-remove PUBKEY`.

## Modules

Next you might want to define the modules that should be installed on the machine.
Modules are those with an install function. `grep install_ lib/*` will give you
a list of available modules with a custom installer, otherwise OS packages
with a matching name are installed by default.
Add a `modules` file inside your machine dir with a list of module names separated
by space and/or newlines (eg. `timezone hostname secure_proc git curl`).

Modules can be installed manually with `mm install MODULE`. Modules declared
in the `modules` file can be installed with `mm prepare`, which is what you
should run on a new machine right after you get SSH access to it.

## `mm` vs `mmd`

`mm` is the frontend UI for the commands in `/cmd`. `mm` takes a list of
machines and/or deployments and passes them to the command as the `MACHINES`
and `DEPLOYS` vars.

Some commands are ambiguous in that they work on either a list of deployments
or a list of machines. To disambiguate, use `mmd` to act on deployments
because `mm` always acts on machines, even when deployment names are given.

Most commands, when no machines/deploys (let's call them MDs from now on)
are given act on all MDs in the database. Some more dangerous commands will
refuse to act on all of them and ask you to be specific.

## The Help System

The second line of a cmd script is important: it's a comment that describes
the command's section, its args if any and a description. This line is parsed
and used when typing `mm`, `mm help`, `mm help SECTION` and `mm COMMAND ?`.

## The MM Database

The mm database is the `var` dir inside MM. Since this is a local offline
database and not a centralized server, if you use multiple computers to manage
your machines _from_, then you need to sync the database between them, which
means they need to have a public IP and be both online at the same time to do
the transfer. This is unlikely, so a better way is to sync the database using
the machines that you administer as "cloud storage", since those are always
online anyway. This is done with `mm var-download` and `mm var-upload`. For it
to work you need to create a file inside mm called `var-secret` with a random
string in it of 30 chars+ so that the database is kept encrypted in the cloud.
You can also use a github repo that you have read/write access to as storage.
Put the repo URL in `var/var_repo` and use `mm var-push` and `mm var-pull`
to sync. The data on the repo will still be encrypted so you don't have to
trust the cloud provider.

Another way to sync the database is via git. Still using your always-on machines
but non-encrypted this time, if you can trust it. The advantage here is that
multiple sysadmins can work together on the same infrastructure and sync their
changes with branches and merges. For this MM doesn't provide any utilities,
just do `git init` inside the `var` dir, `git remote add ssh://IP/root/mm/var`
and go from there. This will work since you can already ssh to your machines.

## The Vars System

Configuration data for machines and deployments is kept in one-value-per-file in
`var/machines/MACHINE/VAR_NAME` and `var/deploys/DEPLOY/VAR_NAME` respectively.
Some values will be common to multiple MDs, in which case you can put them
in other dirs of your chosing in `var` (or directly in `var`) and just symlink
them into the right places. This can become tedious when entire groups of values
are common, like eg. when specifying the details of a a SMTP server which
includes host, user, password, etc. For that you can use an include dir: make
a dir in `var` eg. `var/.my-smtp-server` and symlink it into the MD dir that
needs those values. Notice the dir starts with a dot, which makes its contents
be included in the MD just like if you were making individual symlinks from it.

You can have multiple include dirs symlinked into an MD dir. They are processed
in alphabetical order, so you can override values from the ones that come before
in the ones that come later.

In practice you will most likely have a `.0-defaults` include dir for machines
and one for deployments that you wil symlink into every MD, and other include
dirs on top of that based on your situation.

# Status

In active development, see TODO.txt.
