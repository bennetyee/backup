# backup

This git repository contains a simple script for making backup copies
of files to do differential backups onto an external, removable disk.
The main goal, aside from basic functionality, is to have a relatively
simple script, so that the backup process is understandable and
completely in the user's control.  If anything goes wrong, the user
should be able to fix things.

The script takes the mountpoint of the external disk as first
argument, and make backup copies of the source directory of the backup
(additional arguements, default home directory) there.  The backups
are nested in a directory that mirrors the full-path name of the
source directory, with user name and hostname included to make sharing
of a single external drive among different users and computers easy.
For each source directory, the script creates numbered subdirectories
for the source directory being backed up.  The numbering scheme is
that the '000' is the newest, up to a maximum specified by a MAXBACKUP
environment variable.  No automatic disk capacity based estimation is
done.

The backups are incremental in the sense that each version of a file
should occur on the backup drive once: when we make a backup, we
create hard links between the numbered version directories and replace
a file if and only if it has changed.

There is currently no disk management, so the script just backs up
onto the disk without any notion of daily, weekly, monthly, etc
backups and how the treatments might differ.  It would be simple to
just use different paths for different frequencies, except that the
benefits of the incremental backup is reduced: when the user does a
monthly backup, the hardlinks should be to the most recently backup
(daily or weekly, depending on the user's backup frequency), rather
than the last month's version.

Anyway, suggestions and PRs welcome.  Enjoy!
