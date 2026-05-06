## Quick Start

**Dependencies:**
- bash
- python3
- fwupd
- nvme-cli
- smartmontools
- ethtool
- dmidecode
 - mokutil
- tpm2-tools
 - chipsec

### Archlinux
```bash
sudo pacman -S --needed --noconfirm python3 fwupd nvme-cli smartmontools ethtool dmidecode mokutil tpm2-tools

# Build chipsec from source:
git clone https://github.com/chipsec/chipsec 
cd chipsec 
sudo python setup.py install 
```
### Debian/Ubuntu
```bash
sudo  apt  install -y debsums 
sudo  apt  install -y python3-pip python3-setuptools build-essential \ linux-headers-$(uname -r) 

# Build chipsec from source:

git clone https://github.com/chipsec/chipsec 
cd chipsec &&  
sudo python3 setup.py install
```

**Report:**
- Any modern browser (Chrome, Firefox, Safari, Edge)
- JavaScript enabled

### 1. Run the audit

```bash
chmod +x firmware-audit.sh
sudo ./firmware-audit.sh
```

### 2. Open the report

Double-click `firmware-audit-report.html` or open it in a browser.

### 3. Import JSON

In the report, click **Import JSON** in the bottom-right corner and select the generated file.
All fields are automatically filled in, status badges are set,
and checks with `warn`/`fail` are expanded for quick review.

---

## Status Heuristics

The script automatically assigns a status to each check:

| Status   | Meaning |
|----------|-----------|
| `pass`   | Command successful, output returns a positive signal (e.g., Secure Boot enabled, HSI ≥ 2) |
| `warn`   | Successful, but security status suboptimal (e.g., Secure Boot disabled, HSI ≤ 1) |
| `fail`   | Command failed (exit code ≠ 0) |


| `pending` | Status cannot be determined — set manually |

The tool itself (missing `tool_required`) results in a `warn` status with a note in the output.

In the HTML, you can change any status by clicking on the badge: `pending → pass → warn → fail → pending`.

---

## Self-Hosting

**No backend is required**. The HTML file is completely static and
uses browser-internal JavaScript.
```bash
xdg-open firmware-audit-report.html   # Linux
```
---

## Data Protection

The audit script sends **nothing** over the network. The HTML file is offline-capable
(only external resource: Google Fonts — switch to local fonts if needed,
see below).
