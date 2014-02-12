#!/bin/bash
#
# Passed arguments:
#	$1 - pkgname to build [REQUIRED]
#	$2 - cross target [OPTIONAL]

if [ $# -lt 1 -o $# -gt 2 ]; then
	echo "$(basename $0): invalid number of arguments: pkgname [cross-target]"
	exit 1
fi

PKGNAME="$1"
XBPS_CROSS_BUILD="$2"

. $XBPS_SHUTILSDIR/common.sh

for f in $XBPS_COMMONDIR/helpers/*.sh; do
	source_file $f
done

setup_pkg "$PKGNAME" $XBPS_CROSS_BUILD

for f in $XBPS_COMMONDIR/environment/build/*.sh; do
	set -a; source_file $f; set +a
done

if [ -z $pkgname -o -z $version ]; then
	msg_error "$1: pkgname/version not set in pkg template!\n"
	exit 1
fi

XBPS_BUILD_DONE="$wrksrc/.xbps_${XBPS_CROSS_BUILD}_build_done"
XBPS_PRE_BUILD_DONE="$wrksrc/.xbps_${XBPS_CROSS_BUILD}_pre_build_done"
XBPS_POST_BUILD_DONE="$wrksrc/.xbps_${XBPS_CROSS_BUILD}_post_build_done"

if [ -f "$XBPS_BUILD_DONE" ]; then
	exit 0
fi

cd $wrksrc || msg_error "$pkgver: cannot access wrksrc directory [$wrksrc]\n"
if [ -n "$build_wrksrc" ]; then
	cd $build_wrksrc || \
		msg_error "$pkgver: cannot access build_wrksrc directory [$build_wrksrc]\n"
fi

run_pkg_hooks pre-build

# Run pre_build()
if [ ! -f $XBPS_PRE_BUILD_DONE ]; then
	cd $wrksrc
	[ -n "$build_wrksrc" ] && cd $build_wrksrc
	if declare -f pre_build >/dev/null; then
		run_func pre_build
		touch -f $XBPS_PRE_BUILD_DONE
	fi
fi

# Run do_build()
cd $wrksrc
[ -n "$build_wrksrc" ] && cd $build_wrksrc
if declare -f do_build >/dev/null; then
	run_func do_build
else
	if [ -n "$build_style" ]; then
		if [ ! -r $XBPS_BUILDSTYLEDIR/${build_style}.sh ]; then
			msg_error "$pkgver: cannot find build helper $XBPS_BUILDSTYLEDIR/${build_style}.sh!\n"
		fi
		. $XBPS_BUILDSTYLEDIR/${build_style}.sh
		if declare -f do_build >/dev/null; then
			run_func do_build
		fi
	fi
fi

touch -f $XBPS_BUILD_DONE

# Run post_build()
if [ ! -f $XBPS_POST_BUILD_DONE ]; then
	cd $wrksrc
	[ -n "$build_wrksrc" ] && cd $build_wrksrc
	if declare -f post_build >/dev/null; then
		run_func post_build
		touch -f $XBPS_POST_BUILD_DONE
	fi
fi

run_pkg_hooks post-build

exit 0
