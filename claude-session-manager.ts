#!/usr/bin/env deno run --allow-run --allow-read --allow-write --allow-env --allow-net

/**
 * Claude Session Manager - Deno TypeScript Implementation
 * 
 * A modern CLI for managing Claude Code sessions using:
 * - Claude Code SDK types for type safety
 * - CLI execution (not direct API) for compatibility
 * - Integration with tmux, sesh, fzf, gum, and zoxide
 */

import { parse } from "https://deno.land/std@0.224.0/flags/mod.ts";
import { Select, Checkbox, Input, Confirm } from "@cliffy/prompt";
import { Table } from "@cliffy/table";
import { colors } from "@cliffy/ansi/colors";
import { ClaudeCliWrapper } from "./claude-cli-wrapper.ts";
import { InteractiveMode } from "./interactive-ui.ts";
import type { 
  ClaudeSession, 
  SessionSelection,
  ExportFormat,
} from "./claude-types.ts";

// Initialize CLI wrapper
const claude = new ClaudeCliWrapper();

/**
 * Clean terminal state to prevent escape sequence issues
 */
function cleanTerminalState(): void {
  try {
    const encoder = new TextEncoder();
    // Disable bracketed paste mode
    Deno.stdout.writeSync(encoder.encode("\x1b[?2004l"));
    // Reset colors and attributes
    Deno.stdout.writeSync(encoder.encode("\x1b[0m"));
    // Clear any pending OSC sequences
    Deno.stdout.writeSync(encoder.encode("\x1b]110;\x07"));
    // Clear OSC 11 background color query
    Deno.stdout.writeSync(encoder.encode("\x1b]111;\x07"));
  } catch {
    // Ignore errors if output is not a terminal
  }
}

/**
 * Execute shell command helper
 */
async function exec(cmd: string, args: string[] = []): Promise<string> {
  const command = new Deno.Command(cmd, {
    args,
    stdout: "piped",
    stderr: "piped",
  });
  
  const { stdout } = await command.output();
  return new TextDecoder().decode(stdout).trim();
}

/**
 * Check if a command exists
 */
async function commandExists(cmd: string): Promise<boolean> {
  try {
    await exec("which", [cmd]);
    return true;
  } catch {
    return false;
  }
}

/**
 * Get sesh session name for a directory
 */
function getSeshName(dir: string): string {
  const parts = dir.split("/");
  const name = parts[parts.length - 1] || "home";
  return name.replace(/[.:]/g, "_");
}

/**
 * Format session for display
 */
function formatSession(session: ClaudeSession): string {
  const date = new Date(session.timestamp).toLocaleString();
  const icon = session.gitBranch ? "🔸" : "📁";
  const status = session.status === "active" ? "🟢" : "";
  const message = session.summary || session.lastMessage || "No messages";
  
  return `${icon} ${status} [${date}] ${getSeshName(session.cwd)} - ${message.slice(0, 50)}... | ${session.id} | ${session.cwd}`;
}

/**
 * Simple selection for non-TTY environments
 */
async function simpleSelectSession(sessions: ClaudeSession[]): Promise<SessionSelection | null> {
  if (sessions.length === 0) {
    console.log("No sessions found");
    return null;
  }
  
  // Display sessions with numbers
  console.log("\nAvailable Claude Sessions:\n");
  sessions.forEach((session, index) => {
    const date = new Date(session.timestamp).toLocaleString();
    const icon = session.gitBranch ? "🔸" : "📁";
    const message = session.summary || session.lastMessage || "No messages";
    const shortMessage = message.length > 50 ? message.slice(0, 50) + "..." : message;
    const seshName = getSeshName(session.cwd);
    
    console.log(`${index + 1}. ${icon} [${date}] ${seshName}`);
    console.log(`   ${shortMessage}`);
    console.log(`   ID: ${session.id.slice(0, 8)}...\n`);
  });
  
  // Prompt for selection
  const input = prompt("Enter session number (or 'q' to quit): ");
  
  if (!input || input.toLowerCase() === 'q') {
    return null;
  }
  
  const index = parseInt(input) - 1;
  if (isNaN(index) || index < 0 || index >= sessions.length) {
    console.log(colors.red("Invalid selection"));
    return null;
  }
  
  const session = sessions[index];
  
  // Show action menu
  console.log("\nChoose action:");
  console.log("1. Resume Session");
  console.log("2. View Conversation");
  console.log("3. Export to Markdown");
  console.log("4. Delete Session");
  console.log("5. Cancel\n");
  
  const actionInput = prompt("Enter action number: ");
  
  if (!actionInput) return null;
  
  const actionMap: { [key: string]: SessionSelection["action"] } = {
    "1": "resume",
    "2": "view",
    "3": "export",
    "4": "delete",
    "5": "cancel",
  };
  
  const action = actionMap[actionInput];
  if (!action) {
    console.log(colors.red("Invalid action"));
    return null;
  }
  
  return { session, action };
}

/**
 * Select session using Cliffy (requires TTY)
 */
async function selectSession(sessions: ClaudeSession[]): Promise<SessionSelection | null> {
  if (sessions.length === 0) {
    console.log("No sessions found");
    return null;
  }
  
  // Create options for Select prompt
  const options = sessions.map(session => {
    const date = new Date(session.timestamp).toLocaleString();
    const icon = session.gitBranch ? "🔸" : "📁";
    const status = session.status === "active" ? "🟢" : "";
    const message = session.summary || session.lastMessage || "No messages";
    const shortMessage = message.length > 50 ? message.slice(0, 50) + "..." : message;
    const seshName = getSeshName(session.cwd);
    
    return {
      name: `${icon} ${status} [${date}] ${seshName} - ${shortMessage}`,
      value: session.id,
      // Store the full session object in a custom property
      session: session,
    };
  });
  
  try {
    // Clean terminal state before prompt
    cleanTerminalState();
    
    // Use Cliffy Select prompt with search
    const selectedId = await Select.prompt({
      message: "Select Claude session:",
      options: options,
      search: true,
      searchLabel: "Search sessions",
      maxRows: 15,
    });
    
    // Clean terminal state after prompt
    cleanTerminalState();
    
    if (!selectedId) return null;
    
    // Find the selected session
    const session = sessions.find(s => s.id === selectedId);
    if (!session) return null;
    
    // Show action menu
    const action = await Select.prompt({
      message: "Choose action:",
      options: [
        { name: "Resume Session", value: "resume" },
        { name: "View Conversation", value: "view" },
        { name: "Export to Markdown", value: "export" },
        { name: "Delete Session", value: "delete" },
        { name: "Cancel", value: "cancel" },
      ],
    });
    
    return { session, action: action as SessionSelection["action"] };
  } catch (error) {
    // User cancelled (Ctrl+C)
    if (error instanceof Error && error.message.includes("Cancelled")) {
      return null;
    }
    throw error;
  }
}

/**
 * Display sessions in a table
 */
function displaySessionsTable(sessions: ClaudeSession[]): void {
  const table = new Table()
    .header(["Icon", "Status", "Date", "Directory", "Summary", "ID"])
    .border(true);
  
  for (const session of sessions) {
    const date = new Date(session.timestamp).toLocaleString();
    const icon = session.gitBranch ? "🔸" : "📁";
    const status = session.status === "active" ? "🟢" : "⚪";
    const message = session.summary || session.lastMessage || "No messages";
    const shortMessage = message.length > 50 ? message.slice(0, 50) + "..." : message;
    const seshName = getSeshName(session.cwd);
    
    table.push([
      icon,
      status,
      date,
      seshName,
      shortMessage,
      session.id.slice(0, 8) + "...",
    ]);
  }
  
  table.render();
}

/**
 * Connect to tmux/sesh session and resume Claude
 */
async function connectAndResume(session: ClaudeSession): Promise<void> {
  const seshName = getSeshName(session.cwd);
  const windowName = `claude-${session.id.slice(0, 8)}`;
  
  console.log(colors.cyan(`📍 Resuming session in ${session.cwd}`));
  console.log(colors.blue(`🏷️ Sesh name: ${seshName}`));
  console.log(colors.gray(`🆔 Session ID: ${session.id.slice(0, 8)}...`));
  
  // Check if we're in tmux
  const inTmux = Deno.env.get("TMUX") !== undefined;
  
  // Option to run without tmux
  const useTmux = await commandExists("tmux") && (inTmux || Deno.stdout.isTerminal());
  
  if (!useTmux) {
    // Direct execution without tmux
    console.log(colors.yellow("Running Claude directly (no tmux)..."));
    const cmd = new Deno.Command("claude", {
      args: ["--resume", session.id],
      cwd: session.cwd,
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    });
    
    const { code } = await cmd.output();
    if (code !== 0) {
      console.error(colors.red(`Failed to resume session (exit code: ${code})`));
    }
    return;
  }
  
  // Check if tmux session exists
  let sessionExists = false;
  try {
    await exec("tmux", ["has-session", "-t", seshName]);
    sessionExists = true;
  } catch {
    sessionExists = false;
  }
  
  if (sessionExists) {
    if (inTmux) {
      // Create new window in existing session
      await exec("tmux", ["new-window", "-a", "-t", seshName, "-c", session.cwd, "-n", windowName]);
      await exec("tmux", ["send-keys", "-t", `${seshName}:${windowName}`, `claude --resume ${session.id}`, "C-m"]);
      // Switch to the new window instead of switching sessions
      await exec("tmux", ["select-window", "-t", `${seshName}:${windowName}`]);
      console.log(colors.green(`✓ Created new window in session ${seshName}`));
    } else {
      // Create window and attach
      await exec("tmux", ["new-window", "-a", "-t", seshName, "-c", session.cwd, "-n", windowName]);
      await exec("tmux", ["send-keys", "-t", `${seshName}:${windowName}`, `claude --resume ${session.id}`, "C-m"]);
      
      // Use exec to replace current process when attaching
      const attachCmd = new Deno.Command("tmux", {
        args: ["attach-session", "-t", seshName],
        stdin: "inherit",
        stdout: "inherit",
        stderr: "inherit",
      });
      await attachCmd.output();
    }
  } else {
    // Create new session
    await exec("tmux", ["new-session", "-d", "-s", seshName, "-c", session.cwd, "-n", windowName]);
    await exec("tmux", ["send-keys", "-t", `${seshName}:${windowName}`, `claude --resume ${session.id}`, "C-m"]);
    
    if (inTmux) {
      // Switch to the new session
      console.log(colors.yellow("Please switch to the new session manually with:"));
      console.log(colors.cyan(`  tmux switch-client -t ${seshName}`));
    } else {
      // Attach to the new session
      const attachCmd = new Deno.Command("tmux", {
        args: ["attach-session", "-t", seshName],
        stdin: "inherit",
        stdout: "inherit",
        stderr: "inherit",
      });
      await attachCmd.output();
    }
  }
}

/**
 * View session conversation
 */
async function viewSession(session: ClaudeSession): Promise<void> {
  const content = await claude.exportSession(session.id, "markdown");
  
  // Check if we have a TTY and can use a pager
  const hasTty = Deno.stdout.isTerminal();
  const hasLess = await commandExists("less");
  const hasGum = await commandExists("gum");
  
  if (hasTty && hasGum) {
    // Try gum pager
    try {
      const pager = new Deno.Command("gum", {
        args: ["pager"],
        stdin: "piped",
      });
      
      const process = pager.spawn();
      const writer = process.stdin.getWriter();
      await writer.write(new TextEncoder().encode(content));
      await writer.close();
      await process.status;
      return;
    } catch {
      // Fall through to alternatives
    }
  }
  
  if (hasTty && hasLess) {
    // Use less as fallback
    const pager = new Deno.Command("less", {
      args: ["-R"], // Allow ANSI colors
      stdin: "piped",
    });
    
    const process = pager.spawn();
    const writer = process.stdin.getWriter();
    await writer.write(new TextEncoder().encode(content));
    await writer.close();
    await process.status;
  } else {
    // No pager available or no TTY, just output to stdout
    console.log(content);
  }
}

/**
 * Export session
 */
async function exportSession(session: ClaudeSession, format: ExportFormat = "markdown"): Promise<void> {
  const content = await claude.exportSession(session.id, format as any);
  const filename = `claude-session-${session.id.slice(0, 8)}-${Date.now()}.${format === "markdown" ? "md" : format}`;
  
  await Deno.writeTextFile(filename, content);
  console.log(`✅ Exported to ${filename}`);
}

/**
 * Main CLI
 */
async function main() {
  // Parse arguments
  const flags = parse(Deno.args, {
    boolean: ["help", "list", "zoxide", "no-tmux", "simple", "debug"],
    string: ["resume", "view", "export", "delete", "search"],
    alias: { h: "help", l: "list", r: "resume", v: "view", e: "export", d: "delete", s: "search" },
  });
  
  // Detect if running as compiled binary or from source
  // When compiled, Deno.execPath() will be the binary itself, not the deno executable
  const execPath = Deno.execPath();
  const isCompiled = !execPath.includes("deno") || execPath.endsWith("claude-manager");
  const programName = isCompiled ? "claude-manager" : "deno run --allow-all claude-session-manager.ts";
  
  // Show help
  if (flags.help) {
    console.log(`
Claude Session Manager${isCompiled ? "" : " - Deno TypeScript Implementation"}

Usage: ${programName} [OPTIONS]

Options:
  -h, --help          Show this help message
  -i, --interactive   Launch interactive browser with rich UI
  -l, --list          List all sessions in a table
  -r, --resume ID     Resume specific session
  -v, --view ID       View session conversation
  -e, --export ID     Export session to markdown
  -d, --delete ID     Delete session
  -s, --search TERM   Search sessions
  --simple            Use simple text-based selection (no interactive UI)
  --no-tmux           Run without tmux integration
  --zoxide            Sort by zoxide frecency
  --debug             Show debug information for troubleshooting

Interactive Mode Keys:
  ↑/↓ or j/k    Navigate sessions
  Enter         View conversation
  r             Resume session
  e             Export session
  d             Delete session
  /             Search
  ESC or q      Quit

Examples:
  # Interactive selection
  ${programName}
  
  # List all sessions
  ${programName} --list
  
  # Resume specific session
  ${programName} --resume abc123
  
  # Search sessions
  ${programName} --search "typescript"
  
  # Run without tmux
  ${programName} --no-tmux --resume abc123
  
  # Force simple mode
  CLAUDE_MANAGER_SIMPLE=true ${programName}
  
  # Debug TTY detection
  ${programName} --debug
`);
    Deno.exit(0);
  }
  
  // Get all sessions
  let sessions = await claude.listSessions();
  
  // Apply search filter if provided
  if (flags.search) {
    const searchTerm = flags.search.toLowerCase();
    sessions = sessions.filter(s => 
      s.lastMessage?.toLowerCase().includes(searchTerm) ||
      s.summary?.toLowerCase().includes(searchTerm) ||
      s.cwd.toLowerCase().includes(searchTerm)
    );
  }
  
  // Sort by zoxide if requested
  if (flags.zoxide && await commandExists("zoxide")) {
    // Get zoxide rankings
    const zoxideOutput = await exec("zoxide", ["query", "-l"]);
    const rankings = zoxideOutput.split("\n");
    
    sessions.sort((a, b) => {
      const aRank = rankings.indexOf(a.cwd);
      const bRank = rankings.indexOf(b.cwd);
      if (aRank === -1 && bRank === -1) return 0;
      if (aRank === -1) return 1;
      if (bRank === -1) return -1;
      return aRank - bRank;
    });
  }
  
  // Handle specific actions
  if (flags.resume) {
    const session = sessions.find(s => s.id.includes(flags.resume as string));
    if (session) {
      await connectAndResume(session);
    } else {
      console.error(`Session ${flags.resume} not found`);
      Deno.exit(1);
    }
  } else if (flags.view) {
    const session = sessions.find(s => s.id.includes(flags.view as string));
    if (session) {
      await viewSession(session);
    } else {
      console.error(`Session ${flags.view} not found`);
      Deno.exit(1);
    }
  } else if (flags.export) {
    const session = sessions.find(s => s.id.includes(flags.export as string));
    if (session) {
      await exportSession(session);
    } else {
      console.error(`Session ${flags.export} not found`);
      Deno.exit(1);
    }
  } else if (flags.delete) {
    const success = await claude.deleteSession(flags.delete);
    if (success) {
      console.log(`✅ Session ${flags.delete} deleted`);
    } else {
      console.error(`Failed to delete session ${flags.delete}`);
      Deno.exit(1);
    }
  } else if (flags.list) {
    // List all sessions in a table
    displaySessionsTable(sessions);
  } else if (flags.interactive || (!Object.keys(flags).filter(k => k !== "_").length && Deno.stdin.isTerminal())) {
    // Launch interactive mode when explicitly requested or when no args provided and TTY available
    const interactive = new InteractiveMode(claude);
    await interactive.run();
  } else {
    // Interactive selection - check if we can use Cliffy or need simple mode
    const stdinTty = Deno.stdin.isTerminal();
    const stdoutTty = Deno.stdout.isTerminal();
    const termEnv = Deno.env.get("TERM") || "unknown";
    const forceSimple = Deno.env.get("CLAUDE_MANAGER_SIMPLE") === "true";
    
    // More robust TTY detection
    const hasTty = stdinTty && stdoutTty && termEnv !== "dumb";
    const useSimple = flags.simple || forceSimple || !hasTty;
    
    // Debug mode
    if (flags.debug) {
      console.log(colors.gray("=== Debug Info ==="));
      console.log(colors.gray(`TTY stdin: ${stdinTty}`));
      console.log(colors.gray(`TTY stdout: ${stdoutTty}`));
      console.log(colors.gray(`TERM: ${termEnv}`));
      console.log(colors.gray(`Force simple: ${forceSimple}`));
      console.log(colors.gray(`Use simple mode: ${useSimple}`));
      console.log(colors.gray("==================\n"));
    }
    
    if (useSimple && !flags.simple && !forceSimple) {
      console.log(colors.yellow("Note: Using simple selection mode (no TTY detected)"));
      if (flags.debug) {
        console.log(colors.gray(`Reason: stdin=${stdinTty}, stdout=${stdoutTty}, TERM=${termEnv}`));
      }
    }
    
    let selection: SessionSelection | null = null;
    
    if (!useSimple) {
      try {
        selection = await selectSession(sessions);
      } catch (error) {
        console.log(colors.yellow("Interactive mode failed, falling back to simple mode"));
        if (flags.debug) {
          console.error(colors.red(`Error: ${error}`));
        }
        selection = await simpleSelectSession(sessions);
      }
    } else {
      selection = await simpleSelectSession(sessions);
    }
    
    if (selection) {
      switch (selection.action) {
        case "resume":
          await connectAndResume(selection.session);
          break;
        case "view":
          await viewSession(selection.session);
          break;
        case "export":
          await exportSession(selection.session);
          break;
        case "delete":
          await claude.deleteSession(selection.session.id);
          console.log(colors.green("✅ Session deleted"));
          break;
        case "cancel":
          console.log(colors.gray("Cancelled"));
          break;
      }
    }
  }
}

// Run main
if (import.meta.main) {
  main().catch(console.error);
}