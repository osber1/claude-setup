cat > /tmp/haos-install.sh <<'HAOS_INSTALL'
#!/usr/bin/env bash
set -euo pipefail

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
trap 'echo "ERROR: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"
for c in xz dd lsblk wipefs blockdev cmp sha256sum; do
  command -v "$c" >/dev/null || die "missing tool: $c"
done
command -v curl >/dev/null || command -v wget >/dev/null || die "need curl or wget"
[[ -d /sys/firmware/efi ]] || warn "Live USB booted in legacy/BIOS mode. HAOS needs UEFI - enable it in BIOS before booting HAOS."

LIVE_DISK=""
for mp in /cdrom /run/live/medium /isodevice; do
  src=$(findmnt -no SOURCE "$mp" 2>/dev/null || true)
  if [[ -n $src ]]; then
    LIVE_DISK=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)
    break
  fi
done

DISKS=()
while read -r name type tran; do
  [[ $type == disk ]] || continue
  [[ $name == zram* || $name == "$LIVE_DISK" || $tran == usb ]] && continue
  DISKS+=("/dev/$name")
done < <(lsblk -dnro NAME,TYPE,TRAN)
(( ${#DISKS[@]} > 0 )) || die "No internal disks found"

echo "Disks that will be WIPED:"
for d in "${DISKS[@]}"; do lsblk -dno NAME,SIZE,MODEL,TRAN "$d"; done
echo "(USB drives are left untouched)"
echo

TARGET="${1:-${TARGET:-}}"
if [[ -z $TARGET ]]; then
  if (( ${#DISKS[@]} == 1 )); then
    TARGET=${DISKS[0]}
  else
    read -rp "Install HAOS on which disk (e.g. sda or nvme0n1): " name
    TARGET="/dev/${name#/dev/}"
  fi
fi
printf '%s\n' "${DISKS[@]}" | grep -qx "$TARGET" || die "$TARGET is not one of the disks listed above"
echo "HAOS will be installed on: $TARGET"
echo
echo "ALL DATA ON ${DISKS[*]} WILL BE DESTROYED."
read -rp "Type WIPE to confirm: " confirm
[[ $confirm == WIPE ]] || die "Aborted."

echo "==> Finding latest HAOS release"
REPO=https://github.com/home-assistant/operating-system
if command -v curl >/dev/null; then
  fetch()  { curl -fsSL "$1" </dev/null; }
  latest() { curl -fsSLI -o /dev/null -w '%{url_effective}' "$REPO/releases/latest" </dev/null; }
  dl()     { curl -fL --progress-bar -o "$2" "$1" </dev/null; }
else
  fetch()  { wget -qO- "$1" </dev/null; }
  latest() { wget -S --spider "$REPO/releases/latest" 2>&1 </dev/null | awk '/^ *[Ll]ocation: /{u=$2} END{print u}'; }
  dl()     { wget -O "$2" "$1" </dev/null; }
fi
VER=$(latest | tr -d '\r' | sed -n 's#.*/releases/tag/##p' || true)
[[ $VER =~ ^[0-9]+\.[0-9]+$ ]] || die "Could not determine latest version (got '$VER')"
IMG="haos_generic-x86-64-${VER}.img.xz"
URL="$REPO/releases/download/${VER}/${IMG}"
echo "    Version: $VER"

SHA=""
if command -v python3 >/dev/null; then
  SHA=$(fetch "https://api.github.com/repos/home-assistant/operating-system/releases/tags/${VER}" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for a in d.get("assets",[]):
    if a["name"]==sys.argv[1]:
        print((a.get("digest") or "").removeprefix("sha256:")); break
' "$IMG" || true)
fi

WORKDIR=/tmp/haos
mkdir -p "$WORKDIR"
if [[ ! -f $WORKDIR/$IMG ]]; then
  echo "==> Downloading $URL"
  dl "$URL" "$WORKDIR/$IMG.part" || die "Download failed: $URL"
  mv "$WORKDIR/$IMG.part" "$WORKDIR/$IMG"
fi

echo "==> Verifying download"
if [[ -n $SHA ]]; then
  echo "$SHA  $WORKDIR/$IMG" | sha256sum -c --quiet - || { rm -f "$WORKDIR/$IMG"; die "Checksum mismatch, deleted. Re-run."; }
else
  warn "No published checksum found, checking archive integrity only"
fi
xz -t "$WORKDIR/$IMG" || { rm -f "$WORKDIR/$IMG"; die "Archive corrupt, deleted. Re-run."; }
IMG_BYTES=$(xz --robot -l "$WORKDIR/$IMG" | awk '$1=="totals"{print $5}')
(( IMG_BYTES <= $(blockdev --getsize64 "$TARGET") )) || die "$TARGET is too small for the image"

echo "==> Releasing disks"
for d in "${DISKS[@]}"; do
  for p in $(lsblk -lnpo NAME "$d" | tac); do
    umount -lf "$p" 2>/dev/null || true
    swapoff "$p" 2>/dev/null || true
  done
done
command -v vgchange >/dev/null && vgchange -an >/dev/null 2>&1 || true
for _ in 1 2 3; do
  for d in "${DISKS[@]}"; do
    for dm in $(lsblk -lnpo NAME,TYPE "$d" | awk '$2!="disk" && $2!="part"{print $1}' | tac); do
      dmsetup remove -f "$dm" >/dev/null 2>&1 || true
    done
  done
done
command -v mdadm >/dev/null && mdadm --stop --scan >/dev/null 2>&1 || true
command -v zpool >/dev/null && zpool export -af >/dev/null 2>&1 || true
for d in "${DISKS[@]}"; do
  if lsblk -lnpo TYPE "$d" | grep -qvE '^(disk|part)$'; then
    warn "Old mappings still active on $d. Continuing - the wipe still writes and a reboot clears them."
  fi
done

for d in "${DISKS[@]}"; do
  echo "==> Wiping $d"
  for p in $(lsblk -lnpo NAME,TYPE "$d" | awk '$2=="part"{print $1}'); do
    wipefs -af "$p" >/dev/null 2>&1 || true
  done
  wipefs -af "$d" >/dev/null 2>&1 || true
  sectors=$(blockdev --getsz "$d")
  dd if=/dev/zero of="$d" bs=1M count=16 conv=fsync status=none
  dd if=/dev/zero of="$d" bs=512 count=32768 seek=$((sectors - 32768)) conv=fsync status=none
  if command -v blkdiscard >/dev/null && [[ $(lsblk -dno DISC-GRAN "$d" | tr -d ' ') != 0B ]]; then
    blkdiscard -f "$d" >/dev/null 2>&1 || true
  fi
done

echo "==> Writing HAOS $VER to $TARGET"
xz -dc "$WORKDIR/$IMG" | dd of="$TARGET" bs=4M iflag=fullblock oflag=direct status=progress conv=fsync
sync

echo "==> Verifying written image"
echo 3 > /proc/sys/vm/drop_caches
xz -dc "$WORKDIR/$IMG" | cmp -n "$IMG_BYTES" - "$TARGET" || die "Verification FAILED - disk contents differ from image"
for d in "${DISKS[@]}"; do partprobe "$d" 2>/dev/null || true; done

echo
echo "Done. Wiped: ${DISKS[*]}"
echo "HAOS $VER written and verified on $TARGET."
echo "Next: reboot, remove the USB, boot in UEFI mode with Secure Boot off."
echo "Then open http://homeassistant.local (or http://<ip>) - new installs use port 80."
HAOS_INSTALL
sudo bash /tmp/haos-install.sh
