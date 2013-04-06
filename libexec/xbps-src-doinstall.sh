#!//bin/bash
#
# Passed arguments:
#	$1 - pkgname [REQUIRED]
#	$2 - cross target [OPTIONAL]

_add_trigger() {
	local f= found= name="$1"

	for f in ${triggers}; do
		[ "$f" = "$name" ] && found=1
	done
	[ -z "$found" ] && triggers="$triggers $name"
}

process_metadata_scripts() {
	local action="$1"
	local action_file="$2"
	local tmpf=$(mktemp -t xbps-install.XXXXXXXXXX) || exit 1
	local fpattern="s|${DESTDIR}||g;s|^\./$||g;/^$/d"
	local targets= f= _f= info_files= home= shell= descr= groups=
	local found= triggers_found= _icondirs= _schemas= _mods= _tmpfiles=

	case "$action" in
		install) ;;
		remove) ;;
		*) return 1;;
	esac

	cd ${DESTDIR}
	cat >> $tmpf <<_EOF
#!/bin/sh -e
#
# Generic INSTALL/REMOVE script. Arguments passed to this script:
#
# \$1 = ACTION	[pre/post]
# \$2 = PKGNAME
# \$3 = VERSION
# \$4 = UPDATE	[yes/no]
# \$5 = CONF_FILE (path to xbps.conf)
#
# Note that paths must be relative to CWD, to avoid calling
# host commands if /bin/sh (dash) is not installed and it's
# not possible to chroot(3).
#

export PATH="/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

TRIGGERSDIR="./var/db/xbps/triggers"
ACTION="\$1"
PKGNAME="\$2"
VERSION="\$3"
UPDATE="\$4"
CONF_FILE="\$5"

#
# The following code will run the triggers.
#
_EOF
	#
	# Handle kernel hooks.
	#
	if [ -n "${kernel_hooks_version}" ]; then
		_add_trigger kernel-hooks
		echo "export kernel_hooks_version=\"${kernel_hooks_version}\"" >> $tmpf
	fi
	#
	# Handle DKMS modules.
	#
	if [ -n "${dkms_modules}" ]; then
		_add_trigger dkms
		echo "export dkms_modules=\"${dkms_modules}\"" >> $tmpf
	fi
	#
	# Handle system groups.
	#
	if [ -n "${system_groups}" ]; then
		_add_trigger system-accounts
		echo "export system_groups=\"${system_groups}\"" >> $tmpf
	fi
	#
	# Handle system accounts.
	#
	if [ -n "${system_accounts}" ]; then
		_add_trigger system-accounts
		echo "export system_accounts=\"${system_accounts}\"" >> $tmpf
		for f in ${system_accounts}; do
			eval homedir="\$${f}_homedir"
			eval shell="\$${f}_shell"
			eval descr="\$${f}_descr"
			eval groups="\$${f}_groups"
			if [ -n "$homedir" ]; then
				echo "export ${f}_homedir=\"$homedir\"" >> $tmpf
			fi
			if [ -n "$shell" ]; then
				echo "export ${f}_shell=\"$shell\"" >> $tmpf
			fi
			if [ -n "$descr" ]; then
				echo "export ${f}_descr=\"$descr\"" >> $tmpf
			fi
			if [ -n "$groups" ]; then
				echo "export ${f}_groups=\"${groups}\"" >> $tmpf
			fi
			unset homedir shell descr groups
		done
	fi
	#
	# Handle mkdirs trigger.
	#
	if [ -n "${make_dirs}" ]; then
		_add_trigger mkdirs
		echo "export make_dirs=\"${make_dirs}\"" >> $tmpf
	fi
	#
	# Handle systemd services.
	#
	if [ -n "${systemd_services}" ]; then
		_add_trigger systemd-service
		echo "export systemd_services=\"${systemd_services}\"" >> $tmpf
	fi
	if [ -d ${DESTDIR}/usr/lib/tmpfiles.d ]; then
		for f in ${DESTDIR}/usr/lib/tmpfiles.d/*; do
			_tmpfiles="${_tmpfiles} $(basename $f)"
		done
		_add_trigger systemd-service
		echo "export systemd_tmpfiles=\"${_tmpfiles}\"" >> $tmpf
	fi
	if [ -d ${DESTDIR}/usr/lib/modules-load.d ]; then
		for f in ${DESTDIR}/usr/lib/modules-load.d/*; do
			_mods="${_mods} $(basename $f)"
		done
		_add_trigger systemd-service
		echo "export systemd_modules=\"${_mods}\"" >> $tmpf
	fi
	#
	# Handle GNU Info files.
	#
	if [ -d "${DESTDIR}/usr/share/info" ]; then
		unset info_files
		for f in $(find ${DESTDIR}/usr/share/info -type f); do
			j=$(echo $f|sed -e "$fpattern")
                        [ "$j" = "" ] && continue
			[ "$j" = "/usr/share/info/dir" ] && continue
			if [ -z "$info_files" ]; then
				info_files="$j"
			else
				info_files="$info_files $j"
			fi
		done
		if [ -n "${info_files}" ]; then
			_add_trigger info-files
			echo "export info_files=\"${info_files}\"" >> $tmpf
		fi
        fi
	#
	# (Un)Register a shell in /etc/shells.
	#
	if [ -n "${register_shell}" ]; then
		_add_trigger register-shell
		echo "export register_shell=\"${register_shell}\"" >> $tmpf
	fi
	#
	# Handle SGML/XML catalog entries via xmlcatmgr.
	#
	if [ -n "${sgml_catalogs}" ]; then
		for catalog in ${sgml_catalogs}; do
			sgml_entries="${sgml_entries} CATALOG ${catalog} --"
		done
	fi
	if [ -n "${sgml_entries}" ]; then
		echo "export sgml_entries=\"${sgml_entries}\"" >> $tmpf
	fi
	if [ -n "${xml_catalogs}" ]; then
		for catalog in ${xml_catalogs}; do
			xml_entries="${xml_entries} nextCatalog ${catalog} --"
		done
	fi
	if [ -n "${xml_entries}" ]; then
		echo "export xml_entries=\"${xml_entries}\"" >> $tmpf
	fi
	if [ -n "${sgml_entries}" -o -n "${xml_entries}" ]; then
		_add_trigger xml-catalog
	fi
	#
	# Handle X11 font updates via mkfontdir/mkfontscale.
	#
	if [ -n "${font_dirs}" ]; then
		_add_trigger x11-fonts
		echo "export font_dirs=\"${font_dirs}\"" >> $tmpf
	fi
	#
	# Handle GTK+ Icon cache directories.
	#
	if [ -d ${DESTDIR}/usr/share/icons ]; then
		for f in ${DESTDIR}/usr/share/icons/*; do
			[ ! -d "${f}" ] && continue
			_icondirs="${_icondirs} ${f#${DESTDIR}}"
		done
		if [ -n "${_icondirs}" ]; then
			echo "export gtk_iconcache_dirs=\"${_icondirs}\"" >> $tmpf
			_add_trigger gtk-icon-cache
		fi
	fi
        #
	# Handle .desktop files in /usr/share/applications with
	# desktop-file-utils.
	#
	if [ -d ${DESTDIR}/usr/share/applications ]; then
		_add_trigger update-desktopdb
	fi
	#
	# Handle GConf schemas/entries files with gconf-schemas.
	#
	if [ -d ${DESTDIR}/usr/share/gconf/schemas ]; then
		_add_trigger gconf-schemas
		for f in ${DESTDIR}/usr/share/gconf/schemas/*.schemas; do
			_schemas="${_schemas} $(basename $f)"
		done
		echo "export gconf_schemas=\"${_schemas}\"" >> $tmpf
	fi
	#
	# Handle gio-modules trigger.
	#
	if [ -d ${DESTDIR}/usr/lib/gio/modules ]; then
		_add_trigger gio-modules
	fi
	#
	# Handle gsettings schemas in /usr/share/glib-2.0/schemas with
	# gsettings-schemas.
	#
	if [ -d ${DESTDIR}/usr/share/glib-2.0/schemas ]; then
		_add_trigger gsettings-schemas
	fi
	#
	# Handle mime database in /usr/share/mime with update-mime-database.
	#
	if [ -d ${DESTDIR}/usr/share/mime ]; then
		_add_trigger mimedb
	fi
	#
	# Handle python bytecode archives with pycompile trigger.
	#
	if [ -n "${pycompile_dirs}" -o -n "${pycompile_module}" ]; then
		if [ -n "${pycompile_dirs}" ]; then
			echo "export pycompile_dirs=\"${pycompile_dirs}\"" >>$tmpf
		fi
		if [ -n "${pycompile_module}" ]; then
			echo "export pycompile_module=\"${pycompile_module}\"" >>$tmpf
		fi
		_add_trigger pycompile
	fi

	# End of trigger var exports.
	echo >> $tmpf

	#
	# Write the INSTALL/REMOVE package scripts.
	#
	if [ -n "$triggers" ]; then
		triggers_found=1
		echo "case \"\${ACTION}\" in" >> $tmpf
		echo "pre)" >> $tmpf
		for f in ${triggers}; do
			if [ ! -f $XBPS_TRIGGERSDIR/$f ]; then
				rm -f $tmpf
				msg_error "$pkgname: unknown trigger $f, aborting!\n"
			fi
		done
		for f in ${triggers}; do
			targets=$($XBPS_TRIGGERSDIR/$f targets)
			for j in ${targets}; do
				if ! $(echo $j|grep -q pre-${action}); then
					continue
				fi
				printf "\t\${TRIGGERSDIR}/$f run $j \${PKGNAME} \${VERSION} \${UPDATE} \${CONF_FILE}\n" >> $tmpf
				printf "\t[ \$? -ne 0 ] && exit \$?\n" >> $tmpf
			done
		done
		printf "\t;;\n" >> $tmpf
		echo "post)" >> $tmpf
		for f in ${triggers}; do
			targets=$($XBPS_TRIGGERSDIR/$f targets)
			for j in ${targets}; do
				if ! $(echo $j|grep -q post-${action}); then
					continue
				fi
				printf "\t\${TRIGGERSDIR}/$f run $j \${PKGNAME} \${VERSION} \${UPDATE} \${CONF_FILE}\n" >> $tmpf
				printf "\t[ \$? -ne 0 ] && exit \$?\n" >> $tmpf
			done
		done
		printf "\t;;\n" >> $tmpf
		echo "esac" >> $tmpf
		echo >> $tmpf
	fi

	if [ -z "$triggers" -a ! -f "$action_file" ]; then
		rm -f $tmpf
		return 0
	fi

	case "$action" in
	install)
		if [ -f ${action_file} ]; then
			found=1
			cat ${action_file} >> $tmpf
		fi
		echo "exit 0" >> $tmpf
		mv $tmpf ${DESTDIR}/INSTALL && chmod 755 ${DESTDIR}/INSTALL
		;;
	remove)
		unset found
		if [ -f ${action_file} ]; then
			found=1
			cat ${action_file} >> $tmpf
		fi
		echo "exit 0" >> $tmpf
		mv $tmpf ${DESTDIR}/REMOVE && chmod 755 ${DESTDIR}/REMOVE
		;;
	esac
}

prepare_destdir() {
	local f= i= j= found= dirat= lnkat= newlnk=
	local TMPFLIST= TMPFPLIST= found= _depname=
	local fpattern="s|${DESTDIR}||g;s|^\./$||g;/^$/d"

	if [ ! -d "${DESTDIR}" ]; then
		msg_error "$pkgver: not installed in destdir!\n"
	fi

	#
	# Always remove metadata files generated in a previous installation.
	#
	for f in INSTALL REMOVE files.plist props.plist flist rdeps; do
		[ -f ${DESTDIR}/${f} ] && rm -f ${DESTDIR}/${f}
	done

	#
	# If package provides virtual packages, create dynamically the
	# required configuration file.
	#
	if [ -n "$provides" ]; then
		_tmpf=$(mktemp) || msg_error "$pkgver: failed to create tempfile.\n"
		echo "# Virtual packages provided by '${pkgname}':" >>${_tmpf}
		for f in ${provides}; do
			echo "virtual-package ${pkgname} { targets = \"${f}\" }" >>${_tmpf}
		done
		install -Dm644 ${_tmpf} \
			${DESTDIR}/etc/xbps/virtualpkg.d/${pkgname}.conf
		rm -f ${_tmpf}
	fi

        #
        # Find out if this package contains info files and compress
        # all them with gzip.
        #
	if [ -f ${DESTDIR}/usr/share/info/dir ]; then
		# Always remove this file if curpkg is not texinfo.
		if [ "$pkgname" != "texinfo" ]; then
			[ -f ${DESTDIR}/usr/share/info/dir ] && \
				rm -f ${DESTDIR}/usr/share/info/dir
		fi
		# Add info-files trigger.
		triggers="info-files $triggers"
		msg_normal "$pkgver: processing info(1) files...\n"

		find ${DESTDIR}/usr/share/info -type f -follow | while read f
		do
			j=$(echo "$f"|sed -e "$fpattern")
			[ "$j" = "" ] && continue
			[ "$j" = "/usr/share/info/dir" ] && continue
			# Ignore compressed files.
			if $(echo "$j"|grep -q '.*.gz$'); then
				continue
			fi
			# Ignore non info files.
			if ! $(echo "$j"|grep -q '.*.info$') && \
			   ! $(echo "$j"|grep -q '.*.info-[0-9]*$'); then
				continue
			fi
			if [ -h ${DESTDIR}/"$j" ]; then
				dirat=$(dirname "$j")
				lnkat=$(readlink ${DESTDIR}/"$j")
				newlnk=$(basename "$j")
				rm -f ${DESTDIR}/"$j"
				cd ${DESTDIR}/"$dirat"
				ln -s "${lnkat}".gz "${newlnk}".gz
				continue
			fi
			echo "   Compressing info file: $j..."
			gzip -nfq9 ${DESTDIR}/"$j"
		done
	fi

	#
	# Find out if this package contains manual pages and
	# compress all them with gzip.
	#
	if [ -d "${DESTDIR}/usr/share/man" ]; then
		msg_normal "$pkgver: processing manual pages...\n"
		find ${DESTDIR}/usr/share/man -type f -follow | while read f
		do
			j=$(echo "$f"|sed -e "$fpattern")
			[ "$j" = "" ] && continue
			if $(echo "$j"|grep -q '.*.gz$'); then
				continue
			fi
			if [ -h ${DESTDIR}/"$j" ]; then
				dirat=$(dirname "$j")
				lnkat=$(readlink ${DESTDIR}/"$j")
				newlnk=$(basename "$j")
				rm -f ${DESTDIR}/"$j"
				cd ${DESTDIR}/"$dirat"
				ln -s "${lnkat}".gz "${newlnk}".gz
				continue
			fi
			echo "   Compressing manpage: $j..."
			gzip -nfq9 ${DESTDIR}/"$j"
		done
	fi

	#
	# Create package's flist for bootstrap packages.
	#
	find ${DESTDIR} -print > ${DESTDIR}/flist
	sed -i -e "s|${DESTDIR}||g;s|/flist||g;/^$/d" ${DESTDIR}/flist

	#
	# Create the INSTALL/REMOVE scripts if package uses them
	# or uses any available trigger.
	#
	local meta_install meta_remove
	if [ -n "${sourcepkg}" -a "${sourcepkg}" != "${pkgname}" ]; then
		meta_install=${XBPS_SRCPKGDIR}/${pkgname}/${pkgname}.INSTALL
		meta_remove=${XBPS_SRCPKGDIR}/${pkgname}/${pkgname}.REMOVE
	else
		meta_install=${XBPS_SRCPKGDIR}/${pkgname}/INSTALL
		meta_remove=${XBPS_SRCPKGDIR}/${pkgname}/REMOVE
	fi
	process_metadata_scripts install ${meta_install} || \
		msg_error "$pkgver: failed to write INSTALL metadata file!\n"

	process_metadata_scripts remove ${meta_remove} || \
		msg_error "$pkgver: failed to write REMOVE metadata file!\n"

	msg_normal "$pkgver: installed successfully to destdir.\n"
}

if [ $# -lt 1 -o $# -gt 2 ]; then
	echo "$(basename $0): invalid number of arguments: pkgname [cross-target]"
	exit 1
fi

PKGNAME="$1"
CROSS_BUILD="$2"

. $XBPS_CONFIG_FILE
. $XBPS_SHUTILSDIR/common.sh
. $XBPS_SHUTILSDIR/install_files.sh

for f in $XBPS_COMMONDIR/*.sh; do
	. $f
done

setup_subpkg "$PKGNAME"

if [ -z "$pkgname" -o -z "$version" ]; then
	msg_error "$1: pkgname/version not set in pkg template!\n"
fi

XBPS_INSTALL_DONE="$wrksrc/.xbps_${pkgname}_${CROSS_BUILD}_install_done"
XBPS_PRE_INSTALL_DONE="$wrksrc/.xbps_${pkgname}_${CROSS_BUILD}_pre_install_done"
XBPS_POST_INSTALL_DONE="$wrksrc/.xbps_${pkgname}_${CROSS_BUILD}_post_install_done"

if [ -f $XBPS_INSTALL_DONE ]; then
	exit 0
fi
#
# There's nothing we can do if it is a meta template.
# Just creating the dir is enough.
#
if [ "$build_style" = "meta-template" ]; then
	mkdir -p $XBPS_DESTDIR/$pkgname-$version
	exit 0
fi

cd $wrksrc || msg_error "$pkgver: cannot access to wrksrc [$wrksrc]\n"
if [ -n "$build_wrksrc" ]; then
	cd $build_wrksrc \
		|| msg_error "$pkgver: cannot access to build_wrksrc [$build_wrksrc]\n"
fi

# Run pre_install()
if [ -z "$SUBPKG" -a ! -f $XBPS_PRE_INSTALL_DONE ]; then
	if declare -f pre_install >/dev/null; then
		run_func pre_install
		touch -f $XBPS_PRE_INSTALL_DONE
	fi
fi

# Run do_install()
cd $wrksrc
[ -n "$build_wrksrc" ] && cd $build_wrksrc
if declare -f do_install >/dev/null; then
	run_func do_install
else
	if [ ! -r $XBPS_HELPERSDIR/${build_style}.sh ]; then
		msg_error "$pkgver: cannot find build helper $XBPS_HELPERSDIR/${build_style}.sh!\n"
	fi
	. $XBPS_HELPERSDIR/${build_style}.sh
	run_func do_install
fi

# Run post_install()
if [ -z "$SUBPKG" -a ! -f $XBPS_POST_INSTALL_DONE ]; then
	cd $wrksrc
	[ -n "$build_wrksrc" ] && cd $build_wrksrc
	if declare -f post_install >/dev/null; then
		run_func post_install
		touch -f $XBPS_POST_INSTALL_DONE
	fi
fi

# Remove libtool archives by default.
if [ -z "$keep_libtool_archives" ]; then
	msg_normal "$pkgver: removing libtool archives...\n"
	find ${DESTDIR} -type f -name \*.la -delete
fi

# Remove bytecode python generated files.
msg_normal "$pkgver: removing python bytecode archives...\n"
find ${DESTDIR} -type f -name \*.py[co] -delete

# Always remove perllocal.pod and .packlist files.
if [ "$pkgname" != "perl" ]; then
	find ${DESTDIR} -type f -name perllocal.pod -delete
	find ${DESTDIR} -type f -name .packlist -delete
fi

# Remove empty directories by default.
for f in $(find ${DESTDIR} -depth -type d); do
	rmdir $f 2>/dev/null && \
		msg_warn "$pkgver: removed empty dir: ${f##${DESTDIR}}\n"
done

# Prepare pkg destdir and install/remove scripts.
prepare_destdir

touch -f $XBPS_INSTALL_DONE

exit 0