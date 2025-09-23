#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[0;31mERROR on line $LINENO\033[0m" >&2' ERR

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==> $1${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $1${NC}"; }

check_macos()   { [[ $(uname) == Darwin ]] || { echo -e "${RED}ERROR: macOS only${NC}"; exit 1; }; }
check_rosetta() {
  if [[ $(uname -m) == arm64 ]] && ! pgrep -q oahd; then
    log "Installing Rosetta 2…"
    softwareupdate --install-rosetta --agree-to-license
  fi
}

install_homebrew() {
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [[ $(uname -m) == arm64 ]] && { echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile; eval "$(/opt/homebrew/bin/brew shellenv)"; }
  else log "Homebrew already installed"; fi
  brew analytics off
  log "Updating Homebrew…"; brew update && brew upgrade
}

install_cli_tools() {
  log "Installing CLI tools…"
  local formulas=(htop poetry uv python@3.12 zsh git docker postgresql@16 redis node wget tree jq gh)
  for f in "${formulas[@]}"; do
    brew list --formula | grep -q "^${f}$" && log "✓ $f" || { log "Installing $f"; brew install "$f"; }
  done

  log "Starting PostgreSQL & Redis…"
  brew services start postgresql@16
  brew services start redis
  sleep 2
  pgrep postgres     >/dev/null && log "✓ PostgreSQL running" || warn "PostgreSQL failed"
  pgrep redis-server >/dev/null && log "✓ Redis running"     || warn "Redis failed"
}

install_gui_apps() {
  log "Installing GUI apps…"
  local casks=(
    brave-browser google-chrome rectangle chatgpt the-unarchiver vlc spotify keepassxc
    google-drive whatsapp telegram iterm2 calibre sublime-text slack visual-studio-code
    libreoffice raycast stats
  )
  for c in "${casks[@]}"; do
    brew list --cask | grep -q "^$c$" && log "✓ $c" || { log "Installing $c"; brew install --cask "$c"; }
  done
}

setup_iterm2() {
  log "Configuring iTerm2 (no close prompts + Dark theme)…"

  local DOMAIN="com.googlecode.iterm2"
  local PREFS_DIR="" TARGET=""
  local has_app=false

  [[ -d "/Applications/iTerm.app" || -d "$HOME/Applications/iTerm.app" ]] && has_app=true
  if command -v brew &>/dev/null; then
    brew list --cask 2>/dev/null | grep -q '^iterm2$' && has_app=true
  fi

  if [[ "$(defaults read "$DOMAIN" LoadPrefsFromCustomFolder 2>/dev/null || echo 0)" == "1" ]]; then
    PREFS_DIR="$(defaults read "$DOMAIN" PrefsCustomFolder 2>/dev/null || echo "")"
  fi
  if [[ -n "$PREFS_DIR" && -d "$PREFS_DIR" ]]; then
    TARGET="$PREFS_DIR/$DOMAIN.plist"
    log "Using custom prefs at: $TARGET"
  else
    TARGET="$DOMAIN"
    log "Using prefs domain: $DOMAIN"
  fi

  write() { defaults write "$TARGET" "$1" "${@:2}"; }

  # Disable close/quit confirmation prompts
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    read -r -a parts <<< "$line"
    write "${parts[@]}" || warn "Failed to set: $line"
  done <<'EOF'
PromptOnQuit -bool false
PromptOnClose -int 0
ConfirmClosingMultipleTabs -bool false
ConfirmClosingMultipleWindows -bool false
EOF

  # Prefer iTerm2 Dark UI theme
  write Theme -string "Dark" 2>/dev/null || \
    warn "iTerm2 'Theme' key not supported; it may follow macOS appearance"

  log "✓ iTerm2 configured"
}

install_claude_code() {
  log "Installing Claude Code CLI…"
  if command -v claude &>/dev/null; then
    log "✓ Claude Code already installed"
    return
  fi
  if ! command -v node &>/dev/null; then
    warn "Node.js not found, Claude Code skipped"
    return
  fi
  npm install -g @anthropic-ai/claude-code
  command -v claude &>/dev/null && log "✓ Claude Code installed" \
    || warn "Claude Code installation failed"
}

wait_for_app() { # wait_for_app "Raycast" 5
  local app="$1" timeout="${2:-5}" i=0
  while ! pgrep -x "$app" >/dev/null 2>&1; do
    (( i++ >= timeout )) && return 1
    sleep 1
  done
  return 0
}

setup_raycast() {
  log "Setting up Raycast with ⌘ + Space…"

  if ! brew list --cask | grep -q '^raycast$' && [[ ! -d "/Applications/Raycast.app" && ! -d "$HOME/Applications/Raycast.app" ]]; then
    warn "Raycast not installed, skipping configuration"
    return
  fi

  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict || true

  log "Disabling Spotlight keyboard shortcuts…"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '{
    enabled = 0;
    value = {
      parameters = (32, 49, 1048576);
      type = "standard";
    };
  }' || warn "Failed to disable Spotlight hotkey (ID 64)"

  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 '{
    enabled = 0;
    value = {
      parameters = (32, 49, 1572864);
      type = "standard";
    };
  }' || warn "Failed to disable Spotlight hotkey (ID 65)"

  killall Dock || true

  log "Opening Raycast Preferences so you can assign ⌘ + Space…"
  open -g -a "Raycast" 2>/dev/null || warn "Could not open Raycast automatically"
  wait_for_app "Raycast" 5 || warn "Raycast did not appear; open it manually to set the hotkey"

  /usr/bin/osascript <<'OSA' 2>/dev/null || true
tell application "System Events"
  try
    if application process "Raycast" exists then
      tell application process "Raycast"
        set frontmost to true
        delay 0.2
        key code 43 using {command down} -- ⌘ + ,
      end tell
    end if
  end try
end tell
OSA

  log "✓ Spotlight shortcuts disabled."
  log "  Now set Raycast Hotkey to ⌘ + Space: Raycast → Preferences → Hotkey."
  warn "If macOS blocks keystrokes, grant Accessibility permissions to your terminal app in System Settings → Privacy & Security → Accessibility."
}

setup_zsh() {
  log "Setting up Zsh & plugins…"
  [[ -d ~/.oh-my-zsh ]] || { log "Installing oh-my-zsh…"; sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; }
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  for repo in zsh-users/{zsh-autosuggestions,zsh-syntax-highlighting,zsh-completions}; do
    local name
    name=$(basename "$repo")
    [[ -d $ZSH_CUSTOM/plugins/$name ]] || git clone "https://github.com/$repo.git" "$ZSH_CUSTOM/plugins/$name"
  done
  grep -q "zsh-autosuggestions" ~/.zshrc || \
    sed -i '' 's/plugins=(/&git docker pip python brew zsh-autosuggestions zsh-syntax-highlighting zsh-completions /' ~/.zshrc

  # ---------- custom block with markers ----------
  if ! grep -q "# >>> macbook-setup >>>" ~/.zshrc; then
cat >> ~/.zshrc << 'EOF'
# >>> macbook-setup >>>
export HIST_STAMPS="yyyy-mm-dd HH:MM:SS"
setopt HIST_FIND_NO_DUPS SHARE_HISTORY AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT

# Homebrew completions
if command -v brew &>/dev/null; then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
  autoload -Uz compinit && compinit
fi

# Aliases
alias ll='ls -la'
alias la='ls -la'
alias py='python3'
alias pip='pip3'
# <<< macbook-setup <<<
EOF
  fi

  # ---- Add update-mac() helper if missing ----
  if ! grep -q "update-mac()" ~/.zshrc; then
cat >> ~/.zshrc << 'EOF'

# Homebrew update helper
update-mac() {
  local start=$(date +%s)

  echo "🔄 Updating Homebrew formulas and casks..."
  brew update

  echo "⬆️  Upgrading apps..."
  brew upgrade

  echo "🧹 Cleaning up old versions..."
  brew cleanup

  local end=$(date +%s)
  local duration=$((end - start))

  echo "✅ All apps are up to date in ${duration}s 🚀"
}
EOF
    log "Added update-mac() to ~/.zshrc"
  else
    log "update-mac() already present in ~/.zshrc"
  fi

  [[ $SHELL == /bin/zsh ]] || { log "Changing default shell to zsh"; chsh -s /bin/zsh; }
}

setup_screenshots_folder() {
  log "Redirecting screenshots to ~/Screenshots"
  mkdir -p ~/Screenshots
  defaults write com.apple.screencapture location ~/Screenshots
  killall SystemUIServer || true
}

setup_macos_preferences() {
  log "Tweaking macOS prefs (Finder path bar on)"
  defaults write com.apple.finder ShowPathbar -bool true
  killall Finder || true
}

setup_git() {
  log "Configuring Git…"

  # Detect current value (if any) to use as default
  local current_name current_email
  current_name=$(git config --global --get user.name || true)
  current_email=$(git config --global --get user.email || true)

  # Prompt user
  read -rp "Git user name [${current_name:-}]: " input_name
  read -rp "Git email     [${current_email:-}]: " input_email
  local git_name="${input_name:-$current_name}"
  local git_email="${input_email:-$current_email}"

  if [[ -z "$git_name" || -z "$git_email" ]]; then
    warn "Git name/email not set. Skipping Git global configuration."
    return
  fi

  git config --global user.name  "$git_name"
  git config --global user.email "$git_email"
  git config --global pull.rebase false
  git config --global init.defaultBranch main
  git config --global color.ui auto
  git config --global core.editor vi

  git config --global alias.st 'status'
  git config --global alias.ci commit
  git config --global alias.co checkout
  git config --global alias.br branch
  git config --global alias.last 'log -1 HEAD --stat'
  git config --global alias.unstage 'restore --staged'
  git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
  git config --global alias.undo 'reset HEAD~1 --mixed'
  git config --global alias.amend 'commit --amend'

  git config --global diff.algorithm histogram
  git config --global merge.conflictstyle diff3
  git config --global credential.helper osxkeychain
  log "✓ Git configured"
}

setup_ssh_key() {
  log "Setting up SSH key…"
  local key=~/.ssh/id_ed25519; mkdir -p ~/.ssh && chmod 700 ~/.ssh
  if [[ ! -f $key ]]; then
    ssh-keygen -t ed25519 -C "$(git config --global user.email || echo user@example.com)" -f "$key" -N ""
    eval "$(ssh-agent -s)" && ssh-add --apple-use-keychain "$key"
  fi
  # ---------- SSH config block with markers ----------
  grep -q "# >>> macbook-setup >>>" ~/.ssh/config 2>/dev/null || cat >> ~/.ssh/config << 'EOF'
# >>> macbook-setup >>>
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
# <<< macbook-setup <<<
EOF
  pbcopy < "${key}.pub" && log "SSH public key copied to clipboard"
}

install_vscode_extensions() {
  log "Ensuring VS Code CLI…"
  open -g -a "Visual Studio Code" || true
  for _ in {1..15}; do command -v code &>/dev/null && break || sleep 2; done
  command -v code &>/dev/null || { warn "'code' CLI not found; install it via VS Code → Command Palette → Shell Command: Install 'code' command in PATH"; return; }
  local exts=(ms-python.python ms-python.vscode-pylance batisteo.vscode-django bibhasdn.django-html charliermarsh.ruff)
  for e in "${exts[@]}"; do code --install-extension "$e" --force && log "✓ $e"; done
}

show_summary() {
  echo; log "🎉 Setup finished"; echo
  echo "• Restart terminal ⇒  source ~/.zshrc"
  echo "• PostgreSQL 5432 | Redis 6379 running | Claude Code CLI available as 'claude'"
  echo "• Spotlight disabled — manually set Raycast hotkey to ⌘ + Space in Raycast Preferences (Hotkey)"
  warn "You may need to log out/in for keyboard shortcut changes to take effect"
}

main() {
  log "Starting macOS setup…"
  check_macos; check_rosetta
  install_homebrew
  install_cli_tools
  install_gui_apps
  setup_iterm2
  install_claude_code
  setup_raycast
  setup_zsh
  setup_screenshots_folder
  setup_macos_preferences
  setup_git
  setup_ssh_key
  install_vscode_extensions
  brew cleanup -s && brew autoremove
  show_summary
}
main
