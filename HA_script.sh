sudo bash <<'HAOS_INSTALL'
# Wipes ALL internal disks (USB drives untouched) and installs the latest
# Home Assistant OS (generic-x86-64). Paste the whole block into a terminal
# on an Ubuntu live USB with internet.
set -euo pipefail

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

[[ $EUID -eq 0 ]] || die "Run as root"
for c in wget xz dd lsblk wipefs blockdev cmp sha256sum; do
  command -v "$c" >/dev/null || die "missing tool: $c"
done
[[ -d /sys/firmware/efi ]] || warn "Live USB booted in legacy/BIOS mode. HAOS needs UEFI - enable it in BIOS before booting HAOS."

# --- Disks to wipe: every whole disk except USB-attached ones (the live stick) and zram ---
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

# --- Pick the disk HAOS goes on ---
TARGET="${TARGET:-}"
if [[ -z $TARGET ]]; then
  if (( ${#DISKS[@]} == 1 )); then
    TARGET=${DISKS[0]}
  else
    read -rp "Install HAOS on which disk (e.g. sda or nvme0n1): " name </dev/tty
    TARGET="/dev/${name#/dev/}"
  fi
fi
printf '%s\n' "${DISKS[@]}" | grep -qx "$TARGET" || die "$TARGET is not one of the disks listed above"
echo "HAOS will be installed on: $TARGET"
echo
echo "ALL DATA ON ${DISKS[*]} WILL BE DESTROYED."
read -rp "Type WIPE to confirm: " confirm </dev/tty
[[ $confirm == WIPE ]] || die "Aborted."

# --- Download latest stable HAOS ---
echo "==> Finding latest HAOS release"
API_JSON=$(wget -qO- https://api.github.com/repos/home-assistant/operating-system/releases/latest) \
  || die "Could not reach GitHub (network?)"
VER=$(grep -Po '"tag_name":\s*"\K[^"]+' <<<"$API_JSON" | head -n1)
[[ -n $VER ]] || die "Could not parse latest version"
IMG="haos_generic-x86-64-${VER}.img.xz"
echo "    Version: $VER"

SHA=""
if command -v python3 >/dev/null; then
  SHA=$(python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
for a in d.get("assets",[]):
    if a["name"]==sys.argv[1]:
        print((a.get("digest") or "").removeprefix("sha256:")); break
' "$IMG" <<<"$API_JSON" || true)
fi

WORKDIR=/tmp/haos
mkdir -p "$WORKDIR"
if [[ ! -f $WORKDIR/$IMG ]]; then
  wget -q --show-progress -O "$WORKDIR/$IMG.part" \
    "https://github.com/home-assistant/operating-system/releases/download/${VER}/${IMG}"
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

# --- Release everything on those disks (Proxmox LVM, swap, RAID, ZFS, mounts) ---
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

# --- Wipe every disk (signatures + start and end of disk) ---
for d in "${DISKS[@]}"; do
  echo "==> Wiping $d"
  for p in $(lsblk -lnpo NAME,TYPE "$d" | awk '$2=="part"{print $1}'); do
    wipefs -af "$p" >/dev/null 2>&1 || true
  done
  wipefs -af "$d" >/dev/null 2>&1 || true
  sectors=$(blockdev --getsz "$d")   # 512-byte sectors
  dd if=/dev/zero of="$d" bs=1M count=16 conv=fsync status=none
  dd if=/dev/zero of="$d" bs=512 count=32768 seek=$((sectors - 32768)) conv=fsync status=none
  if command -v blkdiscard >/dev/null && [[ $(lsblk -dno DISC-GRAN "$d" | tr -d ' ') != 0B ]]; then
    blkdiscard -f "$d" >/dev/null 2>&1 || true   # SSD/NVMe: discard all old data
  fi
done

# --- Write HAOS ---
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
echo "Ignore ':8123' if the HAOS console banner shows it."
HAOS_INSTALL
