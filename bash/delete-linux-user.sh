#!/bin/bash

################################################################################
# Script Name: delete-linux-user.sh
# Description: Remove a Linux user using base-system tools only. Handles the
#              failure modes that survive a reboot: home-directory mount points
#              (data loss), name-based leftovers that a recreated user would
#              inherit, and files left owned by a reusable bare UID.
#              Transient state under /run and /tmp is left to the reboot.
# Author: MrJamesLZAZ
# Created: 2026-08-10
# Version: 2.1
################################################################################

set -uo pipefail

TOTAL=8
STEP=0

# Print a numbered step header. The counter self-increments so the numbers can
# never drift out of sync with the code below.
step() { STEP=$((STEP + 1)); echo; echo "[${STEP}/${TOTAL}] $*"; }

#===============================================================================
# Pre-flight (unnumbered: these only validate how the script was invoked)
#===============================================================================
U="${1:-}"
[ -n "$U" ] || { echo "Usage: $0 <username>"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "FAIL: must run as root (sudo)."; exit 1; }

#===============================================================================
# 1. Does the account exist? Read it from the passwd database, not `id`.
#===============================================================================
step "Looking up user '$U'"
PW=$(getent passwd "$U") || true
[ -n "$PW" ] || { echo "  FAIL: user '$U' not found in passwd database."; exit 1; }

UID_N=$(echo "$PW" | cut -d: -f3)
HOME_D=$(echo "$PW" | cut -d: -f6)
echo "  found: UID $UID_N, home ${HOME_D:-none}"

#===============================================================================
# 2. Refuse root and any account below the system's own human-UID threshold.
#===============================================================================
step "Checking the account is safe to delete"
UID_MIN=$(awk '/^[[:space:]]*UID_MIN/{print $2}' /etc/login.defs 2>/dev/null | tail -n1)
[ "$UID_N" -ge "${UID_MIN:-1000}" ] \
  || { echo "  FAIL: UID $UID_N is below UID_MIN ${UID_MIN:-1000} — system account. Refusing."; exit 1; }
echo "  OK: UID $UID_N is a normal user account (UID_MIN ${UID_MIN:-1000})"

#===============================================================================
# 3. Confirm interactively. Typing the name prevents deleting the wrong account.
#===============================================================================
step "Confirming"
printf "  Type the username '%s' to proceed: " "$U"
read -r a
[ "$a" = "$U" ] || { echo "  Aborted; nothing was changed."; exit 1; }

#===============================================================================
# 4. Mount points under the home directory. THE one data-loss risk: userdel -r
#    deletes recursively and would follow a mount into live data. Deepest first.
#===============================================================================
step "Unmounting any filesystem under $HOME_D"
findmnt -rno TARGET | awk -v h="$HOME_D" 'index($0,h"/")==1||$0==h' \
  | awk '{print length"\t"$0}' | sort -rn | cut -f2- | while read -r m; do
    umount "$m" 2>/dev/null && echo "  unmounted $m" \
      || { echo "  FAIL: cannot unmount $m"; exit 9; }
done || { echo "  Refusing to run 'userdel -r' with a filesystem still mounted there."; exit 1; }
echo "  OK: nothing left mounted under the home directory"

#===============================================================================
# 5. Processes: TERM, wait, then KILL. Match on UID — the name stops resolving
#    once the account is gone.
#===============================================================================
step "Terminating processes owned by UID $UID_N"
pkill -TERM -u "$UID_N" 2>/dev/null && sleep 3
pkill -KILL -u "$UID_N" 2>/dev/null
if pgrep -u "$UID_N" >/dev/null; then
  echo "  WARN: survived SIGKILL: $(pgrep -u "$UID_N" | tr '\n' ' ')"
else
  echo "  OK: no processes running as UID $UID_N"
fi

#===============================================================================
# 6. Name-based leftovers a recreated same-name user would silently inherit.
#===============================================================================
step "Removing name-based leftovers (sudo grant, cron spool)"
found=0
for f in "/etc/sudoers.d/$U" "/var/spool/cron/crontabs/$U" "/var/spool/cron/$U"; do
  [ -e "$f" ] || continue
  found=1
  rm -f "$f" && echo "  removed $f" || echo "  FAIL: could not remove $f"
done
[ "$found" -eq 0 ] && echo "  OK: none present"

#===============================================================================
# 7. The account itself. rc=12 means "account gone, home/mail cleanup partial".
#===============================================================================
step "Deleting the account, home directory and mail spool"
userdel --remove --force "$U"; rc=$?
case $rc in
  0)  echo "  OK: userdel removed account, home and mail spool" ;;
  12) echo "  WARN: account removed, but home/mail cleanup was incomplete (rc=12)" ;;
  *)  echo "  FAIL: userdel exited $rc"; exit 2 ;;
esac
if [ -n "$HOME_D" ] && [ -d "$HOME_D" ]; then
  rm -rf -- "$HOME_D" && echo "  removed leftover $HOME_D"
fi

#===============================================================================
# 8. Verify. Anything flagged below is real residue that outlives a reboot.
#===============================================================================
step "Verifying removal"

# 8a. Must no longer resolve. If it still does, it was never a local account.
if id "$U" >/dev/null 2>&1; then
  echo "  FAIL: '$U' still resolves — LDAP/SSSD account? userdel cannot remove it."
else
  echo "  OK: '$U' no longer resolves"
fi

# 8b. Name references in /etc — a recreated same-name user would inherit these.
refs=$(grep -rn "\b$U\b" /etc/passwd /etc/group /etc/sudoers /etc/sudoers.d/ 2>/dev/null)
if [ -n "$refs" ]; then
  echo "$refs" | sed 's/^/  LEFTOVER: /'
else
  echo "  OK: no name references in /etc"
fi

# 8c. Bare-UID files: harmless on their own, but the next new user gets this UID
#     and would inherit them. Reported, never auto-deleted — may be shared data.
echo "  scanning local filesystems for files owned by UID $UID_N ..."
orphans=$(findmnt -rno TARGET,FSTYPE \
  | awk '$2~/^(ext2|ext3|ext4|xfs|btrfs|f2fs|zfs|jfs|vfat|ntfs|exfat)$/{print $1}' \
  | while read -r r; do find "$r" -xdev -uid "$UID_N" -print 2>/dev/null; done)
if [ -n "$orphans" ]; then
  echo "$orphans" | sed 's/^/  ORPHAN: /'
else
  echo "  OK: no files left owned by UID $UID_N"
fi

echo
echo "=== Finished ${STEP}/${TOTAL} steps for '$U'. Review any FAIL/WARN/LEFTOVER/ORPHAN lines. ==="
