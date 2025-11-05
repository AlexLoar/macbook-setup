#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[0;31mERROR on line $LINENO\033[0m" >&2' ERR

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==> $1${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $1${NC}"; }

check_macos()   { [[ $(uname) == Darwin ]] || { echo -e "${RED}ERROR: macOS only${NC}"; exit 1; }; }

check_rosetta() {
  if [[ $(uname -m) == arm64 ]]; then
    if ! /usr/bin/pgrep -q oahd 2>/dev/null; then
      log "Installing Rosetta 2…"
      softwareupdate --install-rosetta --agree-to-license || log "Rosetta may already be installed"
    fi
  fi
}

ensure_xcode_clt() {
  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools…"
    xcode-select --install || true
    until xcode-select -p &>/dev/null; do sleep 2; done
    log "✓ Xcode Command Line Tools installed"
  fi
}

install_homebrew() {
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Ensure brew is in PATH
    if command -v /opt/homebrew/bin/brew &>/dev/null; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
    if command -v /usr/local/bin/brew &>/dev/null; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    log "Homebrew already installed"
  fi
  brew analytics off
  log "Updating Homebrew…"; brew update && brew upgrade
}

install_cli_tools() {
  log "Installing CLI tools…"
  local formulas=(htop poetry uv python@3.12 zsh git git-delta docker postgresql@16 redis node wget tree jq gh)
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

# Finds the full path to an application bundle (.app)
find_app_path() {
  local app="$1"
  [[ "$app" == *.app ]] || app="${app}.app"

  local p1="/Applications/$app" p2="$HOME/Applications/$app"
  if [[ -d "$p1" ]]; then
    command -v realpath &>/dev/null && realpath "$p1" 2>/dev/null || echo "$p1"
    return 0
  fi
  if [[ -d "$p2" ]]; then
    command -v realpath &>/dev/null && realpath "$p2" 2>/dev/null || echo "$p2"
    return 0
  fi

  if command -v mdfind &>/dev/null; then
    local found
    found="$(/usr/bin/mdfind "kMDItemKind == 'Application' && kMDItemFSName == '$app'" 2>/dev/null | head -n1 || true)"
    if [[ -n "$found" && -d "$found" ]]; then
      command -v realpath &>/dev/null && realpath "$found" 2>/dev/null || echo "$found"
      return 0
    fi
  fi
  return 1
}

install_gui_apps() {
  log "Installing GUI apps…"

  # Mapping: Homebrew cask → Application bundle name
  declare -A BUNDLE=(
    [brave-browser]="Brave Browser"
    [google-chrome]="Google Chrome"
    [rectangle]="Rectangle"
    [chatgpt]="ChatGPT"
    [the-unarchiver]="The Unarchiver"
    [vlc]="VLC"
    [spotify]="Spotify"
    [keepassxc]="KeePassXC"
    [google-drive]="Google Drive"
    [whatsapp]="WhatsApp"
    [telegram]="Telegram"
    [iterm2]="iTerm"
    [calibre]="calibre"
    [sublime-text]="Sublime Text"
    [slack]="Slack"
    [visual-studio-code]="Visual Studio Code"
    [libreoffice]="LibreOffice"
    [raycast]="Raycast"
    [stats]="Stats"
    [displaylink]="DisplayLink Manager"
    [notunes]="NoTunes"
  )

  local casks=(
    brave-browser google-chrome rectangle chatgpt the-unarchiver vlc spotify keepassxc
    google-drive whatsapp telegram iterm2 calibre sublime-text slack visual-studio-code
    libreoffice raycast stats displaylink notunes
  )

  for c in "${casks[@]}"; do
    # 1) Skip if cask already installed
    if brew list --cask 2>/dev/null | grep -qx "$c"; then
      log "✓ $c (Homebrew cask present)"
      continue
    fi

    # 2) Is there an existing .app bundle (manually installed)?
    local bundle="${BUNDLE[$c]-}"
    if [[ -z "$bundle" ]]; then
      # Safe heuristic: generate the bundle name if it's not mapped
      bundle="$(echo "$c" | sed -E 's/-/ /g; s/\b(.)/\U\1/g')"
    fi

    if find_app_path "${bundle}.app" >/dev/null 2>&1; then
      log "✓ Found existing app: ${bundle}.app — skipping Homebrew install for $c"
      continue
    fi

    # 3) Install if neither cask nor bundle exists
    log "Installing $c"
    brew install --cask "$c" || warn "Failed to install $c"
  done
}

setup_iterm2() {
  log "Configuring iTerm2 (no close prompts + Dark theme)…"

  local DOMAIN="com.googlecode.iterm2"
  local PREFS_DIR="" TARGET=""
  local has_app=false

  if find_app_path "iTerm.app" >/dev/null 2>&1; then
    has_app=true
  fi
  if command -v brew &>/dev/null; then
    brew list --cask 2>/dev/null | grep -q '^iterm2$' && has_app=true
  fi

  if [[ "$has_app" != true ]]; then
    warn "iTerm2 not installed, skipping configuration"
    return
  fi

  # Detect if custom prefs folder is being used
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

  # Disable quit/close confirmations
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
  command -v claude &>/dev/null && log "✓ Claude Code installed" || warn "Claude Code installation failed"
}

wait_for_app() { # wait_for_app "Raycast" 5
  local app="$1" timeout="${2:-5}" i=0
  while ! pgrep -x "$app" >/dev/null 2>&1; do
    (( i++ >= timeout )) && return 1
    sleep 1
  done
  return 0
}

disable_spotlight_hotkeys() {
  log "Disabling Spotlight keyboard shortcuts…"
  local PLIST="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
  local ids=(64 65) # 64 = ⌘Space, 65 = ⌥⌘Space

  for id in "${ids[@]}"; do
    /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:$id:enabled false" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$id dict" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$id:enabled bool false" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$id:value dict" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$id:value:type string standard" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:$id:value:parameters array" "$PLIST" 2>/dev/null || true
  done

  killall Dock 2>/dev/null || true
}

# Disable Spotlight shortcuts and open Raycast prefs (hotkey to be set manually)
setup_raycast() {
  log "Setting up Raycast with ⌘ + Space…"

  if ! brew list --cask 2>/dev/null | grep -q '^raycast$' && ! find_app_path "Raycast.app" >/dev/null 2>&1; then
    warn "Raycast not installed, skipping configuration"
    return
  fi

  disable_spotlight_hotkeys

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


# Find the full path to an application bundle (.app).
# Checks /Applications, ~/Applications, and Spotlight if available.
ensure_login_item() {
  local name="$1" hidden="$2" path
  if ! path="$(find_app_path "${name}.app")"; then
    warn "Login Item: ${name} not found"
    return 1
  fi

  /usr/bin/osascript <<OSA >/dev/null 2>&1 || return 1
tell application "System Events"
  try
    try
      delete login item "${name}"
    end try
    make login item at end with properties {path:"${path}", hidden:${hidden}}
  end try
end tell
OSA

  # Verify the login item was persisted (TCC/privacy can block it)
  /usr/bin/osascript <<OSA 2>/dev/null | grep -qx "true"
tell application "System Events"
  try
    set ok to false
    repeat with li in (every login item)
      if name of li is equal to "${name}" then set ok to true
    end repeat
    return ok
  on error
    return false
  end try
end tell
OSA
}

# Configure apps to start when log in
setup_login_items() {
  log "Setting up Login Items…"
  local items=(
    "DisplayLink Manager:true"
    "Google Drive:true"
    "KeePassXC:true"
    "Rectangle:true"
    "Raycast:true"
    "NoTunes:true"
  )

  local ok=0 miss=0
  for spec in "${items[@]}"; do
    local name="${spec%%:*}" hidden="${spec##*:}"
    if ensure_login_item "$name" "$hidden"; then
      case "$name" in
        Rectangle) defaults write com.knollsoft.Rectangle launchOnLogin -bool true 2>/dev/null || true ;;
        Raycast)   defaults write com.raycast.macos       launchAtLogin -bool true 2>/dev/null || true ;;
      esac
      log "✓ Login Item: $name (hidden=${hidden})"; ((ok++))
    else
      warn "Failed Login Item: $name"; ((miss++))
    fi
  done

  log "Login Items summary: ${ok} added, ${miss} failed"
  log "Check in: System Settings → General → Login Items"
}

# Zsh/oh-my-zsh and common plugins
setup_zsh() {
  log "Setting up Zsh & plugins…"
  [[ -d ~/.oh-my-zsh ]] || {
    log "Installing oh-my-zsh…"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  }

  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  for repo in zsh-users/{zsh-autosuggestions,zsh-syntax-highlighting,zsh-completions}; do
    local name
    name=$(basename "$repo")
    [[ -d $ZSH_CUSTOM/plugins/$name ]] || git clone "https://github.com/$repo.git" "$ZSH_CUSTOM/plugins/$name"
  done
  grep -q "zsh-autosuggestions" ~/.zshrc || \
    sed -i '' 's/plugins=(/&git docker pip python brew zsh-autosuggestions zsh-syntax-highlighting zsh-completions /' ~/.zshrc

  # --- custom block with markers ---
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

  # Add update-mac() helper if missing
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

# Redirect screenshots to ~/Screenshots
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

# Global Git configuration (prompts for name/email)
setup_git() {
  log "Configuring Git…"

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
  git config --global alias.amend 'commit --amend --no-edit'

  git config --global diff.algorithm histogram
  git config --global merge.conflictstyle diff3
  git config --global credential.helper osxkeychain

  # Configure Delta as Git pager if installed
  if command -v delta &>/dev/null; then
    log "Configuring Delta for beautiful Git diffs…"
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.dark true
    git config --global delta.line-numbers true
    git config --global delta.hyperlinks true
    git config --global delta.side-by-side true
    log "✓ Delta configured as Git pager"
  fi

  log "✓ Git configured"
}

# Create SSH key (ed25519), add to agent, and copy pub key to clipboard
setup_ssh_key() {
  log "Setting up SSH key…"
  local key=~/.ssh/id_ed25519
  mkdir -p ~/.ssh && chmod 700 ~/.ssh

  if [[ ! -f $key ]]; then
    ssh-keygen -t ed25519 -C "$(git config --global user.email || echo user@example.com)" -f "$key" -N ""

    # Add to agent (with fallbacks for older versions)
    if pgrep -x ssh-agent >/dev/null; then
      ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add -K "$key" 2>/dev/null || ssh-add "$key"
    else
      eval "$(ssh-agent -s)"
      ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add -K "$key" 2>/dev/null || ssh-add "$key"
    fi
  fi

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

  # Wait up to ~60s for the CLI to be available
  for i in {1..30}; do
    command -v code &>/dev/null && break || sleep 2
  done

  command -v code &>/dev/null || {
    warn "'code' CLI not found; install it via VS Code → Command Palette → Shell Command: Install 'code' command in PATH"
    return
  }

  local exts=(ms-python.python ms-python.vscode-pylance batisteo.vscode-django bibhasdn.django-html charliermarsh.ruff)
  for e in "${exts[@]}"; do
    code --install-extension "$e" --force && log "✓ $e"
  done
}

show_summary() {
  echo
  log "🎉 Setup finished"
  echo
  echo "• Restart terminal ⇒  source ~/.zshrc"
  echo "• PostgreSQL 5432 | Redis 6379 running | Claude Code CLI available as 'claude'"
  echo "• Spotlight hotkeys disabled — set Raycast hotkey to ⌘ Space in Preferences"
  echo "• Login Items configured (hidden on login): DisplayLink Manager, Google Drive, KeePassXC, Rectangle, Raycast, NoTunes"
  warn "You may need to log out/in for some changes (shortcuts, login items) to take effect"
}

main() {
  log "Starting macOS setup…"
  check_macos
  check_rosetta
  ensure_xcode_clt
  install_homebrew
  install_cli_tools
  install_gui_apps
  setup_iterm2
  install_claude_code
  setup_raycast
  setup_login_items
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