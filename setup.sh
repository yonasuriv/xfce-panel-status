#!/usr/bin/env bash
#
# setup.sh — install / uninstall the Kali panel-status scripts and, optionally,
# wire them into the running Xfce panel as genmon (Generic Monitor) items.
#
# Usage:
#   setup.sh install     [--all | --only <script> ...] [--target <path>] [--load]
#   setup.sh uninstall   [--all | --only <script> ...] [--target <path>] [--unload]
#   setup.sh load        [--all | --only <script> ...] [--target <path>]
#   setup.sh unload      [--all | --only <script> ...] [--target <path>]
#   setup.sh help
#
#   install    copies the selected script(s) from ./kali-themes to the install
#              directory, makes them executable (chmod 755) and, for every
#              matching genmon plugin, disables the label and sets the refresh
#              period to 86400.00 s (24 h).
#   uninstall  removes the selected script(s) from the install directory.
#   load       wires genmon item(s) into the Xfce panel only (no file changes).
#   unload     removes the matching genmon item(s) from the panel only
#              (no file changes).
#   --all      select every script found in ./kali-themes (the default).
#   --only     select a single script (name with or without the .sh suffix).
#   --target   deploy into the given full (absolute) path instead of the
#              default /usr/share/kali-themes.  Takes precedence over the
#              KALI_THEMES_INSTALL_DIR environment variable.  Load/unload use
#              it as the genmon command path too.
#   --load     convenience: as install, but also wire items into the panel.
#   --unload   convenience: as uninstall, but also remove items from the panel.
#
# The panel is never left in a broken state: changes are verified and rolled
# back on failure.  Environment overrides (advanced):
#   KALI_THEMES_INSTALL_DIR  target directory (default: /usr/share/kali-themes)
#   XFCE_PANEL               panel to inject into, e.g. "panel-1" (default: auto)
#   XFCONF_CHANNEL           xfconf channel to operate on (default: xfce4-panel)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_SRC="${REPO_DIR}/kali-themes"
INSTALL_DIR="${KALI_THEMES_INSTALL_DIR:-/usr/share/kali-themes}"

# genmon stores its refresh period in milliseconds:
# 86400000 ms = 86400.00 s = 24 h.
GENMON_PERIOD_MS=86400000

# The panel configuration belongs to the invoking user, even when this script
# is executed through `sudo`.  Resolve that user and their home so the panel
# layer always operates on the right configuration and session bus.
owner_user() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}

owner_home() {
  local u; u="$(owner_user)"
  if [[ "$u" == "$(id -un)" ]]; then
    echo "$HOME"
  else
    getent passwd "$u" | cut -d: -f6
  fi
}

XFCONF_CHANNEL="${XFCONF_CHANNEL:-xfce4-panel}"
XFCONF_DIR="$(owner_home)/.config/xfce4/xfconf/xfce-perchannel-xml"
XFCONF_FILE="$XFCONF_DIR/$XFCONF_CHANNEL.xml"

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------

RED='' GREEN='' YELLOW='' NC=''
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'
fi

info() { printf '%s\n' "${GREEN}[*]${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%s\n' "${RED}[x]${NC} $*" >&2; exit 1; }

usage() {
  awk 'NR == 1 { next } /^#/{ sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# xfconf helpers (configver 2, property / array access)
# ---------------------------------------------------------------------------

# Run xfconf-query as the user who owns the panel.  When this script runs via
# `sudo`, xfconf-query is re-executed as the invoking user with their session
# bus, so writes reach the running panel instead of a root-leased one.
xconf() {
  local u uid
  u="$(owner_user)"
  if [[ "$u" != "$(id -un)" ]]; then
    uid="$(id -u "$u")"
    if [[ -S "/run/user/$uid/bus" ]]; then
      sudo -u "$u" -H XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" xfconf-query "$@"
    else
      warn "No session bus for user '$u' at /run/user/$uid/bus — panel skipped"
      return 1
    fi
  else
    xfconf-query "$@"
  fi
}

xget()      { xconf -c "$XFCONF_CHANNEL" -p "$1" 2>/dev/null || true; }

xget_arr()  {
  xconf -c "$XFCONF_CHANNEL" -p "$1" 2>/dev/null \
    | sed '1,2d' | grep -v '^[[:space:]]*$' || true
}

xset() { # property type value
  xconf -c "$XFCONF_CHANNEL" -p "$1" -t "$2" -s "$3" -n >/dev/null 2>&1 \
    || xconf -c "$XFCONF_CHANNEL" -p "$1" -t "$2" -s "$3" >/dev/null 2>&1 \
    || return 1
}

xset_arr() { # property v1 v2 ...
  local prop="$1"; shift
  (( $# > 0 )) || return 0
  local -a args=(-c "$XFCONF_CHANNEL" -p "$prop")
  local v
  for v in "$@"; do args+=(-t int -s "$v"); done
  [[ -z "$(xget "$prop")" ]] && args+=(-n)
  xconf "${args[@]}" >/dev/null 2>&1
}

# Reset a property subtree recursively.  A single reset is not enough: the
# running panel can rewrite the plugin's own properties (e.g. `command`)
# during widget teardown, racing the reset.  Retry until the subtree is truly
# empty, so no stale values survive an unload.
xreset() {
  local p="$1" attempt
  for attempt in 1 2 3; do
    xconf -c "$XFCONF_CHANNEL" -p "$p" -r -R >/dev/null 2>&1 || true
    [[ -z "$(xget "$p")" && -z "$(xget "$p/command")" ]] && return 0
    sleep 0.25
  done
  warn "Could not fully reset $p"
  return 1
}

# ---------------------------------------------------------------------------
# selection of scripts (auto-read from ./kali-themes)
# ---------------------------------------------------------------------------

resolve_selection() {
  if [[ "${MODE:-}" == "only" ]]; then
    local names=() nb avail
    for n in "${SELECTED[@]}"; do
      nb="$(basename "$n")"
      [[ "$nb" != *.sh ]] && nb="$nb.sh"
      if [[ ! -f "$SCRIPTS_SRC/$nb" ]]; then
        avail="$(cd "$SCRIPTS_SRC" 2>/dev/null && printf '%s\n' *.sh | sed 's/\.sh$//')"
        die "Script not found in $SCRIPTS_SRC: '$nb' (available: ${avail//$'\n'/, })"
      fi
      names+=("$nb")
    done
    SELECTED=("${names[@]}")
  else
    local f
    for f in "$SCRIPTS_SRC"/*.sh; do
      [[ -f "$f" ]] && SELECTED+=("$(basename "$f")")
    done
    ((${#SELECTED[@]})) || die "No scripts found in $SCRIPTS_SRC"
  fi
}

# ---------------------------------------------------------------------------
# file installation (respects sudo only when required)
# ---------------------------------------------------------------------------

needs_sudo() {
  [[ "$(id -u)" -eq 0 ]] && return 1
  if [[ -d "$INSTALL_DIR" ]]; then
    [[ -w "$INSTALL_DIR" ]] && return 1
  else
    [[ -w "$(dirname "$INSTALL_DIR")" ]] && return 1
  fi
  return 0
}

run_priv() { if needs_sudo; then sudo "$@"; else "$@"; fi; }

install_scripts() {
  local f
  run_priv mkdir -p "$INSTALL_DIR" || die "Cannot create $INSTALL_DIR"
  for f in "$@"; do
    run_priv install -m 755 "$SCRIPTS_SRC/$f" "$INSTALL_DIR/$f" \
      || die "Failed to install $f"
    info "Installed $f -> $INSTALL_DIR/$f (mode 755)"

    # apply the standard genmon settings to any plugin already using this script
    local id; id="$(plugin_for_script "$INSTALL_DIR/$f" "$SCRIPTS_SRC/$f")" || true
    if [[ -n "$id" ]]; then
      configure_genmon_plugin "$id" "$INSTALL_DIR/$f" \
        || warn "Could not update settings of existing genmon plugin $id"
      info "Configured existing genmon plugin $id (label off, period 86400.00 s)"
    fi
  done
}

uninstall_scripts() {
  local f
  for f in "$@"; do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
      run_priv rm -f "$INSTALL_DIR/$f" || die "Failed to remove $INSTALL_DIR/$f"
      info "Removed $INSTALL_DIR/$f"
    else
      warn "$f is not installed ($INSTALL_DIR/$f missing)"
    fi
  done
}

# ---------------------------------------------------------------------------
# panel wiring (genmon items via xfconf, configver 2)
# ---------------------------------------------------------------------------

all_plugin_ids() {
  local p
  for p in $(xget_arr "/panels" | sed 's/^panel-//'); do
    xget_arr "/panels/panel-$p/plugin-ids"
  done | sort -un
}

choose_panel() {
  [[ -n "${XFCE_PANEL:-}" ]] && { echo "$XFCE_PANEL"; return 0; }
  local p pid name
  for p in $(xget_arr "/panels" | sed 's/^panel-//'); do
    for pid in $(xget_arr "/panels/panel-$p/plugin-ids"); do
      name="$(xget "/plugins/plugin-$pid")"
      [[ "$name" == "genmon" ]] && { echo "panel-$p"; return 0; }
    done
  done
  echo "panel-$(xget_arr '/panels' | sed 's/^panel-//' | head -n 1)"
}

panel_compatible() {
  command -v xfconf-query >/dev/null 2>&1        || return 1
  [[ -f "$XFCONF_FILE" ]]                        || return 1
  [[ "$(xget /configver)" == "2" ]]              || return 1
  [[ -n "$(choose_panel 2>/dev/null)" ]]         || return 1
  return 0
}

plugin_for_script() { # command path [script source path] -> plugin id
  local cmdpath="$1" srcpath="$2" id name item base srchash itemhash
  base="$(basename "$cmdpath")"
  srchash="$(script_hash "$srcpath")"
  for id in $(all_plugin_ids); do
    name="$(xget "/plugins/plugin-$id")"
    [[ "$name" == "genmon" ]] || continue
    item="$(xget "/plugins/plugin-$id/command")"
    [[ -n "$item" ]] || continue
    # an exact command match is always this script's item
    if [[ "$item" == "$cmdpath" ]]; then echo "$id"; return 0; fi
    # otherwise reuse an item whose command is the same script *name* and whose
    # installed copy is byte-identical to our source (prevents duplicates when
    # the same script is deployed under a different --target path).
    [[ "${item##*/}" == "$base" ]] || continue
    if [[ -n "$srchash" ]]; then
      itemhash="$(script_hash "$item")"
      [[ -n "$itemhash" && "$itemhash" == "$srchash" ]] && { echo "$id"; return 0; }
    fi
  done
  return 1
}

script_hash() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

next_plugin_id() {
  local m=0 id
  for id in $(all_plugin_ids); do
    (( id > m )) && m="$id"
  done
  echo $((m + 1))
}

configure_genmon_plugin() { # plugin id command path
  local id="$1" cmdpath="$2"
  xset "/plugins/plugin-$id" string "genmon"      || return 1
  xset "/plugins/plugin-$id/command" string "$cmdpath" || return 1
  xset "/plugins/plugin-$id/use-label" bool "false"    || return 1
  xset "/plugins/plugin-$id/update-period" int "$GENMON_PERIOD_MS" || return 1
  xset "/plugins/plugin-$id/enable-single-row" bool "true" || return 1
  return 0
}

panel_append() { # panel plugin-id
  local panel="$1" pid="$2" i key
  key="/panels/$panel/plugin-ids"
  local -a ids=()
  mapfile -t ids < <(xget_arr "$key")
  for i in "${ids[@]}"; do
    [[ "$i" == "$pid" ]] && return 0
  done
  xset_arr "$key" "${ids[@]}" "$pid" || die "Failed to append plugin $pid to $panel"
  info "Appended genmon item $pid to $panel"
}

panel_remove() { # panel plugin-id
  local panel="$1" pid="$2" i changed=0 key
  key="/panels/$panel/plugin-ids"
  local -a ids=() new=()
  mapfile -t ids < <(xget_arr "$key")
  for i in "${ids[@]}"; do
    if [[ "$i" == "$pid" ]]; then
      changed=1
    else
      new+=("$i")
    fi
  done
  (( changed )) || return 0
  ((${#new[@]})) || { warn "Refusing to remove the last item from $key"; return 1; }
  xset_arr "$key" "${new[@]}" || return 1
  info "Removed genmon item $pid from $panel"
}

panel_load() { # script names to load
  panel_compatible || {
    warn "Panel wiring skipped: xfce4-panel must use xfconf (configver 2)."
    warn "The scripts were installed regardless; add the items manually if needed."
    return 0
  }

  # snapshot the panel config once, before any change is made
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -f "$XFCONF_FILE" ]]; then
    cp -a "$XFCONF_FILE" "$XFCONF_FILE.bak-$stamp"
    if [[ "$(id -u)" -eq 0 ]]; then
      chown "$(owner_user)" "$XFCONF_FILE.bak-$stamp" 2>/dev/null || true
    fi
  fi
  info "Panel config backed up to $XFCONF_FILE.bak-$stamp"

  local panel; panel="$(choose_panel)"
  info "Wiring genmon items into $panel (appended at the end)"

  local target cmdpath pid
  local -a created=() appended=() loaded_ids=()
  for target in "$@"; do
    cmdpath="$INSTALL_DIR/$target"
    pid="$(plugin_for_script "$cmdpath" "$SCRIPTS_SRC/$target")" || pid=""
    if [[ -n "$pid" ]]; then
      configure_genmon_plugin "$pid" "$cmdpath" \
        || { warn "Failed to configure existing plugin $pid for $target"; continue; }
      info "Reusing existing genmon item $pid for $target"
    else
      pid="$(next_plugin_id)"
      configure_genmon_plugin "$pid" "$cmdpath" \
        || { warn "Failed to create genmon item for $target"; continue; }
      created+=("$pid")
      info "Created genmon item $pid for $target"
    fi
    if panel_append "$panel" "$pid"; then
      appended+=("$pid")
      loaded_ids+=("$pid")
    fi
  done

  # verify every selected script is wired up as expected, otherwise roll back
  local bad=0 id
  for target in "$@"; do
    pid="$(plugin_for_script "$INSTALL_DIR/$target" "$SCRIPTS_SRC/$target")" || pid=""
    [[ -n "$pid" ]] || { warn "Verification failed: no genmon item for $target"; bad=1; continue; }
    found_in_panel "$panel" "$pid" || { warn "Verification failed: item $pid not on $panel"; bad=1; continue; }
    [[ "$(xget "/plugins/plugin-$pid")" == "genmon" ]]            || { warn "Verification failed: $pid is not a genmon item"; bad=1; }
    [[ "$(xget "/plugins/plugin-$pid/use-label")" == "false" ]]   || { warn "Verification failed: label not hidden on $pid"; bad=1; }
    [[ "$(xget "/plugins/plugin-$pid/update-period")" == "$GENMON_PERIOD_MS" ]] \
      || { warn "Verification failed: period not 86400.00 s on $pid"; bad=1; }
  done

  if (( bad )); then
    for id in "${created[@]}"; do
      panel_remove "$panel" "$id" >/dev/null 2>&1 || true
      xreset "/plugins/plugin-$id"
    done
    warn "Panel wiring failed verification and was rolled back."
    warn "The panel was NOT modified (backup: $XFCONF_FILE.bak-$stamp)."
    return 1
  fi

  if ((${#appended[@]})); then
    info "Loaded ${#appended[@]} genmon item(s) into $panel — settings applied:"
    info "  command         $INSTALL_DIR/<script>"
    info "  use-label       false"
    info "  update-period   86400.00 s (24 h)"
  fi

  # force the items to render their content now instead of waiting one period.
  # per-item refresh events can be flaky, so restart the panel if any missed.
  if ((${#loaded_ids[@]})); then
    local fail=0 id
    for id in "${loaded_ids[@]}"; do
      xfce4-panel --plugin-event="genmon-$id:refresh:bool:true" >/dev/null 2>&1 \
        || fail=1
    done
    if (( fail )); then
      if xfce4-panel --restart >/dev/null 2>&1; then
        info "Restarted the panel so the items render immediately."
      else
        warn "Could not refresh the items now; they will show after the next 24 h period."
      fi
    else
      info "Refreshed the newly loaded genmon item(s) so they render immediately."
    fi
  fi
  return 0
}

found_in_panel() { # panel plugin-id
  local panel="$1" pid="$2" i
  for i in $(xget_arr "/panels/$panel/plugin-ids"); do
    [[ "$i" == "$pid" ]] && return 0
  done
  return 1
}

panel_unload() {
  panel_compatible || {
    warn "Panel unwiring skipped: xfce4-panel must use xfconf (configver 2)."
    return 0
  }
  local target pid p removed_any=0 before
  local -a unloaded=()
  before="$(all_plugin_ids)"
  for target in "$@"; do
    pid="$(plugin_for_script "$INSTALL_DIR/$target" "$SCRIPTS_SRC/$target")" || pid=""
    if [[ -z "$pid" ]]; then
      info "$target: no genmon item to remove"
      continue
    fi
    unloaded+=("$pid")
    for p in $(xget_arr "/panels" | sed 's/^panel-//'); do
      panel_remove "panel-$p" "$pid" && removed_any=1
    done
    xreset "/plugins/plugin-$pid" || true
    info "Unloaded $target (genmon item $pid removed)"
  done

  # integrity: no plugin other than the ones we unloaded may have vanished.
  # The running panel occasionally interferes with rapid array writes.
  local id extra=()
  for id in $before; do
    case " ${unloaded[*]} " in
      *" $id "*) continue ;;
    esac
    if [[ -z "$(xget "/plugins/plugin-$id")" ]] || ! found_on_any_panel "$id"; then
      extra+=("$id")
    fi
  done
  if ((${#extra[@]})); then
    warn "Integrity check: unexpected change to plugin(s): ${extra[*]}"
    warn "Re-run './setup.sh unload ${*@Q}' to re-synchronize, then verify the panel."
  fi

  # a live panel occasionally keeps a widget on screen and re-writes the
  # plugin's properties (e.g. `command`) during teardown.  Restart the panel
  # to flush it, then reset the subtree again so the reset finally sticks and
  # no stale command survives in the config.
  if [[ "$removed_any" == "1" ]]; then
    if xfce4-panel --restart >/dev/null 2>&1; then
      info "Restarted the panel so removed items vanish immediately."
    else
      warn "Could not restart the panel; removed items may linger until it restarts."
    fi
    for pid in "${unloaded[@]}"; do
      xreset "/plugins/plugin-$pid" || true
    done
    info "Unloaded from the panel; items take effect immediately."
  fi
}

found_on_any_panel() { # plugin-id
  local id="$1" p
  for p in $(xget_arr "/panels" | sed 's/^panel-//'); do
    if found_in_panel "panel-$p" "$id"; then return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# command line
# ---------------------------------------------------------------------------

if (($# == 0)); then usage 1; fi

CMD="" MODE="all" LOAD=0 UNLOAD=0 SELECTED=() TARGET=""
while (($#)); do
  case "$1" in
    install|uninstall|load|unload)
      [[ -n "$CMD" ]] && die "Duplicate command '$1'"
      CMD="$1"
      ;;
    --all)  MODE="all" ;;
    --only)
      shift
      (($#)) || die "--only requires a script name"
      SELECTED+=("$1"); MODE="only"
      ;;
    --target)
      shift
      (($#)) || die "--target requires a full path"
      TARGET="$1"
      ;;
    --load)   LOAD=1 ;;
    --unload) UNLOAD=1 ;;
    help|-h|--help) usage 0 ;;
    *) die "Unknown argument '$1' (run 'setup.sh help')" ;;
  esac
  shift
done

if [[ -n "$TARGET" ]]; then
  [[ "$TARGET" == /* ]] || die "--target requires a full (absolute) path, got '$TARGET'"
  INSTALL_DIR="${TARGET%/}"
fi

[[ -n "$CMD" ]] || die "Missing command (run 'setup.sh help')"
if [[ "$LOAD" == "1" ]]; then
  [[ "$CMD" == "install" ]] || die "--load is only valid with 'install' (or use 'load' alone)"
fi
if [[ "$UNLOAD" == "1" ]]; then
  [[ "$CMD" == "uninstall" ]] || die "--unload is only valid with 'uninstall' (or use 'unload' alone)"
fi

resolve_selection

case "$CMD" in
  install)
    info "Installing from $SCRIPTS_SRC -> $INSTALL_DIR"
    for s in "${SELECTED[@]}"; do info "  - $s"; done
    install_scripts "${SELECTED[@]}"
    if [[ "$LOAD" == "1" ]]; then
      panel_load "${SELECTED[@]}" || exit 1
    fi
    ;;
  uninstall)
    if [[ "$UNLOAD" == "1" ]]; then
      info "Removing genmon items from the panel first"
      panel_unload "${SELECTED[@]}"
    fi
    info "Uninstalling from $INSTALL_DIR"
    for s in "${SELECTED[@]}"; do info "  - $s"; done
    uninstall_scripts "${SELECTED[@]}"
    ;;
  load)
    info "Wiring genmon items into the Xfce panel"
    panel_load "${SELECTED[@]}" || exit 1
    ;;
  unload)
    info "Unwiring genmon items from the Xfce panel"
    panel_unload "${SELECTED[@]}"
    ;;
esac

info "Done."