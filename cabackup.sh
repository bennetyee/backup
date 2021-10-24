#!/bin/bash

# Use casync to do backups.
#
# We use external, removable disk drives.  We rotate them, so a single
# disk failure would not be terrible.  Unlike tapes, we do not try to
# track the number of times a disk has been written to, use some less
# frequently than others, etc.  The assumption is that when a disk
# fills up, we just delete old backups, which in the case of a
# content-addressable storage will be via garbage collection (casync
# gc --store castr caidx... where the caidx are storage-roots that we
# want to retain.
#
# Because we may back up multiple computers on a single drive, we use
# a common castr directory to maximize the content-addressable storage
# data deduplication.  The indices will just be hostname/date.caidx
# files.
#
# Backups can be examined (read) by fuser mounting the backup, via
#  casync mount --store castr host/date.caidx /mnt
# and to unmount, use
#  fusermount -u /mnt
#
# WARNING
#
# One problem with using casync is that if casync ever becomes
# unsupported and suffers bit rot, backups become inaccessible.  The
# cp -al / rsync approach leaves us with backup data as a normal
# directory tree, with less data deduplication, but it should be
# pretty much impossible to not be accessible unless the filesystem
# type becomes unsupported.  We can include a git clone of casync, but
# building it requires meson and ninja and it's a can of worms for
# ensuring long-duration availability.
#
# One possibility is to use casync (this script, cabackup.sh) for more
# frequent backups and cp / rsync (backup.sh) for less frequent
# backups, so that the simple directory tree form is available.

u=${USER:-$(whoami)}
media=${1:-"/media/$u/backup"}
shift

set -e

OS=$(uname -s)

dest=${media}/${u}/$(hostname)/$(date -Isec).caidx
castore=${media}/${u}/default.castr

VERBOSE=${VERBOSE:-0}

# Excludes go into .caexclude file (per directory), e.g.,
#/.Private
#/.aptitude
#/.cache
#/.gvfs
#/.gxine/socket
#/.rnd
##
## /mail/**/.*
##
## caexclude does not implement rsync style double asterisk globbing
##
## This can be handled by
##  for d in ~/mail/*; do if [ -d $d ]; then echo '.*' > $d/.caexclude; fi; done
## but it has to be done for every new mail folder.  Yuck.

# Unlike backup.sh, we do not (yet) provide a way to set a maximum
# number of backup snapshots.

# The rest of argument list is a list of source directories to back up.
# Default is the home directory
if [ "$*" = '' ]
then
	if [ $OS == Linux ]
	then
		set /home/$u
	#elif [ $OS == Darwin ]
	#then
	#     set /Users/$u
	else
		printf 'casync is Linux-only\n' >&2
		exit 1
	fi
fi

for d
do
	case "$d" in
	/*)
		;;
	*)
		printf 'Fatal: source directory for backup %s is not absolute' "$d" >&2
		exit 1
		;;
	esac
done


function backup() {
	# backup castore caidx dir
	castore="$1"
	caidx="$2"
	src_dir="$3"
	if [ ! -d "$src_dir" ]
	then
		printf 'cabackup: backup source %s is not a directory\n' "$src_dir" >&2
		return 1
	fi
	d=$(dirname "$castore")
	if ! [ -d "${d}" ]
	then
		if [ $VERBOSE -gt 0 ]
		then
			printf 'cabackup: creating content addressable store directory %s\n' "${d}" >&2
		fi
		mkdir -p "${d}"
	fi
	d=$(dirname "$caidx")
	if ! [ -d ${d} ]
	then
		if [ $VERBOSE -gt 0 ]
		then
			printf 'cabackup: creating content addressable index directory %s\n' "${d}" >&2
		fi
		mkdir -p "${d}"
	fi
	verbose=""
	if [ $VERBOSE -gt 2 ]
	then
		verbose="--verbose"
	fi
	casync make $verbose --store="$castore" "$caidx" "$src_dir"
	sync
}

# In case the system is not configured to automatically mount the
# removable device's filesystem.
if [ ! -d "$media" ]
then
	echo "backup destination $media not mounted?" >&2
	exit 1
fi

status=0

for d
do
	if ! backup "$castore" "$dest" "$d"
	then
		printf 'backup of %s failed\n' "$d" >&2
		status=1
	fi
done

[ $VERBOSE -ge 1 ] && printf 'Done.\n'

# Maybe this should only be done w/ verbose set?
if [ $OS == Linux ]
then
	# Suggest how to unmount the external drive.  Not done
	# automatically, in case the user wants to look around, or if
	# the drive is a "hot" backup also used for other things.

	printf 'You should run something like:\n'
	printf ' pumount %s\n' "$media"

	info=$(mount | grep "$media")
	case "$info" in
	/dev/mapper*)
		# echo "LUKS encrypted filesystem"
		luks=$(lsblk | grep -B2 -A0 -F "$media")
		# echo "$luks"
		bdev=/dev/$(echo "$luks" | head -1 | sed 's/[ \t].*//')
		part=/dev/$(echo "$luks" | sed -n '1d;2d;s/^..//;s/ .*//;p')
		printf ' udisksctl lock -b %s\n' "$part"
		;;
	/dev/sd*)
		# echo "Non-encrypted filesystem"
		# echo "$info"
		bdev=$(echo "$info" | sed 's/[0-9]*[ \t].*//')
		;;
	*)
		printf 'No guesses on how backup media is mounted\n'
		printf ' device: %s\n' "$info"
		;;
	esac

	printf ' udisksctl power-off -b %s\n' "${bdev:-'block-device'}" # /dev/sdc
	printf 'before unplugging the external drive.\n'
elif $OS == Darwin
then
	printf 'You should safely unmount the external drive using Disk Utility or diskutil.\n'
else
	printf 'Unknown OS.  You should safely unmount the external drive before unplugging it.\n'
fi

exit $status
