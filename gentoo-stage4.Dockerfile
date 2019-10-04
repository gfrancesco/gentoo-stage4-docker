# syntax = docker/dockerfile:experimental

FROM alpine:latest as alpine-builder
LABEL stage=builder-stage3
LABEL maintainer="Francesco Gianni <https://www.fvg.io>"

ARG STAGE3_DIR=/gentoo-stage3
WORKDIR $STAGE3_DIR
WORKDIR /gentoo-stage3-dwl

ARG SNAPSHOT="portage-latest.tar.xz"
ARG DIST_PORTAGE="https://ftp-osl.osuosl.org/pub/gentoo/snapshots"
ARG SIGNING_KEY_PORTAGE="0xEC590EEAC9189250"

ARG ARCH=amd64
ARG MICROARCH=amd64
ARG SUFFIX
ARG DIST="https://ftp-osl.osuosl.org/pub/gentoo/releases/${ARCH}/autobuilds"
ARG SIGNING_KEY="0xBB572E0E2D182910"

RUN apk --no-cache add gnupg tar wget xz
RUN --mount=type=tmpfs,target=/gentoo-stage3-dwl echo "Building Gentoo Container image for ${ARCH} ${SUFFIX} fetching from ${DIST}" \
 && STAGE3PATH="$(wget -O- "${DIST}/latest-stage3-${MICROARCH}${SUFFIX}.txt" | tail -n 1 | cut -f 1 -d ' ')" \
 && echo "STAGE3PATH:" $STAGE3PATH \
 && STAGE3="$(basename ${STAGE3PATH})" \
 && wget -q "${DIST}/${STAGE3PATH}" "${DIST}/${STAGE3PATH}.CONTENTS" "${DIST}/${STAGE3PATH}.DIGESTS.asc" \
 && gpg --list-keys \
 && echo "standard-resolver" >> ~/.gnupg/dirmngr.conf \
 && echo "honor-http-proxy" >> ~/.gnupg/dirmngr.conf \
 && echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf \
 && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys ${SIGNING_KEY} \
 && gpg --verify "${STAGE3}.DIGESTS.asc" \
 && awk '/# SHA512 HASH/{getline; print}' ${STAGE3}.DIGESTS.asc | sha512sum -c \
 && tar xpf "${STAGE3}" --xattrs --numeric-owner -C ${STAGE3_DIR} \
 && sed -i -e 's/#rc_sys=""/rc_sys="docker"/g' ${STAGE3_DIR}/etc/rc.conf \
 && echo 'UTC' > ${STAGE3_DIR}/etc/timezone \
 && mkdir -p ${STAGE3_DIR}/var/tmp/notmpfs ${STAGE3_DIR}/etc/portage/env \
 && rm -fr ${STAGE3_DIR}/usr/share/doc ${STAGE3_DIR}/usr/share/info ${STAGE3_DIR}/usr/share/man &> /dev/null \
 && rm -fr ${STAGE3_DIR}/tmp/* ${STAGE3_DIR}/tmp/.* ${STAGE3_DIR}/var/log/* ${STAGE3_DIR}/var/log/.* &> /dev/null || true


ARG PORTAGE_DIR=/portage
WORKDIR $PORTAGE_DIR
WORKDIR /portage-dwl

RUN --mount=type=tmpfs,target=/portage-dwl wget -q "${DIST_PORTAGE}/${SNAPSHOT}" "${DIST_PORTAGE}/${SNAPSHOT}.gpgsig" "${DIST_PORTAGE}/${SNAPSHOT}.md5sum" \
 && gpg --list-keys \
 && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys ${SIGNING_KEY_PORTAGE} \
 && gpg --verify "${SNAPSHOT}.gpgsig" "${SNAPSHOT}" \
 && md5sum -c ${SNAPSHOT}.md5sum \
 && mkdir -p ${PORTAGE_DIR}/var/db/repos ${PORTAGE_DIR}/var/cache/binpkgs ${PORTAGE_DIR}/var/cache/distfiles \
 && tar xJpf ${SNAPSHOT} -C ${PORTAGE_DIR}/var/db/repos \
 && mv ${PORTAGE_DIR}/var/db/repos/portage ${PORTAGE_DIR}/var/db/repos/gentoo


FROM scratch AS gentoo-builder

ARG STAGE3_DIR=/gentoo-stage3
ARG CPU_N=8

COPY --from=alpine-builder $STAGE3_DIR /

RUN --mount=type=tmpfs,target=/var/log \
	echo en_US.UTF-8 UTF-8 >> /etc/locale.gen && locale-gen
RUN	echo 'COMMON_FLAGS="-march=native -Os -pipe"' > /etc/portage/make.conf && \
	echo 'CFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf && \
	echo 'CXXFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf && \
	echo 'FCFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf && \
	echo 'FFLAGS="${COMMON_FLAGS}"' >> /etc/portage/make.conf && \
#
	echo 'PORTDIR="/var/db/repos/gentoo"' >> /etc/portage/make.conf && \
	echo 'DISTDIR="/var/cache/distfiles"' >> /etc/portage/make.conf && \
	echo 'PKGDIR="/var/cache/binpkgs"' >> /etc/portage/make.conf && \
#
	echo 'LC_MESSAGES=C' >> /etc/portage/make.conf && \
	echo 'LINGUAS="en"' >> /etc/portage/make.conf && \
	echo 'FEATURES="noinfo nodoc noman unmerge-orphans"' >> /etc/portage/make.conf && \
	echo 'MAKEOPTS="-j'${CPU_N}'"' >> /etc/portage/make.conf && \
#
	echo 'VIDEO_CARDS=""' >> /etc/portage/make.conf && \
	echo 'ALSA_CARDS=""' >> /etc/portage/make.conf && \
	echo 'APACHE2_MODULES=""' >> /etc/portage/make.conf && \
	echo 'VIDEO_CARDS="fbdev vesa dummy v4l"' >> /etc/portage/make.conf && \
	echo 'PYTHON_TARGETS="python2_7 python3_6"' >> /etc/portage/make.conf && \
#
	echo 'USE="-X -ipv6 -manpager minimal -openmp -smartcard -spell -xorg"' >> /etc/portage/make.conf
RUN echo 'PORTAGE_TMPDIR="/var/tmp/notmpfs"' > /etc/portage/env/notmpfs.conf && \
	echo 'sys-devel/gcc notmpfs.conf' > /etc/portage/package.env

RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	emerge --config sys-libs/timezone-data && \
	eselect news read new && \
	echo 'LANG="en_US.UTF-8"' >> /etc/env.d/02locale && \
	env-update

# emerge now to run etc-update /etc/locale.gen
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	emerge glibc gentoolkit empty

RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	empty -f -i in.fifo -o out.fifo etc-update --automode -9 && sleep 1 && \
	echo "YES" > in.fifo && sleep 1 && \
	while [ -e in.fifo ]; do echo "y" > in.fifo; sleep 1; done;

# emerge @world run n.1
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	emerge -ve --with-bdeps=y @world && revdep-rebuild

# run etc-update on /etc/hosts /etc/rc.conf
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	empty -f -i in.fifo -o out.fifo etc-update --automode -9 && sleep 1 && \
	echo "YES" > in.fifo && sleep 1 && \
	while [ -e in.fifo ]; do echo "y" > in.fifo; sleep 1; done;

# emerge @world run n.2
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	emerge -ve --with-bdeps=y @world && revdep-rebuild

# sync
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	emerge --sync

# update @world
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	emerge -v -u --newuse --deep --with-bdeps=y @world

# cleanup
RUN --security=insecure \
	--mount=type=cache,target=/var/db/repos,from=alpine-builder,source=/portage/var/db/repos \
	--mount=type=cache,target=/var/log \
	--mount=type=cache,target=/var/tmp/notmpfs \
	--mount=type=tmpfs,target=/var/tmp/portage \
	revdep-rebuild && emerge @module-rebuild && emerge --depclean
RUN eselect news read new
RUN --security=insecure rm -rf /var/cache/distfiles/*

FROM scratch

COPY --from=gentoo-builder / /

WORKDIR /root

CMD ["/bin/bash"]