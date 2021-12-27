# backup

This git repository contains two simple scripts for making backup
copies of files.

## backup.sh

The first, `backup.sh` performs file-granularity differential backups
onto an external, removable disk.  The main goal, aside from basic
functionality, is to have a relatively simple script, so that the
backup process is understandable and completely in the user's control.
If anything goes wrong, the user should be able to easily fix things.

The script takes the mountpoint of the external disk as first
argument, and source subtree(s) to be backed up as additional
arguements; if no source directories are named, it defaults to backing
up the user's home directory.  The backups are nested in a directory
that mirrors the full-path name of the source directory, with user
name and hostname included to make sharing of a single external drive
among different users and computers easy.  For each source directory,
the script creates numbered subdirectories for the source directory
being backed up.  The numbering scheme is that the '000' is the
newest, up to a maximum specified by a MAXBACKUP environment variable.
No automatic disk capacity based estimation is done.

The defaults for the mountpoint is for an external drive named
`backup` and home directory locations is for Ubuntu.  So running

```
$ git/backup/backup.sh
```

will back up `/home/bsy` (for me) to
`/media/bsy/backup/bsy/machine/backup/home/bsy/backup.000` for login
`bsy` on machine `machine`.

The backups are incremental in the sense that each version of a file
should occur on the backup drive once: when we make a backup, we
create hard links between the numbered version directories and replace
a file if and only if it has changed.

The script just uses `cp` and `rsync`, which are widely used and quite
dependable.

There is currently no disk management, so the script just backs up
onto the disk without any notion of daily, weekly, monthly, etc
backups and how the treatments might differ.  It would be simple to
just use different paths for different frequencies, except that the
benefits of the incremental backup is reduced: when the user does a
monthly backup, the hardlinks should be to the most recently backup
(daily or weekly, depending on the user's backup frequency), rather
than the last month's version.

## cabackup.sh

The `cabackup.sh` script is more experimental and depends on `casync`
which is not as widely available / installed by default.

This script uses `casync` to do finer grained deduplication.  The
`casync` program chops files into blocks (using a windowed hash
function to identify block boundaries) and then computes a
cryptographic hash of the block contents, replacing each file with a
list of hashes to name the contents.  The data in the block is saved
to a separate storage area, and since there should be no hash
collisions with a cryptographic hash function, is content-addressible
storage.  This means that two files that are different but mostly
identical should have many identical blocks, so the actual storage
used is reduced.

Note that `cabackup.sh` is slower than `backup.sh`, because of the
hashing overhead, even though there should be far less I/O bandwidth
needed.

I have had problems with `casync` failing when writing to some older
external drives -- I don't think it ran out of inodes or something
simple like that -- so I tend to use `backup.sh` for "major" backups
and `cabackup.sh` for more frequent "minor" backups.

Anyway, suggestions and PRs welcome.  Enjoy!
