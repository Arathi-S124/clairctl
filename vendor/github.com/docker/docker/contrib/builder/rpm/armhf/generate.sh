#!/bin/bash
# vim: set ts=4 sw=4 noet :

set -e

# usage: ./generate.sh [versions]
#    ie: ./generate.sh
#        to update all Dockerfiles in this directory
#    or: ./generate.sh centos-7
#        to only update centos-7/Dockerfile
#    or: ./generate.sh fedora-newversion
#        to create a new folder and a Dockerfile within it

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	distro="${version%-*}"
	suite="${version##*-}"
	from="${distro}:${suite}"
	installer=yum

	if [[ "$distro" == "fedora" ]]; then
		installer=dnf
	fi

	mkdir -p "$version"

	case "$from" in
		centos:*)
			# get "Development Tools" packages dependencies
			image="multiarch/centos:7.2.1511-armhfp-clean"
			;;
		*)
			image="${from}"
			;;
	esac

	echo "$version -> FROM $image"
	cat > "$version/Dockerfile" <<-EOF
		#
		# THIS FILE IS AUTOGENERATED; SEE "contrib/builder/rpm/armhf/generate.sh"!
		#

		FROM $image
	EOF

	echo >> "$version/Dockerfile"

	extraBuildTags='pkcs11'
	runcBuildTags=

	case "$from" in
		fedora:*)
			echo "RUN ${installer} -y upgrade" >> "$version/Dockerfile"
			;;
		*) ;;
	esac

	case "$from" in
		centos:*)
			# get "Development Tools" packages dependencies

			echo 'RUN yum install -y yum-plugin-ovl' >> "$version/Dockerfile"

			echo 'RUN yum groupinstall --skip-broken -y "Development Tools"' >> "$version/Dockerfile"

			if [[ "$version" == "centos-7" ]]; then
				echo 'RUN yum -y swap -- remove systemd-container systemd-container-libs -- install systemd systemd-libs' >> "$version/Dockerfile"
			fi
			;;
		*)
			echo "RUN ${installer} install -y @development-tools fedora-packager" >> "$version/Dockerfile"
			;;
	esac

	packages=(
		btrfs-progs-devel # for "btrfs/ioctl.h" (and "version.h" if possible)
		device-mapper-devel # for "libdevmapper.h"
		glibc-static
		libseccomp-devel # for "seccomp.h" & "libseccomp.so"
		libselinux-devel # for "libselinux.so"
		libtool-ltdl-devel # for pkcs11 "ltdl.h"
		pkgconfig # for the pkg-config command
		selinux-policy
		selinux-policy-devel
		sqlite-devel # for "sqlite3.h"
		systemd-devel # for "sd-journal.h" and libraries
		tar # older versions of dev-tools do not have tar
		git # required for containerd and runc clone
		cmake # tini build
		vim-common # tini build
	)

	extraBuildTags+=' seccomp'
	runcBuildTags="seccomp selinux"

	echo "RUN ${installer} install -y ${packages[*]}" >> "$version/Dockerfile"

	echo >> "$version/Dockerfile"

	awk '$1 == "ENV" && $2 == "GO_VERSION" { print; exit }' ../../../../Dockerfile.armhf >> "$version/Dockerfile"
	echo 'RUN curl -fSL "https://golang.org/dl/go${GO_VERSION}.linux-armv6l.tar.gz" | tar xzC /usr/local' >> "$version/Dockerfile"
	echo 'ENV PATH $PATH:/usr/local/go/bin' >> "$version/Dockerfile"

	echo >> "$version/Dockerfile"

	echo 'ENV AUTO_GOPATH 1' >> "$version/Dockerfile"

	echo >> "$version/Dockerfile"

	# print build tags in alphabetical order
	buildTags=$( echo "selinux $extraBuildTags" | xargs -n1 | sort -n | tr '\n' ' ' | sed -e 's/[[:space:]]*$//' )

	echo "ENV DOCKER_BUILDTAGS $buildTags" >> "$version/Dockerfile"
	echo "ENV RUNC_BUILDTAGS $runcBuildTags" >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"
done
