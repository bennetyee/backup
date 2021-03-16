#!/bin/bash

# A script to do differential backups.  Backups performed at different
# times are kept in separate directories, but if a file has not
# changed then these directories will share the file via a hard link.
# This saves disk space.  The assumption is that the backup is done
# via a removable storage device, e.g., USB external storage.  There
# is currently no provision to use ssh/rsync to back up to a remote
# machine, though this may be added in the future.  After backing up
# one's home directory, the assumption is that the external storage
# device will be unmounted, removed, and stored somewhere safe,
# possibly away from the computer to avoid common mode failures such
# as physical damage scenarios.

u=${USER:-$(whoami)}
media=${1:-"/media/$u/backup"}
shift

dest=${media}/${u}/$(hostname)/backup
digits=3
max_backup=$(printf %0${digits}d ${MAXBACKUP:-64})

VERBOSE=${VERBOSE:-0}

EXCLUDES=${EXCLUDES:-"--exclude=/.Private \
       --exclude=/.aptitude \
       --exclude=/.cache \
       --exclude=/.gvfs \
       --exclude=/.gxine/socket \
       --exclude=/.rnd \
       --exclude=/mail/**/.*"}

# Use a fixed number of digits as the backup directory name, so that
# when we do ls etc the directories will lexicographically sort in a
# nice order.

# BUG: if MAXBACKUP is more than 3 digits, then we overflow the printf
# format, and some names will use 3 digits and others will be 4.

# rest of argument list is a list of source directories to back up.
if [ "$*" = '' ]
then
	set /home/$u /mm/$u
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

function shift_backup() {
	# shift_backup /foo/bar 001  -- renames /foo/bar.001 to /foo/bar.002
	# Handles number of digits used in the numbering.
	if [ -d "$1.$2" ]
	then
		[ $VERBOSE -ge 2 ] && echo "shifting $1.$2"
		next=$(printf %0${digits}d $((10#$2 + 1)))
		# $(( )) use of # not well documented: it says that
		# the $2 should be evaluated as base 10, even if
		# e.g. it may start with a 0 and otherwise would have
		# been interpreted as octal.
		mv -f "$1.$2" "$1.$next"
	fi
}

function backup() {
	# backup src_dir target_dir [ rsync-options ]
	src_dir="$1"
	target_dir="$2"
	if [ ! -d "$src_dir" ]
	then
		return 1
	fi
	[ -d "$target_dir" ] || mkdir -p "$target_dir"
	shift; shift  # consume dirs, so "$@" are the rsync options

	# If we run out of disk space or inodes, the cp -al or rsync
	# below will fail.  We leave behind the new_dir, but existing
	# data should be fine.  Manual cleanup is needed for the new
	# directory, changing the max number of backup to save, etc.
	new_dir="$target_dir/backup.new.$$"
	most_recent="$target_dir/backup.$(printf %0${digits}d 0)"
	if [ -d "$most_recent" ]
	then
		cp -al "$most_recent" "$new_dir"
	else
		[ $VERBOSE -ge 1 ] && printf 'Not previously backed up'
	fi
	rsync -a --delete "$@" "$src_dir/" "$new_dir/"

	# Create a timestamp file, so when the backup is done is obvious.
	touch "$new_dir/BACKUP.$(date -Isec)"

	if [ -d "$target_dir/backup.$max_backup" ]
	then
		[ $VERBOSE -ge 1 ] && printf 'at max backup limit %d; removing excess' "$max_backup"
		trash="$target_dir/trash.$$"
		mv -f "$target_dir/backup.$max_backup" "$trash";
		# trash removing in the background
		(chmod -R u+w "$trash" && rm -fr "$trash")&
	fi
	for i in $(seq $((10#$max_backup - 1)) -1 0)
	do
		shift_backup "$target_dir/backup" "$(printf %0${digits}d $i)"
	done

	if [ -d "$most_recent" ]
	then
		echo "most-recent backup $most_recent still exists after shifting?" >&2
		exit 1
	fi

	mv "$new_dir" "$most_recent"
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
	if ! backup "$d" "$dest$d" $EXCLUDES
	then
		printf 'backup of %s failed\n' "$d" >&2
		status=1
	fi
done

[ $VERBOSE -ge 1 ] && printf 'Done.\n'

# Suggest how to unmount the external drive.  Not done automatically,
# in case the user wants to look around, or if the drive is a "hot"
# backup also used for other things.

info=$(mount | grep "$media")
case "$info" in
/dev/mapper*)
	# echo "LUKS encrypted filesystem"
	luks=$(lsblk | grep -B2 -A0 -F "$media")
	# echo "$luks"
	bdev=/dev/$(echo "$luks" | head -1 | sed 's/[ \t].*//')
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

printf 'You should run something like:\n'
printf ' pumount %s\n' "$media"
printf ' udisksctl power-off -b %s\n' "${bdev:-'block-device'}" # /dev/sdc
printf 'before unplugging the external drive.\n'
exit $status
