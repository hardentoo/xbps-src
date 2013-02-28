# -*-* shell *-*-

git_revs() {
	local _revs= _out= f= _filerev= _files=

	# Get the git revisions from this source pkg.
	cd $XBPS_SRCPKGDIR
	_files=$(git ls-files $1)
	[ -z "${_files}" ] && return

	for f in ${_files}; do
		_filerev=$(git rev-list HEAD $f | head -n1)
		[ -z "${_filerev}" ] && continue
		_out="${f} ${_filerev}"
		if [ -z "${_revs}" ]; then
			_revs="${_out}"
		else
			_revs="${_revs} ${_out}"
		fi
	done

	SRCPKG_GITREVS_FILE=$(mktemp --tmpdir || msg_error "$pkgver: failed to create tmpfile.\n")
	echo "$pkgver git source revisions:"
	set -- ${_revs}
	while [ $# -gt 0 ]; do
		local _file=$1; local _rev=$2
		echo "${_file}: ${_rev}"
		echo "${_file}: ${_rev}" >> ${SRCPKG_GITREVS_FILE}
		shift 2
	done
}

unset_pkg_vars() {
	unset nonfree conf_files noarch triggers replaces softreplace \
		system_accounts system_groups preserve \
		xml_entries sgml_entries xml_catalogs sgml_catalogs \
		font_dirs dkms_modules provides kernel_hooks_version \
		conflicts pycompile_dirs pycompile_module \
		systemd_services make_dirs \
		depends fulldepends run_depends mutable_files
}

make_binpkg() {
	local subpkg= rval=

	[ -z "$pkgname" ] && return 1

	msg_normal "$pkgver: fetching source git revisions, please wait...\n"
	git_revs $pkgname

	for subpkg in ${subpackages}; do
		unset_pkg_vars
		. $XBPS_SRCPKGDIR/$pkgname/$subpkg.template
		pkgname=${subpkg}
		set_tmpl_common_vars
		make_binpkg_real
		# Generate -dbg pkg automagically.
		if [ -d "${XBPS_DESTDIR}/${subpkg}-dbg-${version}" ]; then
			unset_pkg_vars
			pkgname="${subpkg}-dbg"
			pkgver="${pkgname}-${version}_${revision}"
			short_desc="${short_desc} (debug files)"
			DESTDIR="${XBPS_DESTDIR}/${pkgname}-${version}"
			make_binpkg_real
		fi
		setup_tmpl ${sourcepkg}
	done

	if [ -n "${subpackages}" ]; then
		setup_tmpl ${sourcepkg}
	fi
	make_binpkg_real
	rval=$?
	# Generate -dbg pkg automagically.
	if [ -d "${XBPS_DESTDIR}/${pkgname}-dbg-${version}" ]; then
		unset_pkg_vars
		pkgname="${pkgname}-dbg"
		pkgver="${pkgname}-${version}_${revision}"
		short_desc="${short_desc} (debug files)"
		DESTDIR="${XBPS_DESTDIR}/${pkgname}-${version}"
		make_binpkg_real
		setup_tmpl ${sourcepkg}
	fi

	rm -f ${SRCPKG_GITREVS_FILE}
	unset SRCPKG_GITREVS_FILE

	return $rval
}

register_pkg() {
	local rval= _pkgdir="$1" _binpkg="$2"

	while [ -f ${_pkgdir}/.xbps-src-index-lock ]; do
		echo "The repo index is currently locked!"
		sleep 1
	done
	touch -f ${_pkgdir}/.xbps-src-index-lock
	if [ -n "$XBPS_CROSS_TRIPLET" ]; then
		env XBPS_TARGET_ARCH="$XBPS_TARGET_ARCH" $XBPS_RINDEX_CMD -a ${_pkgdir}/${_binpkg}
	else
		$XBPS_RINDEX_CMD -a ${_pkgdir}/${_binpkg}
	fi
	rval=$?
	rm -f ${_pkgdir}/.xbps-src-index-lock

	return $rval
}

#
# This function builds a binary package from an installed xbps
# package in destdir.
#
make_binpkg_real() {
	local binpkg= pkgdir= arch= _deps= f=

	if [ ! -d "${DESTDIR}" ]; then
		msg_warn "$pkgver: cannot find destdir... skipping!\n"
		return 0
	fi

	if [ -n "$noarch" ]; then
		arch=noarch
	elif [ -n "$XBPS_TARGET_MACHINE" ]; then
		arch=$XBPS_TARGET_MACHINE
	else
		arch=$XBPS_MACHINE
	fi
	binpkg=$pkgver.$arch.xbps
	if [ -n "$nonfree" ]; then
		pkgdir=$XBPS_PACKAGESDIR/nonfree
	else
		pkgdir=$XBPS_PACKAGESDIR
	fi

	# Don't overwrite existing binpkgs by default, skip them.
	if [ -f $pkgdir/$binpkg ]; then
		msg_normal "$pkgver: skipping existing $binpkg pkg...\n"
		register_pkg "$pkgdir" "$binpkg"
		return $?
	fi

	if [ ! -d $pkgdir ]; then
		mkdir -p $pkgdir
	fi
	cd $pkgdir

	[ -n "$preserve" ] && _preserve="-p"
	[ -s ${DESTDIR}/rdeps ] && _deps="$(cat ${DESTDIR}/rdeps)"
	if [ -n "$provides" ]; then
		local _provides=
		for f in ${provides}; do
			_provides="${_provides} ${f}"
		done
	fi
	if [ -n "$conflicts" ]; then
		local _conflicts=
		for f in ${conflicts}; do
			_conflicts="${_conflicts} ${f}"
		done
	fi
	if [ -n "$replaces" ]; then
		local _replaces=
		for f in ${replaces}; do
			_replaces="${_replaces} ${f}"
		done
	fi
	if [ -n "$mutable_files" ]; then
		local _mutable_files=
		for f in ${mutable_files}; do
			_mutable_files="${_mutable_files} ${f}"
		done
	fi
	if [ -n "$conf_files" ]; then
		local _conf_files=
		for f in ${conf_files}; do
			_conf_files="${_conf_files} ${f}"
		done
	fi

	msg_normal "$pkgver: building $binpkg ...\n"

	#
	# Create the XBPS binary package.
	#
	${FAKEROOT_CMD} ${XBPS_CREATE_CMD} \
		--architecture ${arch} \
		--provides "${_provides}" \
		--conflicts "${_conflicts}" \
		--replaces "${_replaces}" \
		--mutable-files "${_mutable_files}" \
		--dependencies "${_deps}" \
		--config-files "${_conf_files}" \
		--homepage "${homepage}" \
		--license "${license}" \
		--maintainer "${maintainer}" \
		--long-desc "${long_desc}" --desc "${short_desc}" \
		--built-with "xbps-src-${XBPS_SRC_VERSION}" \
		--pkgver "${pkgver}" --quiet \
		--source-revisions "$(cat ${SRCPKG_GITREVS_FILE:-/dev/null} 2>/dev/null)" \
		${_preserve} ${_sourcerevs} ${DESTDIR}
	rval=$?
	if [ $rval -eq 0 ]; then
		register_pkg "$pkgdir" "$binpkg"
		rval=$?
	else
		rm -f $pkgdir/$binpkg
		msg_error "Failed to build binary package: $binpkg!\n"
	fi

	return $rval
}
