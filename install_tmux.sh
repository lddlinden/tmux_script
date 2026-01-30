#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Detect environment
# ----------------------------
USER_HOME="${HOME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.tmux_install_state"
UNINSTALL_SCRIPT="${SCRIPT_DIR}/uninstall_tmux.sh"

REQUIRED_PACKAGES=(tmux git xclip)

# ----------------------------
# Detect package manager
# ----------------------------
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then echo "zypper"
  else echo "unknown"
  fi
}

PKG_MGR="$(detect_pkg_mgr)"
if [[ "$PKG_MGR" == "unknown" ]]; then
  echo "Kunde inte identifiera paketmanager. Avbryter."
  exit 1
fi

# ----------------------------
# Install packages
# ----------------------------
install_packages() {
  local installed_now=()

  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    case "$PKG_MGR" in
      apt)
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
          sudo apt-get update -y
          sudo apt-get install -y "$pkg"
          installed_now+=("$pkg")
        fi
        ;;
      dnf|yum)
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
          sudo "$PKG_MGR" install -y "$pkg"
          installed_now+=("$pkg")
        fi
        ;;
      pacman)
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
          sudo pacman -Syu --noconfirm "$pkg"
          installed_now+=("$pkg")
        fi
        ;;
      zypper)
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
          sudo zypper install -y "$pkg"
          installed_now+=("$pkg")
        fi
        ;;
    esac
  done

  if (( ${#installed_now[@]} > 0 )); then
    printf "%s\n" "${installed_now[@]}" >> "$STATE_FILE"
  fi
}

# ----------------------------
# Ensure tmux-256color terminfo
# ----------------------------
ensure_terminfo() {
  if infocmp tmux-256color >/dev/null 2>&1; then
    echo "terminfo tmux-256color finns redan."
    return
  fi

  if command -v tic >/dev/null 2>&1; then
    cat > /tmp/tmux-256color.terminfo <<'EOF'
tmux-256color|tmux with 256 colors,
  use=xterm-256color,
EOF
    tic -x /tmp/tmux-256color.terminfo || true
    rm -f /tmp/tmux-256color.terminfo
    echo "__created_terminfo_tmux_256color" >> "$STATE_FILE"
  fi
}

# ----------------------------
# Write tmux config
# ----------------------------
write_tmux_conf() {
  cat > "${USER_HOME}/.tmux.conf" <<'EOF'
# ===== ESSENTIAL SETTINGS =====
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",*:RGB"
set -sg escape-time 0
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g mouse on
set -g focus-events on
set -as terminal-features ",xterm-256color:RGB"
setw -g aggressive-resize on

# ===== KEY BINDINGS =====
unbind C-b
set -g prefix C-a
bind C-a send-prefix
bind r source-file ~/.tmux.conf \; display "Config reloaded!"
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"

bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# ===== APPEARANCE =====
set -g status-position top
set -g status-style fg=#8b949e

set -g status-left-length 40
set -g status-right-length 80

set -g status-left '#[fg=#00e68a,bold] #{username}@#H #[fg=#30363d]│ #S '

set -g status-right '#[fg=#30363d]│#[fg=#1f6feb] #( . /etc/os-release 2>/dev/null && echo "$NAME" ) #[fg=#8b949e] %H:%M │ %Y-%m-%d '

# Window styles
setw -g window-style fg=#8B7E86,bg=#3A3437
setw -g window-active-style fg=#C6BAEE,bg=#09031D,bold

# Window formats
setw -g window-status-format ' #I:#W '
setw -g window-status-current-format ' #I:#W '

# Pane borders
set -g pane-border-style fg=#30363d
set -g pane-active-border-style fg=#0a4ea1

set -g message-style bg=#00e68a,fg=#000000,bold

# ===== COPY MODE =====
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "xclip -selection clipboard -i"

# ===== PLUGINS (TPM) =====
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @resurrect-strategy-vim 'session'
set -g @continuum-restore 'on'

run '~/.tmux/plugins/tpm/tpm'
EOF

  echo "__wrote_tmux_conf" >> "$STATE_FILE"
}

# ----------------------------
# Install TPM + plugins
# ----------------------------
install_tpm_and_plugins() {
  command -v git >/dev/null 2>&1 || {
    echo "Error: git is required but not installed."
    exit 1
  }

  local tpm_dir="${USER_HOME}/.tmux/plugins/tpm"

  if [[ ! -d "$tpm_dir" ]]; then
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
    echo "__cloned_tpm" >> "$STATE_FILE"
  fi

  if [[ -x "${tpm_dir}/bin/install_plugins" ]]; then
    "${tpm_dir}/bin/install_plugins" || true
    echo "__installed_plugins" >> "$STATE_FILE"
  fi
}

# ----------------------------
# Run everything
# ----------------------------
install_packages
ensure_terminfo
write_tmux_conf
install_tpm_and_plugins

echo "✅ tmux installation complete."

create_uninstall_script() {
  cat > "$UNINSTALL_SCRIPT" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.tmux_install_state"
USER_HOME="${HOME}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No install state found. Nothing to uninstall."
  exit 0
fi

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then echo "zypper"
  else echo "unknown"
  fi
}

PKG_MGR="$(detect_pkg_mgr)"

echo "Starting tmux uninstall..."

while read -r entry; do
  case "$entry" in
    __wrote_tmux_conf)
      if [[ -f "${USER_HOME}/.tmux.conf" ]]; then
        rm -f "${USER_HOME}/.tmux.conf"
        echo "Removed ~/.tmux.conf"
      fi
      ;;
    __cloned_tpm)
      rm -rf "${USER_HOME}/.tmux/plugins/tpm"
      echo "Removed TPM"
      ;;
    __created_terminfo_tmux_256color)
      if command -v tic >/dev/null 2>&1; then
        tic -x -r /usr/share/terminfo /dev/null || true
        rm -f ~/.terminfo/tmux-256color 2>/dev/null || true
        echo "Removed tmux-256color terminfo"
      fi
      ;;
    tmux|git|xclip)
      case "$PKG_MGR" in
        apt) sudo apt-get remove -y "$entry" ;;
        dnf) sudo dnf remove -y "$entry" ;;
        yum) sudo yum remove -y "$entry" ;;
        pacman) sudo pacman -Rs --noconfirm "$entry" ;;
        zypper) sudo zypper remove -y "$entry" ;;
      esac
      echo "Removed package: $entry"
      ;;
  esac
done < "$STATE_FILE"

rm -f "$STATE_FILE"
echo "✅ tmux uninstall complete."
EOS

  chmod +x "$UNINSTALL_SCRIPT"
  echo "Created uninstall script: $UNINSTALL_SCRIPT"
}

create_uninstall_script