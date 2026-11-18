#!/bin/sh
set -eu
: "${SYSROOT:?Set SYSROOT to a Q2 NaN2008 MIPS sysroot}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test -f "$SYSROOT/lib/libc.so.6" || { echo "Missing Q2 libc in SYSROOT" >&2; exit 1; }
test -f "$SYSROOT/lib/libasound.so.2" || { echo "Missing Q2 ALSA in SYSROOT" >&2; exit 1; }
CORE_SRC=${CORE_SRC:-"$ROOT/deps/libretro-fceumm"}
if [ ! -f "$CORE_SRC/Makefile.libretro" ]; then
  mkdir -p "$ROOT/deps"
  git clone --depth 1 https://github.com/libretro/libretro-fceumm.git "$CORE_SRC"
fi
test -f "$CORE_SRC/src/drivers/libretro/libretro-common/include/libretro.h" || {
  echo "FCEUmm Libretro headers missing" >&2; exit 1;
}
export LIBRETRO_INCLUDE="$CORE_SRC/src/drivers/libretro/libretro-common/include"
Q2_CC="clang --target=mipsel-linux-gnu --sysroot=$SYSROOT -march=mips32r2 -mabi=32 -mfp64 -mnan=2008 -mabs=2008"
# Q2's extracted firmware sysroot intentionally lacks GCC startup objects
# (crti.o/crtbeginS.o/crtendS.o/crtn.o). Link the shared core directly with
# LLD instead of letting clang inject missing host/target CRT files.
# Use the firmware's real .so filenames, not the unavailable -lgcc_s symlink.
for lib in libm.so.6 libc.so.6 libgcc_s.so.1 ld-linux-mipsn8.so.1; do
  test -f "$SYSROOT/lib/$lib" || {
    echo "Missing Q2 runtime library: $SYSROOT/lib/$lib" >&2
    exit 1
  }
done
make -C "$CORE_SRC" -f Makefile.libretro -j"${JOBS:-2}" \
  platform=unix WANT_32BPP=0 HAVE_HDPACK=0 HAVE_NTSC=0 \
  CC="$Q2_CC" PLATFORM_DEFINES="-O2 -fPIC -D_GNU_SOURCE" \
  LD="ld.lld -m elf32ltsmip" LIBM= \
  SHARED="-shared --version-script=src/drivers/libretro/link.T --no-undefined --hash-style=sysv" \
  LDFLAGS="$SYSROOT/lib/libm.so.6 $SYSROOT/lib/libc.so.6 $SYSROOT/lib/libgcc_s.so.1 $SYSROOT/lib/ld-linux-mipsn8.so.1"
STAGE="$ROOT/dist/card"
rm -rf "$STAGE"
mkdir -p "$STAGE/.nes"
cp "$ROOT/package/.nes/q2app" "$STAGE/.nes/q2app"
cp "$CORE_SRC/fceumm_libretro.so" "$STAGE/.nes/fceumm_libretro.so"
sh "$ROOT/src/build.sh" "$STAGE/.nes/q2-nes"
python3 "$ROOT/tools/verify-package.py" "$STAGE/.nes"
(cd "$STAGE" && zip -q -r "$ROOT/dist/q2-nes.zip" .nes)
echo "Created $ROOT/dist/q2-nes.zip"
