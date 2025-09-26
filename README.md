# macOS Setup Script

An automated script to set up a new MacBook with development tools, essential applications, and useful configurations.

## 🚀 Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/AlexLoar/macos-setup/main/setup.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/AlexLoar/macos-setup.git
cd macos-setup
chmod +x setup.sh
./setup.sh
```

## 📋 What does it install?

### CLI Tools
- **Package managers**: Homebrew, Poetry, uv
- **Development**: Python 3.12, Node.js 18+, Git, Docker (CLI), GitHub CLI, Claude Code CLI
- **Databases**: PostgreSQL 16, Redis
- **Utilities**: htop, wget, tree, jq, git-delta
- **Shell**: Zsh with Oh My Zsh and plugins

### GUI Applications
- **Browsers**: Brave, Chrome
- **Productivity**: Rectangle, Raycast, Stats, Google Drive
- **Communication**: Slack, WhatsApp, Telegram
- **Development**: VS Code, iTerm2, Sublime Text
- **Multimedia**: VLC, Spotify
- **Others**: KeePassXC, Calibre, LibreOffice, ChatGPT, The Unarchiver  

### VS Code Extensions
- Python, Pylance
- Django support
- Ruff formatter

## 🔧 Configurations

### Git
- Default branch: `main`
- Aliases: `st`, `ci`, `co`, `br`, `last`, `unstage`, `lg`, `undo`, `amend`  
- Uses [delta](https://github.com/dandavison/delta) for improved diffs if installed  

### SSH
- Generates Ed25519 key
- Configures SSH agent with Keychain
- Copies public key to clipboard

### Zsh
- Timestamped history
- Enhanced directory navigation
- No duplicates in history
- Aliases: `ll`, `la`, `py`, `pip`  
- Adds `update-mac()` helper to update and clean Homebrew in one command  

### macOS
- Screenshots saved to `~/Screenshots`
- Shows path bar in Finder

### iTerm2
- Custom profile with optimized settings
- Enhanced color scheme and transparency

### Raycast
- Disables Spotlight shortcuts  
- Opens Raycast Preferences so you can set ⌘ + Space as hotkey

## 🛠️ Requirements

- macOS (Intel or Apple Silicon)
- Internet connection
- Administrator permissions

## 📝 Notes

- **Apple Silicon**: The script automatically installs Rosetta 2 if needed
- **Services**: PostgreSQL (port 5432) and Redis (port 6379) start automatically
- **SSH**: If an SSH key already exists, it's preserved and just copied to clipboard
- **Idempotent**: The script can be run multiple times without duplicating configurations

## ⚠️ Post-installation

1. **Restart terminal** or run `source ~/.zshrc`
2. **Configure your apps**: Sign in to Slack, Google Drive, etc.
3. **VS Code**: If the `code` command doesn't work, install it from VS Code:
   - `Cmd+Shift+P` → "Shell Command: Install 'code' command in PATH"
4. **Claude Code**: Run `claude login` to configure the CLI
5. **Raycast**: Assign ⌘ + Space as its hotkey in Preferences
6. **Rectangle**: Configure your preferred keyboard shortcuts

## 🔍 Troubleshooting

### PostgreSQL or Redis won't start
```bash
brew services restart postgresql@16
brew services restart redis
```

### Check services
```bash
brew services list
```

### Clean up Homebrew installations
```bash
brew cleanup -s && brew autoremove
```

## 📄 License

MIT License - Feel free to modify and share

---

**Author**: [Álex López](https://github.com/AlexLoar)
