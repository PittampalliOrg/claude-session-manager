/**
 * Claude CLI Wrapper
 * 
 * This module provides a TypeScript wrapper around the Claude Code CLI,
 * using the SDK types while executing commands through the CLI instead
 * of direct API calls.
 */

import type {
  ClaudeSession,
  SessionFileEntry,
  CommandResult,
  ClaudeCodeOptions,
  PermissionMode,
} from "./claude-types.ts";

/**
 * Wrapper class for Claude Code CLI operations
 */
export class ClaudeCliWrapper {
  private claudeCommand: string;
  
  constructor(claudeCommand = "claude") {
    this.claudeCommand = claudeCommand;
  }

  /**
   * Execute a command and return the result
   */
  private async executeCommand(
    cmd: string,
    args: string[] = [],
    options?: { cwd?: string }
  ): Promise<CommandResult> {
    const command = new Deno.Command(cmd, {
      args,
      stdout: "piped",
      stderr: "piped",
      stdin: "piped",
      cwd: options?.cwd,
    });

    const { code, stdout, stderr } = await command.output();
    
    return {
      success: code === 0,
      stdout: new TextDecoder().decode(stdout),
      stderr: new TextDecoder().decode(stderr),
      code,
    };
  }

  /**
   * Start a new Claude session
   */
  async startSession(options?: {
    prompt?: string;
    cwd?: string;
    systemPrompt?: string;
    permissionMode?: PermissionMode;
    maxTurns?: number;
  }): Promise<{ sessionId: string; process: Deno.ChildProcess }> {
    const args: string[] = [];
    
    if (options?.systemPrompt) {
      args.push("--system-prompt", options.systemPrompt);
    }
    
    if (options?.permissionMode) {
      args.push("--permission-mode", options.permissionMode);
    }
    
    if (options?.maxTurns) {
      args.push("--max-turns", options.maxTurns.toString());
    }
    
    if (options?.prompt) {
      args.push(options.prompt);
    }

    const command = new Deno.Command(this.claudeCommand, {
      args,
      cwd: options?.cwd,
      stdout: "piped",
      stderr: "piped",
      stdin: "piped",
    });

    const process = command.spawn();
    
    // Extract session ID from initial output
    // This would need to parse the actual Claude CLI output
    const sessionId = crypto.randomUUID();
    
    return { sessionId, process };
  }

  /**
   * Resume an existing Claude session
   */
  async resumeSession(sessionId: string, cwd?: string): Promise<CommandResult> {
    return this.executeCommand(
      this.claudeCommand,
      ["--resume", sessionId],
      { cwd }
    );
  }

  /**
   * List all available sessions
   */
  async listSessions(): Promise<ClaudeSession[]> {
    const homeDir = Deno.env.get("HOME") || "";
    const projectsDir = `${homeDir}/.claude/projects`;
    
    const sessions: ClaudeSession[] = [];
    
    try {
      // Walk through all JSONL files in projects directory
      for await (const entry of Deno.readDir(projectsDir)) {
        if (entry.isDirectory) {
          const subDir = `${projectsDir}/${entry.name}`;
          for await (const file of Deno.readDir(subDir)) {
            if (file.name.endsWith(".jsonl")) {
              const session = await this.parseSessionFile(
                `${subDir}/${file.name}`
              );
              if (session) {
                sessions.push(session);
              }
            }
          }
        }
      }
    } catch (error) {
      console.error("Error reading sessions:", error);
    }
    
    return sessions;
  }

  /**
   * Parse a session JSONL file
   */
  private async parseSessionFile(filePath: string): Promise<ClaudeSession | null> {
    try {
      const content = await Deno.readTextFile(filePath);
      const lines = content.split("\n").filter(line => line.trim());
      
      if (lines.length === 0) return null;
      
      // Extract session ID from filename
      const filename = filePath.split("/").pop() || "";
      const sessionId = filename.replace(".jsonl", "");
      
      // Parse first line for metadata
      const firstEntry = JSON.parse(lines[0]) as SessionFileEntry;
      
      // Count messages
      let messageCount = 0;
      let lastMessage = "";
      let summary = "";
      
      for (const line of lines) {
        try {
          const entry = JSON.parse(line) as SessionFileEntry;
          // Check for both old and new formats
          if (entry.type === "message" || entry.type === "user" || entry.type === "assistant") {
            // Skip meta messages
            if ((entry as any).isMeta) continue;
            
            messageCount++;
            
            // Extract user messages for lastMessage
            const role = entry.message?.role || entry.type;
            if (role === "user") {
              const content = entry.message?.content;
              // Skip command messages
              if (typeof content === "string") {
                if (!content.includes("<command-name>") && !content.includes("<local-command-stdout>")) {
                  lastMessage = content;
                }
              } else if (Array.isArray(content)) {
                const textContent = content[0]?.text || "";
                if (textContent && !textContent.includes("<command-name>")) {
                  lastMessage = textContent;
                }
              }
            }
          } else if (entry.type === "summary") {
            summary = entry.summary || "";
          }
        } catch {
          // Skip malformed lines
        }
      }
      
      return {
        id: sessionId,
        timestamp: firstEntry.timestamp || new Date().toISOString(),
        cwd: firstEntry.cwd || Deno.cwd(),
        gitBranch: firstEntry.gitBranch,
        status: "completed",
        messageCount,
        lastMessage: lastMessage.slice(0, 100),
        summary,
      };
    } catch (error) {
      console.error(`Error parsing session file ${filePath}:`, error);
      return null;
    }
  }

  /**
   * Export a session to various formats
   */
  async exportSession(
    sessionId: string,
    format: 'markdown' | 'json' = 'markdown'
  ): Promise<string> {
    const homeDir = Deno.env.get("HOME") || "";
    const projectsDir = `${homeDir}/.claude/projects`;
    
    // Find session file
    let sessionFile = "";
    for await (const entry of Deno.readDir(projectsDir)) {
      if (entry.isDirectory) {
        const subDir = `${projectsDir}/${entry.name}`;
        for await (const file of Deno.readDir(subDir)) {
          if (file.name.includes(sessionId)) {
            sessionFile = `${subDir}/${file.name}`;
            break;
          }
        }
      }
      if (sessionFile) break;
    }
    
    if (!sessionFile) {
      throw new Error(`Session ${sessionId} not found`);
    }
    
    const content = await Deno.readTextFile(sessionFile);
    const lines = content.split("\n").filter(line => line.trim());
    
    if (format === 'json') {
      return JSON.stringify(lines.map(l => JSON.parse(l)), null, 2);
    }
    
    // Format as markdown
    let markdown = `# Claude Session ${sessionId}\n\n`;
    
    // Parse all entries first
    let metadata: any = {};
    const messages: any[] = [];
    
    for (const line of lines) {
      try {
        const entry = JSON.parse(line) as SessionFileEntry;
        if (entry.type === "metadata") {
          metadata = entry;
        } else if ((entry.type === "message" || entry.type === "user" || entry.type === "assistant")) {
          // Skip meta messages
          if (!(entry as any).isMeta) {
            messages.push(entry);
          }
        } else if (entry.type === "summary") {
          metadata.summary = entry.summary;
        }
      } catch {
        // Skip malformed lines
      }
    }
    
    // Add session info
    if (metadata.cwd || metadata.gitBranch) {
      markdown += `## Session Info\n\n`;
      if (metadata.cwd) markdown += `- **Directory:** ${metadata.cwd}\n`;
      if (metadata.gitBranch) markdown += `- **Git Branch:** ${metadata.gitBranch}\n`;
      if (metadata.timestamp) markdown += `- **Started:** ${new Date(metadata.timestamp).toLocaleString()}\n`;
      markdown += `\n`;
    }
    
    // Add summary if available
    if (metadata.summary) {
      markdown += `## Summary\n\n${metadata.summary}\n\n`;
    }
    
    // Add conversation
    if (messages.length > 0) {
      markdown += `## Conversation\n\n`;
      for (const entry of messages) {
        const timestamp = new Date(entry.timestamp).toLocaleString();
        // Handle both old and new formats
        const role = entry.message?.role || entry.type;
        const roleIcon = role === 'user' ? '👤' : '🤖';
        
        markdown += `### ${roleIcon} ${role.charAt(0).toUpperCase() + role.slice(1)} (${timestamp})\n\n`;
        
        // Handle different content types
        const content = entry.message?.content;
        if (typeof content === "string") {
          markdown += `${content}\n\n`;
        } else if (Array.isArray(content)) {
          for (const item of content) {
            if (item.type === "text") {
              markdown += `${item.text}\n\n`;
            } else if (item.type === "tool_use") {
              markdown += `🔧 **Tool:** ${item.name}\n`;
              if (item.input) {
                markdown += `\`\`\`json\n${JSON.stringify(item.input, null, 2)}\n\`\`\`\n\n`;
              }
            } else if (item.type === "tool_result") {
              markdown += `📤 **Tool Result:**\n`;
              markdown += `\`\`\`\n${item.content || 'No output'}\n\`\`\`\n\n`;
            }
          }
        }
        
        markdown += `---\n\n`;
      }
    } else {
      markdown += `## Conversation\n\n*No messages in this session*\n\n`;
    }
    
    return markdown;
  }

  /**
   * Delete a session
   */
  async deleteSession(sessionId: string): Promise<boolean> {
    const homeDir = Deno.env.get("HOME") || "";
    const projectsDir = `${homeDir}/.claude/projects`;
    
    try {
      for await (const entry of Deno.readDir(projectsDir)) {
        if (entry.isDirectory) {
          const subDir = `${projectsDir}/${entry.name}`;
          for await (const file of Deno.readDir(subDir)) {
            if (file.name.includes(sessionId)) {
              await Deno.remove(`${subDir}/${file.name}`);
              return true;
            }
          }
        }
      }
    } catch (error) {
      console.error("Error deleting session:", error);
    }
    
    return false;
  }

  /**
   * Stream interaction with Claude CLI
   */
  async *streamInteraction(
    sessionId: string,
    input: AsyncIterable<string>,
    cwd?: string
  ): AsyncGenerator<string, void> {
    const command = new Deno.Command(this.claudeCommand, {
      args: ["--resume", sessionId],
      stdout: "piped",
      stderr: "piped",
      stdin: "piped",
      cwd,
    });

    const process = command.spawn();
    const writer = process.stdin.getWriter();
    const reader = process.stdout.getReader();
    
    // Write input in background
    (async () => {
      for await (const line of input) {
        await writer.write(new TextEncoder().encode(line + "\n"));
      }
      await writer.close();
    })();
    
    // Read output
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      yield decoder.decode(value);
    }
  }
}