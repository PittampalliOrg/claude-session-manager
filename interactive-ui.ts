/**
 * Interactive UI components for Claude Session Manager
 * Provides rich terminal user interface with search, navigation, and viewing capabilities
 */

import { Table } from "@cliffy/table";
import { Select, Input, Confirm } from "@cliffy/prompt";
import { colors } from "@cliffy/ansi/colors";
import type { ClaudeSession } from "./claude-types.ts";

// ANSI escape codes for terminal control
const CLEAR_SCREEN = "\x1b[2J\x1b[H";
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";
const SAVE_CURSOR = "\x1b[s";
const RESTORE_CURSOR = "\x1b[u";

/**
 * Format a timestamp for display
 */
function formatDate(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
  const diffMins = Math.floor(diffMs / (1000 * 60));
  
  if (diffMins < 60) {
    return colors.green(`${diffMins}m ago`);
  } else if (diffHours < 24) {
    return colors.yellow(`${diffHours}h ago`);
  } else if (diffDays < 7) {
    return colors.cyan(`${diffDays}d ago`);
  } else {
    return colors.gray(date.toLocaleDateString());
  }
}

/**
 * Format directory path for display
 */
function formatDirectory(cwd: string): string {
  const home = Deno.env.get("HOME") || "";
  const shortened = cwd.replace(home, "~");
  const parts = shortened.split("/");
  const lastTwo = parts.slice(-2).join("/");
  return lastTwo.length > 30 ? "..." + lastTwo.slice(-27) : lastTwo;
}

/**
 * Format message preview
 */
function formatMessagePreview(message: string | undefined, maxLength = 50): string {
  if (!message) return colors.gray("(no messages)");
  
  const cleaned = message
    .replace(/\n/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  
  if (cleaned.length <= maxLength) {
    return cleaned;
  }
  
  return cleaned.slice(0, maxLength - 3) + "...";
}

/**
 * Get status icon for session
 */
function getStatusIcon(session: ClaudeSession): string {
  const hasMessages = session.messageCount > 0;
  const isRecent = new Date().getTime() - new Date(session.timestamp).getTime() < 3600000; // 1 hour
  
  if (isRecent && hasMessages) {
    return "🔥"; // Hot/active
  } else if (hasMessages) {
    return "📝"; // Has content
  } else {
    return "📁"; // Empty/new
  }
}

/**
 * Interactive session browser with rich table display
 */
export class InteractiveSessionBrowser {
  private sessions: ClaudeSession[] = [];
  private filteredSessions: ClaudeSession[] = [];
  private searchTerm = "";
  private selectedIndex = 0;
  private pageSize = 15;
  private currentPage = 0;
  
  constructor(sessions: ClaudeSession[]) {
    this.sessions = sessions;
    this.filteredSessions = sessions;
  }
  
  /**
   * Apply search filter to sessions
   */
  private applyFilter(term: string) {
    this.searchTerm = term.toLowerCase();
    
    if (!this.searchTerm) {
      this.filteredSessions = this.sessions;
      return;
    }
    
    this.filteredSessions = this.sessions.filter(session => {
      const searchableText = [
        session.id,
        session.cwd,
        session.gitBranch || "",
        session.summary || "",
        session.lastMessage || "",
      ].join(" ").toLowerCase();
      
      return searchableText.includes(this.searchTerm);
    });
    
    this.currentPage = 0;
    this.selectedIndex = 0;
  }
  
  /**
   * Render the session table
   */
  private renderTable(): string {
    const start = this.currentPage * this.pageSize;
    const end = Math.min(start + this.pageSize, this.filteredSessions.length);
    const pageSessions = this.filteredSessions.slice(start, end);
    
    if (pageSessions.length === 0) {
      return colors.yellow("\n  No sessions found matching your search.\n");
    }
    
    // Create table data
    const tableData: string[][] = [];
    
    // Add header
    tableData.push([
      colors.bold.cyan(""),
      colors.bold.cyan("Time"),
      colors.bold.cyan("Directory"),
      colors.bold.cyan("Branch"),
      colors.bold.cyan("Msgs"),
      colors.bold.cyan("Preview"),
      colors.bold.cyan("ID"),
    ]);
    
    // Add sessions
    pageSessions.forEach((session, index) => {
      const isSelected = index === this.selectedIndex;
      const row = [
        getStatusIcon(session),
        formatDate(session.timestamp),
        colors.blue(formatDirectory(session.cwd)),
        session.gitBranch ? colors.green(session.gitBranch) : colors.gray("-"),
        session.messageCount > 0 
          ? colors.yellow(session.messageCount.toString())
          : colors.gray("0"),
        formatMessagePreview(session.lastMessage || session.summary),
        colors.gray(session.id.slice(0, 8)),
      ];
      
      // Highlight selected row
      if (isSelected) {
        tableData.push(row.map(cell => colors.bgBlue.white(` ${cell} `)));
      } else {
        tableData.push(row);
      }
    });
    
    const table = new Table(...tableData);
    table.padding(1);
    table.border(true);
    table.align("left");
    
    return table.toString();
  }
  
  /**
   * Render the full interface
   */
  private render() {
    console.log(CLEAR_SCREEN);
    
    // Header
    console.log(colors.bold.magenta("\n🚀 Claude Session Manager - Interactive Browser\n"));
    
    // Search bar
    if (this.searchTerm) {
      console.log(colors.green(`  🔍 Search: ${this.searchTerm}\n`));
    } else {
      console.log(colors.gray("  Press '/' to search, arrow keys to navigate, Enter to view\n"));
    }
    
    // Session table
    console.log(this.renderTable());
    
    // Footer with stats and controls
    const totalSessions = this.filteredSessions.length;
    const currentSession = this.filteredSessions[this.selectedIndex];
    
    console.log(colors.gray("─".repeat(80)));
    console.log(
      colors.gray(`  Sessions: ${totalSessions} | `) +
      colors.gray(`Page: ${this.currentPage + 1}/${Math.ceil(totalSessions / this.pageSize)} | `) +
      colors.cyan("Keys: ") +
      colors.white("↑↓ Navigate | Enter View | r Resume | d Delete | e Export | q Quit")
    );
    
    if (currentSession) {
      console.log(colors.gray(`  Selected: ${currentSession.cwd} (${currentSession.id.slice(0, 8)})`));
    }
  }
  
  /**
   * Handle keyboard input
   */
  private async handleKeypress(): Promise<string | null> {
    const decoder = new TextDecoder();
    const buffer = new Uint8Array(10);
    
    // Set raw mode for single keypress reading
    await Deno.stdin.setRaw(true, { cbreak: true });
    const n = await Deno.stdin.read(buffer);
    await Deno.stdin.setRaw(false);
    
    if (n === null) return null;
    
    const input = decoder.decode(buffer.subarray(0, n));
    return input;
  }
  
  /**
   * Interactive search mode
   */
  private async searchMode(): Promise<void> {
    console.log(SAVE_CURSOR);
    console.log("\n" + colors.cyan("Search: "));
    
    const searchInput = await Input.prompt({
      message: "",
      default: this.searchTerm,
    });
    
    this.applyFilter(searchInput);
    console.log(RESTORE_CURSOR);
  }
  
  /**
   * Main interaction loop
   */
  async browse(): Promise<{ action: string; session?: ClaudeSession }> {
    // Initial render
    this.render();
    
    while (true) {
      const key = await this.handleKeypress();
      
      if (!key) continue;
      
      // Handle keys
      switch (key) {
        case "\x1b[A": // Up arrow
        case "k":
          if (this.selectedIndex > 0) {
            this.selectedIndex--;
          } else if (this.currentPage > 0) {
            this.currentPage--;
            this.selectedIndex = this.pageSize - 1;
          }
          break;
          
        case "\x1b[B": // Down arrow  
        case "j":
          if (this.selectedIndex < Math.min(this.pageSize - 1, this.filteredSessions.length - 1)) {
            this.selectedIndex++;
          } else if ((this.currentPage + 1) * this.pageSize < this.filteredSessions.length) {
            this.currentPage++;
            this.selectedIndex = 0;
          }
          break;
          
        case "\x1b[D": // Left arrow - previous page
        case "h":
          if (this.currentPage > 0) {
            this.currentPage--;
            this.selectedIndex = 0;
          }
          break;
          
        case "\x1b[C": // Right arrow - next page
        case "l":
          if ((this.currentPage + 1) * this.pageSize < this.filteredSessions.length) {
            this.currentPage++;
            this.selectedIndex = 0;
          }
          break;
          
        case "\r": // Enter - view session
        case "\n":
          const selected = this.filteredSessions[this.currentPage * this.pageSize + this.selectedIndex];
          if (selected) {
            return { action: "view", session: selected };
          }
          break;
          
        case "r": // Resume session
        case "R":
          const resumeSession = this.filteredSessions[this.currentPage * this.pageSize + this.selectedIndex];
          if (resumeSession) {
            return { action: "resume", session: resumeSession };
          }
          break;
          
        case "e": // Export session
        case "E":
          const exportSession = this.filteredSessions[this.currentPage * this.pageSize + this.selectedIndex];
          if (exportSession) {
            return { action: "export", session: exportSession };
          }
          break;
          
        case "d": // Delete session
        case "D":
          const deleteSession = this.filteredSessions[this.currentPage * this.pageSize + this.selectedIndex];
          if (deleteSession) {
            console.log(CLEAR_SCREEN);
            const confirm = await Confirm.prompt({
              message: `Delete session ${deleteSession.id.slice(0, 8)} from ${formatDirectory(deleteSession.cwd)}?`,
              default: false,
            });
            if (confirm) {
              return { action: "delete", session: deleteSession };
            }
          }
          break;
          
        case "/": // Search
          await this.searchMode();
          break;
          
        case "\x1b": // ESC
        case "q": // Quit
        case "Q":
          return { action: "quit" };
          
        case "\x03": // Ctrl+C
          return { action: "quit" };
      }
      
      // Re-render after action
      this.render();
    }
  }
}

/**
 * Conversation viewer with scrolling and search
 */
export class ConversationViewer {
  private content: string[] = [];
  private currentLine = 0;
  private terminalHeight = 0;
  private searchTerm = "";
  private searchResults: number[] = [];
  private currentSearchIndex = 0;
  
  constructor(content: string) {
    this.content = content.split("\n");
    this.updateTerminalSize();
  }
  
  /**
   * Update terminal dimensions
   */
  private updateTerminalSize() {
    const size = Deno.consoleSize();
    this.terminalHeight = size.rows - 5; // Leave room for header and footer
  }
  
  /**
   * Render visible portion of content
   */
  private render() {
    console.log(CLEAR_SCREEN);
    
    // Header
    console.log(colors.bold.magenta("📖 Conversation Viewer\n"));
    
    // Show search if active
    if (this.searchTerm) {
      const resultInfo = this.searchResults.length > 0
        ? `(${this.currentSearchIndex + 1}/${this.searchResults.length})`
        : "(no results)";
      console.log(colors.green(`🔍 Search: ${this.searchTerm} ${resultInfo}\n`));
    }
    
    // Content area
    const endLine = Math.min(this.currentLine + this.terminalHeight, this.content.length);
    
    for (let i = this.currentLine; i < endLine; i++) {
      let line = this.content[i];
      
      // Highlight search results
      if (this.searchTerm && this.searchResults.includes(i)) {
        const regex = new RegExp(this.searchTerm, "gi");
        line = line.replace(regex, match => colors.bgYellow.black(match));
      }
      
      // Syntax highlighting for markdown
      if (line.startsWith("###")) {
        console.log(colors.bold.cyan(line));
      } else if (line.startsWith("##")) {
        console.log(colors.bold.magenta(line));
      } else if (line.startsWith("#")) {
        console.log(colors.bold.blue(line));
      } else if (line.startsWith("```")) {
        console.log(colors.gray(line));
      } else if (line.startsWith("- ")) {
        console.log(colors.yellow("• " + line.slice(2)));
      } else if (line.includes("Tool Use:") || line.includes("Tool Result:")) {
        console.log(colors.green(line));
      } else {
        console.log(line);
      }
    }
    
    // Fill remaining space
    const remainingLines = this.terminalHeight - (endLine - this.currentLine);
    for (let i = 0; i < remainingLines; i++) {
      console.log("");
    }
    
    // Footer
    const progress = Math.round((this.currentLine / Math.max(1, this.content.length - this.terminalHeight)) * 100);
    console.log(colors.gray("─".repeat(80)));
    console.log(
      colors.gray(`Line ${this.currentLine + 1}-${endLine} of ${this.content.length} (${progress}%) | `) +
      colors.cyan("Keys: ") +
      colors.white("↑↓ Scroll | / Search | n Next | N Prev | ESC Back | q Quit")
    );
  }
  
  /**
   * Search for term in content
   */
  private search(term: string) {
    this.searchTerm = term.toLowerCase();
    this.searchResults = [];
    
    if (!this.searchTerm) return;
    
    this.content.forEach((line, index) => {
      if (line.toLowerCase().includes(this.searchTerm)) {
        this.searchResults.push(index);
      }
    });
    
    if (this.searchResults.length > 0) {
      this.currentSearchIndex = 0;
      this.currentLine = Math.max(0, this.searchResults[0] - 5);
    }
  }
  
  /**
   * Jump to next search result
   */
  private nextSearchResult() {
    if (this.searchResults.length === 0) return;
    
    this.currentSearchIndex = (this.currentSearchIndex + 1) % this.searchResults.length;
    this.currentLine = Math.max(0, this.searchResults[this.currentSearchIndex] - 5);
  }
  
  /**
   * Jump to previous search result
   */
  private prevSearchResult() {
    if (this.searchResults.length === 0) return;
    
    this.currentSearchIndex = this.currentSearchIndex === 0 
      ? this.searchResults.length - 1 
      : this.currentSearchIndex - 1;
    this.currentLine = Math.max(0, this.searchResults[this.currentSearchIndex] - 5);
  }
  
  /**
   * Handle keyboard input
   */
  private async handleKeypress(): Promise<string | null> {
    const decoder = new TextDecoder();
    const buffer = new Uint8Array(10);
    
    await Deno.stdin.setRaw(true, { cbreak: true });
    const n = await Deno.stdin.read(buffer);
    await Deno.stdin.setRaw(false);
    
    if (n === null) return null;
    
    const input = decoder.decode(buffer.subarray(0, n));
    return input;
  }
  
  /**
   * Main view loop
   */
  async view(): Promise<void> {
    this.render();
    
    while (true) {
      const key = await this.handleKeypress();
      
      if (!key) continue;
      
      switch (key) {
        case "\x1b[A": // Up arrow
        case "k":
          if (this.currentLine > 0) {
            this.currentLine--;
          }
          break;
          
        case "\x1b[B": // Down arrow
        case "j":
          if (this.currentLine < this.content.length - this.terminalHeight) {
            this.currentLine++;
          }
          break;
          
        case "\x1b[5~": // Page Up
        case "u":
          this.currentLine = Math.max(0, this.currentLine - this.terminalHeight);
          break;
          
        case "\x1b[6~": // Page Down  
        case "d":
          this.currentLine = Math.min(
            this.content.length - this.terminalHeight,
            this.currentLine + this.terminalHeight
          );
          break;
          
        case "g": // Go to top
          this.currentLine = 0;
          break;
          
        case "G": // Go to bottom
          this.currentLine = Math.max(0, this.content.length - this.terminalHeight);
          break;
          
        case "/": // Search
          console.log(SAVE_CURSOR);
          console.log("\n" + colors.cyan("Search: "));
          const searchInput = await Input.prompt({
            message: "",
            default: this.searchTerm,
          });
          this.search(searchInput);
          console.log(RESTORE_CURSOR);
          break;
          
        case "n": // Next search result
          this.nextSearchResult();
          break;
          
        case "N": // Previous search result
          this.prevSearchResult();
          break;
          
        case "\x1b": // ESC - go back
        case "q": // Quit
        case "Q":
          return;
          
        case "\x03": // Ctrl+C
          Deno.exit(0);
      }
      
      this.render();
    }
  }
}

/**
 * Main interactive mode controller
 */
export class InteractiveMode {
  constructor(private wrapper: any) {}
  
  /**
   * Run the interactive interface
   */
  async run(): Promise<void> {
    try {
      // Hide cursor during interaction
      console.log(HIDE_CURSOR);
      
      while (true) {
        // Get all sessions
        const sessions = await this.wrapper.listSessions();
        
        if (sessions.length === 0) {
          console.log(colors.yellow("\nNo Claude sessions found.\n"));
          break;
        }
        
        // Create and run browser
        const browser = new InteractiveSessionBrowser(sessions);
        const result = await browser.browse();
        
        if (result.action === "quit") {
          break;
        }
        
        if (result.action === "view" && result.session) {
          // Get full conversation content
          const content = await this.wrapper.exportSession(result.session.id, "markdown");
          
          // Show in viewer
          const viewer = new ConversationViewer(content);
          await viewer.view();
          // After viewing, loop back to browser
          continue;
        }
        
        if (result.action === "resume" && result.session) {
          console.log(CLEAR_SCREEN);
          console.log(colors.green(`\n✅ Resuming session ${result.session.id.slice(0, 8)}...\n`));
          await this.wrapper.resumeSession(result.session.id);
          break;
        }
        
        if (result.action === "export" && result.session) {
          console.log(CLEAR_SCREEN);
          const format = await Select.prompt({
            message: "Export format:",
            options: [
              { name: "Markdown", value: "markdown" },
              { name: "JSON", value: "json" },
              { name: "Cancel", value: "cancel" },
            ],
          });
          
          if (format !== "cancel") {
            const content = await this.wrapper.exportSession(result.session.id, format);
            const filename = `claude-session-${result.session.id.slice(0, 8)}.${format === "json" ? "json" : "md"}`;
            await Deno.writeTextFile(filename, content);
            console.log(colors.green(`\n✅ Exported to ${filename}\n`));
            await new Promise(resolve => setTimeout(resolve, 2000));
          }
          continue;
        }
        
        if (result.action === "delete" && result.session) {
          await this.wrapper.deleteSession(result.session.id);
          console.log(colors.green(`\n✅ Deleted session ${result.session.id.slice(0, 8)}\n`));
          await new Promise(resolve => setTimeout(resolve, 1000));
          continue;
        }
      }
    } finally {
      // Show cursor again
      console.log(SHOW_CURSOR);
      console.log(CLEAR_SCREEN);
    }
  }
}