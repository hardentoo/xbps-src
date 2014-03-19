#!//bin/bash
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

for f in $XBPS_COMMONDIR/environment/install/*.sh; do
	source_file "$f"
done

XBPS_INSTALL_DONE="$wrksrc/.xbps_${pkgname}_${XBPS_CROSS_BUILD}_install_done"
XBPS_PRE_INSTALL_DONE="$wrksrc/.xbps_${pkgname}_${XBPS_CROSS_BUILD}_pre_install_done"
XBPS_POST_INSTALL_DONE="$wrksrc/.xbps_${pkgname}_${XBPS_CROSS_BUILD}_post_install_done"

if [ -f $XBPS_INSTALL_DONE ]; then
	exit 0
fi

mkdir -p $XBPS_DESTDIR/$XBPS_CROSS_TRIPLET/$pkgname-$version

cd $wrksrc || msg_error "$pkgver: cannot access to wrksrc [$wrksrc]\n"
if [ -n "$build_wrksrc" ]; then
	cd $build_wrksrc \
		|| msg_error "$pkgver: cannot access to build_wrksrc [$build_wrksrc]\n"
fi

run_pkg_hooks pre-install

# Run pre_install()
if [ ! -f $XBPS_PRE_INSTALL_DONE ]; then
	if declare -f pre_install >/dev/null; then
		run_func pre_install
		touch -f $XBPS_PRE_INSTALL_DONE
	fi
fi

# Run do_install()
if [ ! -f $XBPS_INSTALL_DONE ]; then
	cd $wrksrc
	[ -n "$build_wrksrc" ] && cd $build_wrksrc
	if declare -f do_install >/dev/null; then
		run_func do_install
	else
		if [ ! -r $XBPS_BUILDSTYLEDIR/${build_style}.sh ]; then
			msg_error "$pkgver: cannot find build helper $XBPS_BUILDSTYLEDIR/${build_style}.sh!\n"
		fi
		. $XBPS_BUILDSTYLEDIR/${build_style}.sh
		run_func do_install
	fi
	touch -f $XBPS_INSTALL_DONE
fi

# Run post_install()
if [ ! -f $XBPS_POST_INSTALL_DONE ]; then
	cd $wrksrc
	[ -n "$build_wrksrc" ] && cd $build_wrksrc
	if declare -f post_install >/dev/null; then
		run_func post_install
		touch -f $XBPS_POST_INSTALL_DONE
	fi
fi

exit 0
