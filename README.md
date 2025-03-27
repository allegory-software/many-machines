# :sunglasses: Many Machines

Many Machines is a Linux sysadmin tool and application deployment tool
written in Bash.

MM keeps a database of your machines and deployments and provides you with
a command-line UI from which to perform and automate all your sysadmin tasks
like SSH key management, scheduled backups, automated deployments,
SSL certificate issuing, real-time app monitoring, etc.

MM is the complete opposite of tools like Ansible, Terraform, Puppet, etc.
in that it is a fully programmable, bottom-up, DIY toolbox rather than
a gargantuan black box with 500,000 LOC all trying to convince you that you
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
  * remote shells and commands
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
  a power feature that I will explain later with examples.
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

## Install

	./install

This puts two commands in PATH, `mm` and `mmd`, and also `mmlib` which is
not a command but the MM library to be included in scripts with `. mmlib`.

## Machines

Machines and deployments are what MM is all about, so you need to define
some in order to make MM useful. The MM database is the `var` dir inside mm.
Machines are `var/machines/MACHINE` dirs which must contain at least
the `public_ip` file so that you can run commands on it. So go ahead and
define one machine with its IP address. It can even be the machine that
you are currently on.

Then run `mm pubkey` to see your SSH public key and paste it into the machine's
`/root/.ssh/authorized_keys` file so that you can ssh into the machine freely.

Type `mm m` to see your machines. Type `mm free` to check on the machine's
resources. Try some other reporting commands too.

## Debugging

If anything goes wrong or you want to know what commands do underneath,
type `DEBUG=1 mm ...`. There's an entire vocabulary for printing, tracing,
error reporting and arg checking in `lib/die.sh` that all the scripts use,
so getting familiar with that now will make it easier to read the MM code.

## Modules

Next you might want to define the modules that should be installed on the machine.
Modules are those with an install function. `grep install_ lib/*` will give you
a list of available modules with a custom installer, otherwise OS packages
with a matching name are installed by default.
Add a `modules` file inside your machine dir with a list of module names separated
by space and/or newlines. Example: `timezone hostname secure_proc git curl` etc.

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

## The help system

The second line of a cmd script is important: it's a comment that describes
the command's section, its args if any and a description. This line is parsed
and used when typing `mm`, `mm help`, `mm help SECTION` and `mm COMMAND ?`.

## The var system

The mm database is the `var` dir.


# Status

In active development, see TODO.txt.
