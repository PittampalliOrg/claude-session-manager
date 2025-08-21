# Claude Session Manager - Deno TypeScript Implementation

## Overview
A complete TypeScript/Deno reimplementation of the Claude session management bash scripts, using the Claude Code SDK types for type safety while maintaining CLI compatibility.

## Features
- ✅ Full TypeScript with Claude Code SDK type definitions
- ✅ Session listing, viewing, exporting, and deletion
- ✅ Integration with tmux, sesh, fzf, gum, and zoxide
- ✅ Local session caching with Deno KV
- ✅ Reusable UI components
- ✅ Compiled binary for better performance

## Installation

### Prerequisites
- Deno (v2.0+)
- tmux
- fzf (optional, for fuzzy finding)
- gum (optional, for styled UI)
- zoxide (optional, for frecency sorting)

### Setup
```bash
# Clone or download the files
# Install dependencies are handled automatically by Deno

# Run tests to create mock sessions
deno task test

# Compile to binary (optional)
deno task compile
```

## Usage

### Using Deno tasks
```bash
# List all sessions
deno task cli --list

# Interactive selection (uses gum by default)
deno task cli

# Use fzf for selection
deno task cli --fzf

# View a specific session
deno task cli --view <session-id>

# Export session to markdown
deno task cli --export <session-id>

# Resume a session
deno task cli --resume <session-id>

# Search sessions
deno task cli --search "keyword"
```

### Using compiled binary
```bash
# After compiling with `deno task compile`
./claude-manager --list
./claude-manager --resume <session-id>
./claude-manager --search "typescript"
```

## Project Structure

### Core Files
- `claude-types.ts` - TypeScript type definitions extending Claude Code SDK
- `claude-cli-wrapper.ts` - Wrapper around Claude CLI commands
- `claude-session-manager.ts` - Main CLI application
- `session-store.ts` - Local Deno KV caching for sessions
- `ui-components.ts` - Reusable terminal UI components
- `test-setup.ts` - Test environment setup with mock sessions

### Configuration
- `deno.json` - Deno configuration with tasks and imports

## Key Components

### Type System
- Imports SDK types: `SDKMessage`, `PermissionMode`, `HookInput`, etc.
- Custom types: `ClaudeSession`, `SessionFileEntry`, `CachedSession`
- Type guards for message type checking

### Session Store
- Uses Deno KV for local caching
- Indexes by directory, project, date, tags
- Auto-sync with filesystem
- Search and filter capabilities

### UI Components
- Spinner for long operations
- Progress bar for batch operations
- Selection menus (gum/fzf/fallback)
- Formatted tables and boxes
- Status messages with icons

### Tmux Integration
- Creates named windows for Claude sessions
- Manages sesh sessions
- Switches between existing sessions
- Handles both inside and outside tmux contexts

## Testing

The test setup creates:
- Tmux session `cli-1-2` with multiple windows
- 5 mock Claude sessions with different projects
- Test data for various scenarios

Run tests:
```bash
# Create test environment
deno task test

# Attach to test tmux session
tmux attach -t cli-1-2

# Clean up test session
tmux kill-session -t cli-1-2
```

## SDK Integration

The implementation uses Claude Code SDK types for:
- Type safety and IntelliSense
- Message type definitions
- Permission modes
- Hook interfaces
- Query patterns

While using SDK types, the actual execution happens through the Claude CLI, maintaining full compatibility with existing Claude Code installations.

## Benefits Over Bash Scripts

1. **Type Safety** - Full TypeScript with compile-time checking
2. **Performance** - Compiled binary execution
3. **Caching** - Local KV store for fast access
4. **Maintainability** - Modular architecture with clear separation
5. **Testing** - Easier to test individual components
6. **Cross-platform** - Better Windows/Mac compatibility through Deno
7. **Modern Tooling** - Leverage Deno's built-in features

## Future Enhancements

- [ ] Real-time session monitoring
- [ ] MCP server integration
- [ ] Advanced filtering and search
- [ ] Session templates
- [ ] Batch operations
- [ ] Export to multiple formats (JSON, HTML, PDF)
- [ ] Session analytics and insights
- [ ] Integration with other AI tools

## License
MIT