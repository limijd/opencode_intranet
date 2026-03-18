# Deployment Guide — OpenCode Intranet on CentOS 7.6

## Transfer to Intranet

Build the artifact on an internet-connected machine first (see [BUILD.md](BUILD.md)).

```bash
# On build machine: package the output
cd /path/to/opencode_intranet
tar -czf opencode-intranet.tar.gz -C output .

# Transfer to intranet machine via any method:
#   scp, USB drive, shared network drive, etc.
scp opencode-intranet.tar.gz user@intranet-host:~/
```

## Install (No Root Required)

```bash
# On the CentOS 7.6 intranet machine:
mkdir -p ~/opencode
cd ~/opencode
tar -xzf ~/opencode-intranet.tar.gz

# First run — automatically patches the binary (takes a few seconds)
./opencode --version
# Expected output: 0.0.0-intranet (or your custom version)
```

### What Happens on First Run

1. Wrapper creates `~/.opencode/lib/` directory
2. Copies musl libraries there
3. Uses `patchelf` to rewrite the binary's ELF interpreter path
4. Creates `.patched` marker to skip this on subsequent runs
5. Runs OpenCode

### Verify Installation

```bash
./opencode --version      # Should print version
./opencode --help         # Should show OpenCode commands with ASCII logo
./opencode providers      # Should list provider management commands
```

## Configure Internal LLM

Create `~/.config/opencode/opencode.json`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "my-llm": {
      "name": "Internal LLM",
      "api": "http://your-internal-llm.company.com/v1",
      "npm": "@ai-sdk/openai-compatible",
      "models": {
        "your-model-name": {
          "name": "Your Model Display Name",
          "attachment": false,
          "reasoning": false,
          "tool_call": true,
          "temperature": true,
          "limit": {
            "context": 128000,
            "output": 4096
          }
        }
      }
    }
  },
  // Set default model
  "model": "my-llm/your-model-name"
}
```

### Configuration Fields

| Field | Description |
|-------|-------------|
| `api` | Your internal LLM endpoint URL (OpenAI-compatible) |
| `npm` | Always `"@ai-sdk/openai-compatible"` for intranet |
| `models.*.tool_call` | `true` if your model supports function calling |
| `models.*.reasoning` | `true` if your model has reasoning/CoT support |
| `models.*.attachment` | `true` if your model accepts file attachments |
| `models.*.limit.context` | Context window size in tokens |
| `models.*.limit.output` | Max output tokens |

### API Key (if required)

```bash
# Option 1: Environment variable
export MY_LLM_API_KEY="your-key"

# Option 2: Use opencode auth
./opencode providers login
```

In config, add `env` field to map the key:

```jsonc
{
  "provider": {
    "my-llm": {
      "env": ["MY_LLM_API_KEY"],
      // ... rest of config
    }
  }
}
```

## Usage

```bash
# Interactive TUI mode
./opencode

# Non-interactive / scripting mode
./opencode run "explain this code" < myfile.py

# Start headless server (for IDE integration)
./opencode serve

# Show configured providers
./opencode providers list
```

### Add to PATH

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/opencode:$PATH"

# Then use from anywhere:
opencode
```

## File Locations on Target Machine

| Path | Purpose |
|------|---------|
| `~/opencode/` | Installation directory |
| `~/.opencode/lib/` | musl libraries (auto-created on first run) |
| `~/.config/opencode/opencode.json` | User configuration |
| `~/.local/share/opencode/` | Session data, database |
| `~/.local/share/opencode/logs/` | Log files |

## Upgrading

1. Build new version on internet-connected machine
2. Transfer new `opencode-intranet.tar.gz` to intranet
3. Replace files:

```bash
cd ~/opencode
rm -f .patched     # Force re-patch on next run
tar -xzf ~/opencode-intranet.tar.gz
./opencode --version    # Verify + re-patch
```

## Troubleshooting

### "bad ELF interpreter: No such file or directory"

The binary hasn't been patched yet. Run via the wrapper script (`./opencode`), not directly (`./opencode-bin`).

### "patchelf failed, using fallback"

patchelf couldn't modify the binary. In fallback mode, core functionality works but `--version` and `--help` show Bun's help instead of OpenCode's. Use `opencode providers` or `opencode run` to verify.

### "Segmentation fault" on first run

Delete `.patched` and `opencode-bin`, re-extract from tarball:

```bash
rm -f .patched
tar -xzf ~/opencode-intranet.tar.gz
./opencode --version
```

### Cannot connect to internal LLM

1. Check URL is reachable: `curl http://your-llm.company.com/v1/models`
2. Check config: `cat ~/.config/opencode/opencode.json`
3. Check logs: `ls ~/.local/share/opencode/logs/`

### ripgrep not found

OpenCode needs `rg` (ripgrep) for file search. In intranet mode, auto-download is disabled. Install manually:

```bash
# If your intranet has yum repos with EPEL:
sudo yum install -y ripgrep

# Or transfer a static ripgrep binary:
# https://github.com/BurntSushi/ripgrep/releases
cp rg ~/opencode/  # or anywhere on PATH
```

### TUI rendering issues

CentOS 7.6 terminals may have limited Unicode support. Try:

```bash
export TERM=xterm-256color
./opencode
```

If TUI still has issues, use non-interactive mode:

```bash
./opencode run "your prompt here"
./opencode serve   # then connect via API
```
