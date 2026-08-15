# Kali Panel Status Indicators (Xfce)

Lightweight status indicators for the Xfce panel that surface two things on a
Kali Linux system: how many package updates are pending, and whether a newer
Kali release is available.

Built for the Xfce **Generic Monitor** (`genmon`) plugin. Both scripts print
nothing when there is nothing to report, so the panel stays clean when the
system is up to date.

![Updates Notification](https://github.com/user-attachments/assets/9b606657-1d48-48eb-b2f0-c2bba2e48508)

## Repository layout

```
.
├── kali-themes/                     # the genmon scripts (source of truth)
│   ├── xfce4-panel-update.sh        #   pending package updates
│   └── xfce4-panel-upgrade.sh       #   newer Kali release available
├── setup.sh                         # install/uninstall + panel wiring
└── README.md
```

## Requirements

- **Kali Linux** (scripts refuse to run on other distributions).
- **Xfce panel** with the **`xfce4-genmon-plugin`** package installed — it
  ships with Kali's default Xfce panel, so nothing to install here (see
  *Other distributions* for installing it elsewhere).
- **`sudo`** access — the scripts are installed into
  `/usr/share/kali-themes/` (root-owned). `--load` / `--unload` modify only
  your own user configuration and need no privileges.

## Quick start

```bash
./setup.sh install --all --load
```

Installs both scripts (into `/usr/share/kali-themes/`, using `sudo`
automatically — it only prompts when privileges are actually needed), wires
both indicators to the end of the panel, disables the label, sets the period
to `86400.00 s` (24 h), and refreshes them immediately so their output is
visible at once. Repeated runs are safe: existing items are reused, never
duplicated.

## Other distributions (untested)

This project is written **for Kali Linux**, and **no other distribution has been
tested**. The two stock scripts only perform **Debian-family commands** (`apt`,
`sudo -n apt-get update`, `apt show`), and each one reads `/etc/os-release` and
exits silently unless `ID=kali` — so on any other distro they will either run
the wrong commands or stay blank on purpose. Using `setup.sh` elsewhere means
**editing the scripts manually** for your package manager and your distro's
`ID` (or adding your own genmon scripts to `kali-themes/`); the panel wiring
itself is plain Xfce `xfconf` and works as long as a `genmon` plugin exists.

- **Installing `xfce4-genmon-plugin` on another distro** — see
  [almaceleste's xfce4-genmon-scripts](https://almaceleste.github.io/xfce4-genmon-scripts/)
  (it covers installation and examples for several distributions).
- **Looking for more genmon scripts** — see
  [xtonousou/xfce4-genmon-scripts](https://github.com/xtonousou/xfce4-genmon-scripts).

On Kali the `genmon` plugin ships with the default Xfce panel, so no extra
package is required.

## Commands

| Command      | What it does                                                                 |
| ------------ | ---------------------------------------------------------------------------- |
| `install`    | Copies the selected script(s) from `kali-themes/` to `/usr/share/kali-themes/`, makes them executable (`chmod 755`) and applies the standard genmon settings where applicable. |
| `uninstall`  | Removes the selected script(s) from `/usr/share/kali-themes/`.               |
| `load`       | Wires genmon item(s) into the Xfce panel **only** — no file changes.         |
| `unload`     | Removes the matching genmon item(s) from the panel **only** — no file changes. |

### Options

| Option                   | Only valid with  | What it does                                                                 |
| ------------------------ | ---------------- | ---------------------------------------------------------------------------- |
| `--all`                  | any              | Select every script found in `kali-themes/` (this is the default).            |
| `--only <script>`        | any              | Select a single script by name, e.g. `--only xfce4-panel-update` (`<script>.sh` is also accepted). Available names are listed on mismatch. |
| `--target <path>`        | any              | Deploy to a different **full path** instead of `/usr/share/kali-themes/` (e.g. `--target ~/bin`). Genmon items on `load` then point at that path. Takes precedence over the `KALI_THEMES_INSTALL_DIR` env variable. |
| `--load`                 | `install`        | Shortcut for: install, then `load` as well.                                  |
| `--unload`               | `uninstall`      | Shortcut for: `unload` first, then uninstall.                                |

### Examples

```bash
# Install everything, without touching the panel
./setup.sh install --all

# Install just the updates indicator and add it to the panel
./setup.sh install --only xfce4-panel-update --load

# Remove the upgrades indicator from the panel, then delete the script
./setup.sh uninstall --only xfce4-panel-upgrade --unload

# Install both indicators and wire them into the panel
./setup.sh install --all --load

# Scripts already installed manually — just wire (or re-wire) the panel
./setup.sh load --all

# Unwire the panel without deleting the scripts
./setup.sh unload --only xfce4-panel-upgrade

# Install into your own directory (no sudo needed) instead of /usr/share
./setup.sh install --all --target ~/bin

# Point the panel at scripts deployed elsewhere
./setup.sh load --all --target ~/bin
```

## Scripts

### `xfce4-panel-update.sh` — pending updates

Refreshes the package cache with `sudo -n apt-get update` and counts the
upgradable packages. Prints the count only when it is greater than zero, e.g.:

```
⇡ 12 updates available
```

Requires passwordless `sudo` for `apt-get update` (see Troubleshooting).

### `xfce4-panel-upgrade.sh` — newer release available

Kali is a rolling release; the current version is read from
`/etc/os-release` (`VERSION_ID`) and the newest available release from the apt
package index (`kali-linux-core`). **No website is scraped.** When a newer
release exists it prints, e.g.:

```
Kali 2026.3.0 available (2026.1)
```

## Panel wiring and safety

`load` / `unload` (or the `--load` / `--unload` shortcuts) configure the
panel **live** through Xfce's own configuration system (`xfconf`, config
version 2) — the same mechanism the panel itself uses — so changes apply
immediately, no restart required:

1. **Backup** — the panel configuration (`xfce4-panel.xml`) is snapshotted
   before any change.
2. **Apply** — a genmon item is registered and appended to the end of the
   panel, configured with `use-label` disabled and a period of `86400.00 s`.
   Each installed script gets exactly one item; repeated installs are
   idempotent. An item is considered "already installed" when its command
   matches the exact path **or** the same script name whose installed copy is
   byte-identical (SHA-256) to the repo file — so switching `--target` paths,
   or re-loading after an interrupted unload, reuses the existing item instead
   of creating another one.
3. **Verify + rollback** — every change is checked (item present, label
   hidden, period correct). If anything fails, the changes are rolled back
   automatically and the panel is left untouched.
4. **Refresh** — freshly loaded items are forced to render immediately: the
   script tries a per-item refresh event and, if the panel ignores it, does a
   graceful panel restart so the output appears at once instead of waiting for
   the next period. Items removed from the panel by hand are re-created on the
   next `load`.

On panel configurations that are not `xfconf`-based (old config version 1),
`load`/`unload` refuse to touch anything, print a warning and leave the
scripts installed. Configure the items manually in that case (see below).

## Manual configuration (no `load`)

If you prefer to wire the indicators yourself:

1. Right-click the panel → **Panel → Panel Preferences → Items**.
2. **Add** a **Generic Monitor** for each script.
3. For each item:
   - **Command**: `/usr/share/kali-themes/<script>.sh`
   - uncheck **Label** (only the script output should be shown)
   - **Period(s)**: `86400` (24 hours; stored internally as `86400000` ms)
4. Close the preferences window.

## Advanced environment overrides

| Variable                   | Default                   | Purpose                                           |
| -------------------------- | ------------------------- | ------------------------------------------------- |
| `KALI_THEMES_INSTALL_DIR`  | `/usr/share/kali-themes/` | Where scripts are installed.                      |
| `XFCE_PANEL`               | auto-detected             | Panel to inject into, e.g. `panel-2`.             |
| `XFCONF_CHANNEL`           | `xfce4-panel`             | xfconf channel used by `load` / `unload`.         |

## Troubleshooting

- **Nothing ever shows in the panel.** Verify the script is installed and
  executable (`ls -l /usr/share/kali-themes/`) and that a genmon item in the
  panel points at it.
- **`sudo` password prompt / permission denied during `install`.**
  `/usr/share/kali-themes/` is root-owned. Run `setup.sh` with `sudo`, or
  install to your own directory with
  `KALI_THEMES_INSTALL_DIR=~/bin ./setup.sh install --all`.
- **Built with `sudo`, panel wiring was skipped.** Running `sudo ./setup.sh`
  is supported: the installer resolves the original user's configuration and
  session bus, so `load`/`unload` work through `sudo` too. If it still skips,
  the panel must use `xfconf` (config version 2) — for older Xfce versions,
  add the items manually.
- **Updates indicator refreshes but shows nothing.** Check the sudoers
  rule for apt: `/etc/sudoers.d/` must allow `apt-get update` (and only that)
  without a password.
- **Upgrade indicator shows nothing.** The apt package list has to contain
  `kali-linux-core` — run `sudo apt update` once. If the system is already on
  the newest release the indicator stays empty by design.
- **Duplicate indicators appeared in the panel.** Most likely leftover genmon
  items from an earlier install target path or an interrupted unload. Remove
  them all with `./setup.sh unload --all`, then `./setup.sh load --all` to
  rebuild. To remove by hand: **Panel → Panel Preferences → Items**, select
  each extra **Generic Monitor** and press **Remove**. `load` will not
  recreate them — it reuses items whose installed script is byte-identical,
  so duplicates of the repo scripts are not created again.
- **Trusting a stale panel backup.** Backups are kept alongside
  `xfce4-panel.xml` as `xfce4-panel.xml.bak-<timestamp>`. They are safe to
  delete once you are happy with a `load` / `--load`, and they are not used by the
  panel itself.

## License

Released under the [MIT License](LICENSE).