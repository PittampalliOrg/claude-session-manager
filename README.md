# Claude Session Manager

A TypeScript/Deno-based session manager for Claude Code, providing seamless integration with tmux, fzf, gum, and other terminal tools.

## Features

- 🚀 **Full TypeScript** with Claude Code SDK type definitions
- 📁 **Session Management**: List, view, export, resume, and delete Claude sessions
- 🖥️ **Tmux Integration**: Automatic window and session management
- 🔍 **Smart Selection**: Uses fzf or gum for interactive session selection
- 💾 **Local Caching**: Deno KV store for fast session access
- 📦 **NixOS Ready**: Can be installed as a NixOS package
- ⚡ **Compiled Binary**: Fast execution with Deno compile

## Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/PittampalliOrg/claude-session-manager.git
cd claude-session-manager

# Run directly with Deno
deno task cli --help

# Or compile to binary
deno task compile
./claude-manager --help
```

### NixOS Installation

Add to your NixOS configuration:

```nix
{
  # In your flake.nix inputs
  claude-manager = {
    url = "github:PittampalliOrg/claude-session-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  
  # In your system packages
  environment.systemPackages = [
    inputs.claude-manager.packages.${system}.default
  ];
}
```

## Usage

```bash
# List all sessions
claude-manager --list

# Interactive selection with gum
claude-manager

# Use fzf for selection
claude-manager --fzf

# Resume a specific session
claude-manager --resume <session-id>

# Export session to markdown
claude-manager --export <session-id>

# Search sessions
claude-manager --search "typescript"
```

## Development

### Prerequisites

- Deno 2.0+
- tmux
- fzf (optional)
- gum (optional)
- zoxide (optional)

### Project Structure

```
.
├── claude-session-manager.ts  # Main CLI application
├── claude-cli-wrapper.ts      # Claude CLI wrapper
├── claude-types.ts            # TypeScript definitions
├── session-store.ts           # Deno KV caching
├── ui-components.ts           # Reusable UI components
├── test-setup.ts              # Test environment setup
├── deno.json                  # Deno configuration
└── flake.nix                  # Nix package definition
```

### Testing

```bash
# Run test setup
deno task test

# Run type checking
deno check claude-session-manager.ts

# Compile binary
deno task compile
```

## License

MIT

## Contributing

Pull requests welcome! Please ensure all TypeScript files pass `deno check` and follow the existing code style.

## Author

Created for managing Claude Code sessions efficiently in a NixOS/WSL2 environment.