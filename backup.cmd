#!/bin/bash

u=${USER:-$(whoami)}
media=${1:-"/media/$u/backup"}
dest=${media}/${u}/$(hostname)/backup
max_backup=64
VERBOSE=${VERBOSE:-0}

function shift_backup() {
	# shift_backup /foo/bar 001  -- renames /foo/bar.001 to /foo/bar.002
	if [ -d "$1.$2" ]
	then
		[ $VERBOSE -ge 2 ] && echo "shifting $1.$2"
		next=$(printf %03d $((10#$2 + 1)))
		mv -f "$1.$2" "$1.$next"
	fi
}

function backup() {
	# backup src_dir target_dir [ rsync-options ]
	src_dir="$1"
	target_dir="$2"
	if [ ! -d "$src_dir" ]
	then
		echo "source directory $src_dir does not exist; skipping..."
		return 1
	fi
	[ -d "$target_dir" ] || mkdir -p "$target_dir"
	shift; shift
	if [ -d "$target_dir/backup.$max_backup" ]
	then
		[ $VERBOSE -ge 1 ] && echo "at max backup limit $max_backup; removing excess"
		( mv -f "$target_dir/backup.$max_backup" "$target_dir/trash";
		  chmod -R u+w "$target_dir/trash";
		  rm -fr "$target_dir/trash" & )
	fi
	i="$max_backup"
	while (($i >= 0))
	do
		i=$(($i - 1))
		shift_backup "$target_dir/backup" "$(printf %03d $i)"
	done
	if [ -d "$target_dir/backup.001" ]
	then
		cp -al "$target_dir/backup.001" "$target_dir/backup.000"
	else
		[ $VERBOSE -ge 1 ] && echo 'Not previously backed up'
	fi
	rsync -a --delete "$@" "$src_dir/" "$target_dir/backup.000/"
	touch "$target_dir/backup.000/BACKUP.$(date -Isec)"
}

if [ ! -d "$media" ]
then
	echo "backup destination $media not mounted?" >&2
	exit 1
fi

backup "/home/$u" "$dest/home/$u" \
       --exclude=/.Private \
       --exclude=/.aptitude \
       --exclude=/.cache \
       --exclude=/.gvfs \
       --exclude=/.gxine/socket \
       --exclude=/.rnd \
       --exclude=/mail/**/.*
backup "/mm/$u" "$dest/mm/$u"
sync
echo 'Done.'

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
	echo "No guesses on how it is mounted"
	echo "$info"
	;;
esac

echo 'You should run something like:'
echo " pumount $media"
echo " udisksctl power-off -b ${bdev:-'block-device'}" # /dev/sdc
echo 'before unplugging the external drive.'
