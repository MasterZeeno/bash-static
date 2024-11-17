#!/bin/bash

# For Linux, also builds musl for truly static linking if
# musl is not installed.

set -e
set -o pipefail
shopt -s nullglob

# load version info
# shellcheck source=./version.sh
. version.sh

download_and_verify() {
  curl -LO "$1"
  curl -LO "$1.$2"
  gpg --batch \
  --verify "$1.$2" "$1"
}

init_bash() {
  BASH_BASE_NAME="bash-$BASH_VERSION"
  BASH_FULL_URL="$BASH_URL/$BASH_BASE_NAME"
  BASH_TAR_URL="${BASH_FULL_URL}.tar.gz"
  BASH_TAR="${BASH_TAR_URL##*/}"
  BASH_PATCH_NAME="${BASH_BASE_NAME%.*}"
  BASH_PATCH_URL="$BASH_URL/$BASH_PATCH_NAME-patches"
}

init_musl() {
  MUSL_BASE_NAME="musl-$MUSL_VERSION"
  MUSL_FULL_URL="$MUSL_URL/$MUSL_BASE_NAME"
  MUSL_TAR_URL="${MUSL_FULL_URL}.tar.gz"
  MUSL_TAR="${MUSL_TAR_URL##*/}"
}

init_gpg() {
  GNUPGHOME="$(mktemp -d)"
  export GNUPGHOME
  gpg_args=(
    --batch
    --keyserver
    hkps://keyserver.ubuntu.com:443
    --recv-keys
  )
  gpg_pub_keys=(
    7C0135FB088AAF6C66C650B9BB5869F064EA74AB
    836489290BB6B70F99FFDA0556BCDB593020450F
  )
  for key in "${gpg_pub_keys[@]}"; do
    gpg "${gpg_args[@]}" "$key"
  done
}

target="$1"
arch="$2"

if [[ "$target" == "" ]]; then
  echo "! no target specified" >&2
  exit 1
fi

if [[ "$arch" == "" ]]; then
  echo "! no arch specified" >&2
  exit 1
fi

if [ -d build ]; then
  echo "= removing previous build directory"
  rm -rf build
fi

# make build directory
mkdir build && pushd build

# pre-prepare gpg for verificaiton
echo "= preparing gpg"
init_gpg

# download tarballs
echo "= downloading bash"
init_bash
download_and_verify "$BASH_TAR_URL" sig

echo "= extracting bash"
tar -xf "$BASH_TAR"

echo "= patching bash"

for PATCH in $(seq 1 ${BASH_VERSION##*.}); do
    PADDED_PATCH="$(printf '%03d' "$PATCH")"
    PATCH_FILE="${BASH_PATCH_NAME//[-.]/}-${PADDED_LVL}"
    download_and_verify "$BASH_PATCH_URL/$PATCH_FILE" sig
    
    pushd "$BASH_BASE_NAME"
    patch -p0 < ../"$PATCH_FILE"
    popd
done

echo "= patching with any custom patches we have"
for i in ../custom/*.patch; do
    echo $i
    pushd "$BASH_BASE_NAME"
    patch -p1 < ../"$i"
    popd
done

configure_args=()

if [ "$target" = "linux" ]; then
  if [ "$(grep ID= < /etc/os-release | head -n1)" = "ID=alpine" ]; then
    echo "= skipping installation of musl because this is alpine linux (and it is already installed)"
  else
    echo "= downloading musl"
    init_musl
    download_and_verify "$MUSL_TAR_URL" asc

    echo "= extracting musl"
    tar -xf "$MUSL_TAR"

    echo "= building musl"
    working_dir=$(pwd)

    install_dir=${working_dir}/musl-install

    pushd "$MUSL_BASE_NAME"
    ./configure --prefix="${install_dir}"
    make install
    popd

    echo "= setting CC to musl-gcc"
    export CC=${working_dir}/musl-install/bin/musl-gcc
  fi
  export CFLAGS="-static"
else
  echo "= WARNING: your platform does not support static binaries."
  echo "= (This is mainly due to non-static libc availability.)"
  if [[ $target == "macos" ]]; then
    # set minimum version of macOS to 10.13
    export MACOSX_DEPLOYMENT_TARGET="10.13"
    # https://www.gnu.org/software/bash/manual/html_node/Compilers-and-Options.html
    export CC="clang -std=c89 -Wno-implicit-function-declaration -Wno-return-type"

    # use included gettext to avoid reading from other places, like homebrew
    configure_args=("${configure_args[@]}" "--with-included-gettext")

    # if $arch is aarch64 for mac, target arm64e
    if [[ $arch == "aarch64" ]]; then
      export CFLAGS="-target arm64-apple-macos"
      configure_args=("${configure_args[@]}" "--host=aarch64-apple-darwin")
    else
      export CFLAGS="-target x86_64-apple-macos10.12"
      configure_args=("${configure_args[@]}" "--host=x86_64-apple-macos10.12")
    fi
  fi
fi

echo "= building bash"

pushd "$BASH_BASE_NAME"
autoconf -f
CFLAGS="$CFLAGS -Os" ./configure --without-bash-malloc "${configure_args[@]}"
make
make tests

# "$BASH_BASE_NAME"
popd
# build
popd

if [ ! -d releases ]; then
  mkdir releases
fi

echo "= extracting bash binary"
cp "build/$BASH_BASE_NAME/bash" releases

echo "= done"



