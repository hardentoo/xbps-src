# -*-* shell *-*-

chroot_init() {
	XBPSSRC_CF=$XBPS_MASTERDIR/etc/xbps/xbps-src.conf

	cat > $XBPSSRC_CF <<_EOF
# Generated configuration file by xbps-src, DO NOT EDIT!
XBPS_MASTERDIR=/
XBPS_CFLAGS="$XBPS_CFLAGS"
XBPS_CXXFLAGS="$XBPS_CXXFLAGS"
XBPS_CPPFLAGS="$XBPS_CPPFLAGS"
XBPS_LDFLAGS="$XBPS_LDFLAGS"
_EOF
	if [ -n "$XBPS_MAKEJOBS" ]; then
		echo "XBPS_MAKEJOBS=$XBPS_MAKEJOBS" >> $XBPSSRC_CF
	fi
	if [ -n "$XBPS_HOSTDIR" ]; then
		echo "XBPS_HOSTDIR=/host" >> $XBPSSRC_CF
	fi
	if [ -n "$XBPS_CCACHE" ]; then
		echo "XBPS_CCACHE=$XBPS_CCACHE" >> $XBPSSRC_CF
	fi
	if [ -n "$XBPS_DISTCC" ]; then
		echo "XBPS_DISTCC=$XBPS_DISTCC" >> $XBPSSRC_CF
		echo "XBPS_DISTCC_HOSTS=\"${XBPS_DISTCC_HOSTS}\"" >> $XBPSSRC_CF
	fi
	if [ -n "$XBPS_USE_GIT_REVS" ]; then
		echo "XBPS_USE_GIT_REVS=yes" >> $XBPSSRC_CF
	fi
	if [ -n "$XBPS_DEBUG_PKGS" ]; then
		echo "XBPS_DEBUG_PKGS=yes" >> $XBPSSRC_CF
	fi

	echo "# End of configuration file." >> $XBPSSRC_CF

	# Create custom script to start the chroot bash shell.
	cat > $XBPS_MASTERDIR/bin/xbps-shell <<_EOF
#!/bin/sh

XBPS_SRC_VERSION="$XBPS_SRC_VERSION"

. /etc/xbps/xbps-src.conf

PATH=/usr/bin:/usr/sbin:/usr/lib/perl5/core_perl/bin

exec env -i PATH="\$PATH" DISTCC_HOSTS="\$XBPS_DISTCC_HOSTS" DISTCC_DIR="/distcc" @@XARCH@@ \
	CCACHE_DIR="/ccache" IN_CHROOT=1 LANG=en_US.UTF-8 TERM=linux HOME="/tmp" \
	PS1="[\u@$XBPS_MASTERDIR \W]$ " /bin/bash +h

_EOF
	if [ -n "$XBPS_ARCH" ]; then
		sed -e "s,@@XARCH@@,XBPS_ARCH=${XBPS_ARCH},g" -i $XBPS_MASTERDIR/bin/xbps-shell
	else
		sed -e 's,@@XARCH@@,,g' -i $XBPS_MASTERDIR/bin/xbps-shell
	fi
	chmod 755 $XBPS_MASTERDIR/bin/xbps-shell

	cp -f /etc/resolv.conf $XBPS_MASTERDIR/etc

	# Update xbps alternative repository if set.
	mkdir -p $XBPS_MASTERDIR/etc/xbps/repos
	if [ -n "$XBPS_ALT_REPOSITORY" ]; then
		( \
		echo "repository=/host/binpkgs/${XBPS_ALT_REPOSITORY}"; \
		echo "repository=/host/binpkgs/${XBPS_ALT_REPOSITORY}/nonfree"; \
		) > $XBPS_MASTERDIR/etc/xbps/repos/alternative.conf
	else
		: > $XBPS_MASTERDIR/etc/xbps/repos/alternative.conf
	fi
}

chroot_prepare() {
	local f=

	if [ -f $XBPS_MASTERDIR/.xbps_chroot_init ]; then
		return 0
	elif [ ! -f $XBPS_MASTERDIR/bin/bash ]; then
		msg_error "Bootstrap not installed in $XBPS_MASTERDIR, can't continue.\n"
	fi

	# Create some required files.
	cp -f /etc/services $XBPS_MASTERDIR/etc
	[ -f /etc/localtime ] && cp -f /etc/localtime $XBPS_MASTERDIR/etc

	for f in dev sys proc host boot; do
		[ ! -d $XBPS_MASTERDIR/$f ] && mkdir -p $XBPS_MASTERDIR/$f
	done

	# Copy /etc/passwd and /etc/group from base-files.
	cp -f $XBPS_SRCPKGDIR/base-files/files/passwd $XBPS_MASTERDIR/etc
	echo "$(whoami):x:$(id -u):$(id -g):$(whoami) user:/tmp:/bin/xbps-shell" \
		>> $XBPS_MASTERDIR/etc/passwd
	cp -f $XBPS_SRCPKGDIR/base-files/files/group $XBPS_MASTERDIR/etc
	echo "$(whoami):x:$(id -g):" >> $XBPS_MASTERDIR/etc/group

	# Copy /etc/hosts from base-files.
	cp -f $XBPS_SRCPKGDIR/base-files/files/hosts $XBPS_MASTERDIR/etc

	ln -sf /bin/bash ${XBPS_MASTERDIR}/bin/sh
	rm -f $XBPS_MASTERDIR/etc/xbps/xbps.conf

	# Prepare default locale: en_US.UTF-8.
	if [ -s ${XBPS_MASTERDIR}/etc/default/libc-locales ]; then
		echo 'en_US.UTF-8 UTF-8' >> ${XBPS_MASTERDIR}/etc/default/libc-locales
		$XBPS_RECONFIGURE_CMD -f glibc-locales
	fi

	touch -f $XBPS_MASTERDIR/.xbps_chroot_init
	[ -n "$1" ] && echo $1 >> $XBPS_MASTERDIR/.xbps_chroot_init

	return 0
}

chroot_sync_repos() {
	local f=

	# Copy xbps configuration files to the masterdir.
	if [ ! -f ${XBPS_MASTERDIR}/etc/xbps/xbps.conf ]; then
		install -Dm644 ${XBPS_SHAREDIR}/chroot/xbps.conf \
			${XBPS_MASTERDIR}/etc/xbps/xbps.conf
	fi
	if [ ! -f ${XBPS_MASTERDIR}/etc/xbps/repos/local.conf ]; then
		install -Dm644 ${XBPS_SHAREDIR}/chroot/repos-local.conf \
			${XBPS_MASTERDIR}/etc/xbps/repos/local.conf
	fi
	if [ ! -f ${XBPS_MASTERDIR}/etc/xbps/repos/remote.conf ]; then
		install -Dm644 ${XBPS_SHAREDIR}/chroot/repos-remote.conf \
			${XBPS_MASTERDIR}/etc/xbps/repos/remote.conf
	fi

	# if -N is set, comment out remote repositories from xbps.conf.
	if [ -n "$XBPS_SKIP_REMOTEREPOS" ]; then
		sed -e 's,^.*\(include("/etc/xbps/repos/remote.conf")$\),#\1,' \
			-i ${XBPS_MASTERDIR}/etc/xbps/xbps.conf
	else
		sed -e 's,^#.*\(include("/etc/xbps/repos/remote.conf")$\),\1,' \
			-i ${XBPS_MASTERDIR}/etc/xbps/xbps.conf
		# Make sure to sync index for remote repositories.
		$CHROOT_CMD $XBPS_MASTERDIR /usr/sbin/xbps-install -S
		if [ -n "$XBPS_CROSS_BUILD" ]; then
			# Copy host keys to the target rootdir.
			if [ ! -d $XBPS_MASTERDIR/usr/$XBPS_CROSS_TRIPLET/var/db/xbps/keys ]; then
				mkdir -p $XBPS_MASTERDIR/usr/$XBPS_CROSS_TRIPLET/var/db/xbps/keys
			fi
			cp -a $XBPS_MASTERDIR/var/db/xbps/keys/*.plist \
				$XBPS_MASTERDIR/usr/$XBPS_CROSS_TRIPLET/var/db/xbps/keys
			env XBPS_TARGET_ARCH=$XBPS_TARGET_ARCH \
				$CHROOT_CMD $XBPS_MASTERDIR /usr/sbin/xbps-install \
				-r /usr/$XBPS_CROSS_TRIPLET -S
		fi
	fi

	return 0
}

chroot_handler() {
	local action="$1" pkg="$2" rv=0 arg= _envargs= _chargs=

	# Debian uses /run/shm instead...
	if [ -d /run/shm ]; then
		mkdir -p ${XBPS_MASTERDIR}/run/shm
		_chargs+=" -S /run/shm"
	elif [ -d /dev/shm ]; then
		mkdir -p ${XBPS_MASTERDIR}/dev/shm
		_chargs+=" -S /dev/shm"
	fi

	if [ -n "$XBPS_HOSTDIR" ]; then
		_chargs+=" -H $XBPS_HOSTDIR"
	fi
	if [ "$XBPS_DISTDIR" != "$XBPS_MASTERDIR/xbps-packages" ]; then
		if [ ! -d $XBPS_MASTERDIR/xbps-packages ]; then
			mkdir -p $XBPS_MASTERDIR/xbps-packages
		fi
		_chargs+=" -D ${XBPS_DISTDIR}"
	fi
	[ -z "$action" -a -z "$pkg" ] && return 1

	case "$action" in
	fetch|extract|build|configure|install-destdir|build-pkg|bootstrap-update|chroot)
		chroot_prepare || return $?
		chroot_init || return $?
		chroot_sync_repos || return $?
		;;
	esac

	if [ "$action" = "chroot" ]; then
		$CHROOT_CMD ${_chargs} $XBPS_MASTERDIR /bin/xbps-shell || rv=$?
	else
		[ -n "$XBPS_BUILD_OPTS" ] && arg="$arg -o $XBPS_BUILD_OPTS"
		[ -n "$XBPS_CROSS_BUILD" ] && arg="$arg -a $XBPS_CROSS_BUILD"
		[ -n "$XBPS_KEEP_ALL" ] && arg="$arg -C"
		[ -n "$NOCOLORS" ] && arg="$arg -L"
		[ -n "$XBPS_BUILD_FORCEMODE" ] && arg="$arg -f"
		[ -n "$XBPS_MAKEJOBS" ] && arg="$arg -j$XBPS_MAKEJOBS"
		[ -n "$XBPS_DEBUG_PKGS" ] && arg="$arg -g"
		[ -n "$XBPS_SKIP_DEPS" ] && arg="$arg -I"
		[ -n "$XBPS_ALT_REPOSITORY" ] && arg="$arg -r $XBPS_ALT_REPOSITORY"

		action="$arg $action"
		env -i PATH=/bin:/sbin:/usr/bin:/usr/sbin HOME=/tmp IN_CHROOT=1 LANG=en_US.UTF-8 \
			$CHROOT_CMD ${_chargs} $XBPS_MASTERDIR /usr/sbin/xbps-src $action $pkg || rv=$?
	fi

	return $rv
}
