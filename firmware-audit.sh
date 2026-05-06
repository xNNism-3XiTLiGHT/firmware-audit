#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
#  firmware-audit.sh
#  Linux Hardware Firmware Integrity Audit
#  Generates JSON compatible with firmware-audit-report.html
# ─────────────────────────────────────────────────────────────────────────

set -u

# ── Config ─────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOSTNAME_=$(hostname 2>/dev/null || echo "unknown")
OUTPUT="firmware-audit-${HOSTNAME_}-${TIMESTAMP}.json"
TMPFILE=$(mktemp /tmp/fw-audit.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

# ── Colors ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; CYAN=""; DIM=""; BOLD=""; NC=""
fi

# ── Dependency check ───────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required for JSON generation." >&2
  exit 1
fi

# ── Banner ─────────────────────────────────────────────────────────────
echo "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║${NC}   ${BOLD}FIRMWARE INTEGRITY AUDIT${NC}                                  ${CYAN}║${NC}"
echo "${CYAN}║${NC}   $(date '+%Y-%m-%d %H:%M:%S')  ·  Host: ${HOSTNAME_}$(printf '%*s' $((30 - ${#HOSTNAME_})) '')${CYAN}║${NC}"
echo "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ $EUID -ne 0 ]]; then
  echo "${YELLOW}⚠  Some checks need root privileges. Run with sudo for complete results.${NC}"
  echo ""
fi

# ── Helper: collect metadata ───────────────────────────────────────────
META_HOSTNAME="$HOSTNAME_"
META_DISTRO=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "unknown")
META_KERNEL=$(uname -r 2>/dev/null || echo "unknown")
META_AUDITOR="${SUDO_USER:-$(whoami)}"

# ── Recording functions ────────────────────────────────────────────────
record_field() {
  printf '%s\037%s\n' "$1" "$2" >> "$TMPFILE"
}

record_check() {
  local section="$1" check_title="$2" cmd="$3" output="$4" exit_code="$5" status="$6"
  printf '\036CHECK\036\n' >> "$TMPFILE"
  record_field SECTION "$section"
  record_field TITLE "$check_title"
  record_field COMMAND "$cmd"
  record_field STATUS "$status"
  record_field EXIT "$exit_code"
  printf '\036OUTPUT_START\036\n' >> "$TMPFILE"
  printf '%s\n' "$output" >> "$TMPFILE"
  printf '\036OUTPUT_END\036\n' >> "$TMPFILE"
}

# ── Status detection heuristics ────────────────────────────────────────
detect_status() {
  local title="$1" output="$2" exit_code="$3"
  local lower="${output,,}"

  case "$title" in
    *"Secure Boot Status"*)
      [[ "$lower" == *"secureboot enabled"* ]] && { echo "pass"; return; }
      [[ "$lower" == *"secureboot disabled"* ]] && { echo "warn"; return; }
      ;;
    *"Module Signature"*)
      [[ "$output" =~ ^Y[[:space:]]*$ ]] && { echo "pass"; return; }
      [[ "$output" =~ ^N[[:space:]]*$ ]] && { echo "warn"; return; }
      ;;
    *"Lockdown"*)
      [[ "$output" == *"[integrity]"* || "$output" == *"[confidentiality]"* ]] && { echo "pass"; return; }
      [[ "$output" == *"[none]"* ]] && { echo "warn"; return; }
      ;;
    *"HSI"*|*"Host Security"*)
      [[ "$output" =~ HSI:[2-4] ]] && { echo "pass"; return; }
      [[ "$output" =~ HSI:[01] ]] && { echo "warn"; return; }
      ;;
    *"linux-firmware Paket-Integrität"*)
      [[ -z "$output" || "$output" == *"OK"* ]] && { echo "pass"; return; }
      ;;
    *"Eingetragene"*|*"enrolled"*)
      [[ -n "$output" && "$exit_code" -eq 0 ]] && { echo "pass"; return; }
      ;;
  esac

  if [[ "$exit_code" -eq 127 ]]; then
    echo "warn"
  elif [[ "$exit_code" -ne 0 ]]; then
    echo "fail"
  elif [[ -z "$output" ]]; then
    echo "warn"
  else
    echo "pass"
  fi
}

# ── Main check runner ──────────────────────────────────────────────────
do_check() {
  local section="$1" title="$2" cmd="$3" required_tool="${4:-}"

  printf "${DIM}[%s]${NC} %s\n" "$section" "$title"
  printf "    ${DIM}\$ %s${NC}\n" "$cmd"

  if [[ -n "$required_tool" ]] && ! command -v "$required_tool" >/dev/null 2>&1; then
    local msg="Tool '$required_tool' is not installed — check skipped."
    record_check "$section" "$title" "$cmd" "$msg" "127" "warn"
    printf "    ${YELLOW}⊘ SKIPPED${NC}  (missing: %s)\n\n" "$required_tool"
    return
  fi

  local output exit_code status
  output=$(eval "$cmd" 2>&1)
  exit_code=$?
  status=$(detect_status "$title" "$output" "$exit_code")

  record_check "$section" "$title" "$cmd" "$output" "$exit_code" "$status"

  case "$status" in
    pass)    printf "    ${GREEN}✓ PASS${NC}\n\n" ;;
    warn)    printf "    ${YELLOW}⚠ WARN${NC}\n\n" ;;
    fail)    printf "    ${RED}✗ FAIL${NC} (exit %s)\n\n" "$exit_code" ;;
    pending) printf "    ${DIM}· pending${NC}\n\n" ;;
  esac
}

# ╔══════════════════════════════════════════════════════════════════════╗
# ║                       AUDIT SECTIONS                                  ║
# ╚══════════════════════════════════════════════════════════════════════╝

echo "${BOLD}§ 01  Platform & fwupd${NC}"
echo "${DIM}────────────────────────────────────────────────${NC}"
do_check "01" "Host Security ID (HSI)"            "fwupdmgr security"     "fwupdmgr"
do_check "01" "Geräte mit signierter Firmware-Quelle" "fwupdmgr get-devices"  "fwupdmgr"
do_check "01" "Verfügbare signierte Updates"      "fwupdmgr get-updates"  "fwupdmgr"
do_check "01" "Update-Historie"                   "fwupdmgr get-history"  "fwupdmgr"

echo "${BOLD}§ 02  Storage · SSD / NVMe${NC}"
echo "${DIM}────────────────────────────────────────────────${NC}"
do_check "02" "NVMe-Geräteliste"        "nvme list"           "nvme"
# Try to discover all NVMe devices and run fw-log per device
NVME_DEVICES=$(ls /dev/nvme[0-9]* 2>/dev/null | grep -E '/nvme[0-9]+$' || true)
if [[ -n "$NVME_DEVICES" ]] && command -v nvme >/dev/null 2>&1; then
  for dev in $NVME_DEVICES; do
    do_check "02" "NVMe Firmware-Slots ($dev)" "nvme fw-log $dev" "nvme"
  done
else
  do_check "02" "NVMe Firmware-Slots" "nvme fw-log /dev/nvme0" "nvme"
fi
# SATA devices
SATA_DEVICES=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1 ~ /^sd/ {print "/dev/"$1}' || true)
if [[ -n "$SATA_DEVICES" ]] && command -v smartctl >/dev/null 2>&1; then
  for dev in $SATA_DEVICES; do
    do_check "02" "SATA Identität ($dev)" "smartctl -i $dev" "smartctl"
  done
else
  do_check "02" "SATA-Datenträger Identität" "smartctl -i /dev/sda" "smartctl"
fi

echo "${BOLD}§ 03  Network Interfaces${NC}"
echo "${DIM}────────────────────────────────────────────────${NC}"
NICS=$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' || true)
if [[ -n "$NICS" ]] && command -v ethtool >/dev/null 2>&1; then
  for iface in $NICS; do
    do_check "03" "NIC Firmware ($iface)" "ethtool -i $iface" "ethtool"
  done
else
  do_check "03" "NIC Firmware-Version" "ethtool -i eth0" "ethtool"
fi
do_check "03" "Geladene Firmware-Blobs (Kernel-Log)" "dmesg | grep -i firmware | head -50"
if command -v debsums >/dev/null 2>&1; then
  do_check "03" "linux-firmware Paket-Integrität" "debsums linux-firmware 2>&1 | grep -v 'OK$' || echo 'All firmware files OK'" "debsums"
elif command -v rpm >/dev/null 2>&1; then
  do_check "03" "linux-firmware Paket-Integrität" "rpm -V linux-firmware 2>&1 || echo 'All firmware files OK'" "rpm"
else
  do_check "03" "linux-firmware Paket-Integrität" "echo 'No package verification tool found (debsums/rpm)'"
fi

echo "${BOLD}§ 04  UEFI / BIOS${NC}"
echo "${DIM}────────────────────────────────────────────────${NC}"
do_check "04" "BIOS/UEFI Identifikation" "dmidecode -t bios" "dmidecode"
do_check "04" "Secure Boot Status"       "mokutil --sb-state" "mokutil"
do_check "04" "Eingetragene Secure-Boot-Schlüssel" "mokutil --list-enrolled 2>&1 | head -100" "mokutil"

echo "${BOLD}§ 05  Kernel & Modules${NC}"
echo "${DIM}────────────────────────────────────────────────${NC}"
do_check "05" "Module Signature Enforcement" "cat /sys/module/module/parameters/sig_enforce 2>/dev/null || echo 'not available'"
do_check "05" "Kernel Lockdown Mode" "cat /sys/kernel/security/lockdown 2>/dev/null || echo 'not available'"
if command -v tpm2_getcap >/dev/null 2>&1; then
  do_check "05" "TPM Status" "tpm2_getcap properties-fixed 2>&1 | head -30" "tpm2_getcap"
elif [[ -d /sys/class/tpm/tpm0 ]]; then
  do_check "05" "TPM Status" "ls /sys/class/tpm/tpm0/ && cat /sys/class/tpm/tpm0/tpm_version_major 2>/dev/null"
else
  do_check "05" "TPM Status" "echo 'No TPM detected'"
fi

echo "${BOLD}§ 06  Deep Audit · CHIPSEC  ${DIM}(optional)${NC}"
echo "${DIM}────────────────────────────────────────────────${NC}"
if command -v chipsec_main >/dev/null 2>&1; then
  do_check "06" "CHIPSEC Vollanalyse" "chipsec_main 2>&1 | tail -100" "chipsec_main"
  do_check "06" "Secure Boot Variablen" "chipsec_main -m common.secureboot.variables 2>&1 | tail -50" "chipsec_main"
else
  do_check "06" "CHIPSEC Vollanalyse" "echo 'chipsec not installed - see https://github.com/chipsec/chipsec'"
  do_check "06" "Secure Boot Variablen" "echo 'chipsec not installed'"
fi

# ╔══════════════════════════════════════════════════════════════════════╗
# ║                       JSON GENERATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════╝

echo ""
echo "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo "${CYAN} Generating JSON report…${NC}"
echo "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

python3 <<PYEOF > "$OUTPUT"
import json, datetime, os, sys

REPORT_ID    = "FW-AUDIT-${TIMESTAMP}"
GENERATED    = "$(date '+%Y-%m-%d %H:%M:%S')"
META = {
    "Hostname":     "${META_HOSTNAME}",
    "Distribution": "${META_DISTRO}",
    "Kernel":       "${META_KERNEL}",
    "Auditor":      "${META_AUDITOR}",
}

SECTION_TITLES = {
    "01": "Platform & fwupd",
    "02": "Storage · SSD / NVMe",
    "03": "Network Interfaces",
    "04": "UEFI / BIOS",
    "05": "Kernel & Modules",
    "06": "Deep Audit · CHIPSEC",
}

# Parse the temp file
checks = []
with open("$TMPFILE", "r", encoding="utf-8", errors="replace") as f:
    raw = f.read()

# Split by check marker
parts = raw.split("\x1eCHECK\x1e\n")
for part in parts[1:]:  # skip empty first
    cur = {"section": "", "title": "", "command": "",
           "status": "pending", "exit_code": 0, "output": ""}
    in_output = False
    output_lines = []
    for line in part.split("\n"):
        if line == "\x1eOUTPUT_START\x1e":
            in_output = True
            continue
        if line == "\x1eOUTPUT_END\x1e":
            in_output = False
            continue
        if in_output:
            output_lines.append(line)
        elif "\x1f" in line:
            k, v = line.split("\x1f", 1)
            if   k == "SECTION": cur["section"] = v
            elif k == "TITLE":   cur["title"]   = v
            elif k == "COMMAND": cur["command"] = v
            elif k == "STATUS":  cur["status"]  = v
            elif k == "EXIT":
                try:    cur["exit_code"] = int(v)
                except: cur["exit_code"] = 0
    cur["output"] = "\n".join(output_lines).rstrip()
    cur["notes"]  = ""
    checks.append(cur)

# Group by section
sections_map = {}
for c in checks:
    sections_map.setdefault(c["section"], []).append(c)

sections = []
for sid in sorted(sections_map.keys()):
    sections.append({
        "id":     sid,
        "title":  SECTION_TITLES.get(sid, sid),
        "checks": sections_map[sid],
    })

# Summary
counts = {"pass": 0, "warn": 0, "fail": 0, "pending": 0}
for c in checks:
    counts[c["status"]] = counts.get(c["status"], 0) + 1

report = {
    "report_id": REPORT_ID,
    "generated": GENERATED,
    "meta":      META,
    "summary":   counts,
    "sections":  sections,
}

print(json.dumps(report, indent=2, ensure_ascii=False))
PYEOF

# ── Final summary ──────────────────────────────────────────────────────
PASS_COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(d['summary'].get('pass',0))")
WARN_COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(d['summary'].get('warn',0))")
FAIL_COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(d['summary'].get('fail',0))")
PEND_COUNT=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(d['summary'].get('pending',0))")

echo ""
echo "${BOLD}Summary${NC}"
echo "  ${GREEN}✓ Pass${NC}    : $PASS_COUNT"
echo "  ${YELLOW}⚠ Warn${NC}    : $WARN_COUNT"
echo "  ${RED}✗ Fail${NC}    : $FAIL_COUNT"
echo "  ${DIM}· Pending${NC} : $PEND_COUNT"
echo ""
echo "${GREEN}✓ Report written to:${NC} ${BOLD}$OUTPUT${NC}"
echo ""
echo "  Import via 'Import JSON' button in firmware-audit-report.html"
echo ""
