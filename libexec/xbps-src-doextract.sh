#!/bin/bash
#
# Passed arguments:
#	$1 - pkgname [REQUIRED]
#	$2 - cross target [OPTIONAL]

if [ $# -lt 1 -o $# -gt 2 ]; then
	echo "$(basename $0): invalid number of arguments: pkgname [cross-target]"
	exit 1
fi

PKGNAME="$1"
XBPS_CROSS_BUILD="$2"

. $XBPS_SHUTILSDIR/common.sh

for f in $XBPS_COMMONDIR/helpers/*.sh; do
	source_file "$f"
done

setup_pkg "$PKGNAME" $XBPS_CROSS_BUILD

for f in $XBPS_COMMONDIR/environment/extract/*.sh; do
	source_file "$f"
done

XBPS_EXTRACT_DONE="$wrksrc/.xbps_extract_done"

if [ -f $XBPS_EXTRACT_DONE ]; then
	exit 0
fi

# Run pre-extract hooks
run_pkg_hooks pre-extract

# If template defines pre_extract(), use it.
if declare -f pre_extract >/dev/null; then
	run_func pre_extract
fi

# If template defines do_extract() use it rather than the hooks.
if declare -f do_extract >/dev/null; then
	[ ! -d "$wrksrc" ] && mkdir -p $wrksrc
	cd $wrksrc
	run_func do_extract
else
	# Run do-extract hooks
	run_pkg_hooks "do-extract"
fi

touch -f $XBPS_EXTRACT_DONE

# If template defines post_extract(), use it.
if declare -f post_extract >/dev/null; then
	run_func post_extract
fi

# Run post-extract hooks
run_pkg_hooks post-extract

exit 0
