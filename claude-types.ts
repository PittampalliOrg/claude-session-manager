/**
 * Claude Code SDK Type Definitions and Interfaces
 * 
 * This module re-exports and extends the Claude Code SDK types
 * for use in our Deno-based session management system.
 */

// Import Claude Code SDK types
// Using npm: specifier for direct npm package import in Deno
import type {
  SDKMessage,
  SDKUserMessage,
  SDKAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  Options as ClaudeCodeOptions,
  PermissionMode,
  HookInput,
  HookJSONOutput,
  Query,
} from "npm:@anthropic-ai/claude-code@1.0.86";

// Re-export core types for convenience
export type {
  SDKMessage,
  SDKUserMessage,
  SDKAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  ClaudeCodeOptions,
  PermissionMode,
  HookInput,
  HookJSONOutput,
  Query,
};

/**
 * Extended session metadata that combines Claude Code SDK types
 * with our custom session management needs
 */
export interface ClaudeSession {
  // Core session info
  id: string;
  timestamp: string;
  cwd: string;
  
  // Git integration
  gitBranch?: string;
  gitStatus?: string;
  
  // Sesh/tmux integration
  seshName?: string;
  tmuxSession?: string;
  tmuxWindow?: string;
  
  // Claude Code specific
  model?: string;
  permissionMode?: PermissionMode;
  apiKeySource?: 'user' | 'project' | 'org' | 'temporary';
  
  // Session state
  status: 'active' | 'paused' | 'completed' | 'error';
  summary?: string;
  messageCount: number;
  lastMessage?: string;
  
  // MCP servers if any
  mcpServers?: Array<{
    name: string;
    status: string;
  }>;
}

/**
 * Base session entry fields
 */
interface BaseSessionEntry {
  timestamp: string;
  sessionId?: string;
  uuid?: string;
  parentUuid?: string | null;
  isMeta?: boolean;
  isSidechain?: boolean;
  userType?: string;
  cwd?: string;
  gitBranch?: string;
  version?: string;
  requestId?: string;
}

/**
 * Metadata entry for session initialization
 */
export interface MetadataEntry extends BaseSessionEntry {
  type: 'metadata';
}

/**
 * Summary entry for session summaries
 */
export interface SummaryEntry extends BaseSessionEntry {
  type: 'summary';
  summary: string;
}

/**
 * Wrapped message format (newer format)
 */
export interface WrappedMessageEntry extends BaseSessionEntry {
  type: 'message';
  message: {
    role: 'user' | 'assistant' | 'system';
    content: string | Array<{
      type: 'text' | 'tool_use' | 'tool_result';
      text?: string;
      content?: string;
      name?: string;
      id?: string;
      tool_use_id?: string;
      input?: any;
    }>;
  };
}

/**
 * Direct user message format (older format)
 */
export interface DirectUserEntry extends BaseSessionEntry {
  type: 'user';
  message: {
    role: 'user';
    content: string | Array<{
      type: 'text' | 'tool_result';
      text?: string;
      content?: string;
      tool_use_id?: string;
    }>;
  };
}

/**
 * Direct assistant message format (older format)
 */
export interface DirectAssistantEntry extends BaseSessionEntry {
  type: 'assistant';
  message: {
    id: string;
    type: 'message';
    role: 'assistant';
    model: string;
    content: Array<{
      type: 'text' | 'tool_use';
      text?: string;
      id?: string;
      name?: string;
      input?: any;
    }>;
    stop_reason?: string | null;
    stop_sequence?: string | null;
    usage?: {
      input_tokens: number;
      output_tokens: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
      cache_creation?: any;
      service_tier?: string;
    };
  };
  toolUseResult?: any;
}

/**
 * Union type for all session file entries
 */
export type SessionFileEntry = MetadataEntry | SummaryEntry | WrappedMessageEntry | DirectUserEntry | DirectAssistantEntry;

/**
 * Configuration for our Claude session manager
 */
export interface SessionManagerConfig {
  // Paths
  claudeDir: string;
  projectsDir: string;
  
  // UI preferences
  useGum: boolean;
  useFzf: boolean;
  useTmux: boolean;
  
  // Session defaults
  defaultPermissionMode: PermissionMode;
  maxTurns?: number;
  systemPrompt?: string;
  
  // Integration options
  enableZoxide: boolean;
  enableSesh: boolean;
  enableMcp: boolean;
}

/**
 * Command execution result
 */
export interface CommandResult {
  success: boolean;
  stdout: string;
  stderr?: string;
  code: number;
}

/**
 * Session selection result
 */
export interface SessionSelection {
  session: ClaudeSession;
  action: 'resume' | 'view' | 'export' | 'delete' | 'cancel';
}

/**
 * Hook configuration for session events
 */
export interface SessionHookConfig {
  onSessionStart?: (session: ClaudeSession) => Promise<void>;
  onSessionEnd?: (session: ClaudeSession, reason: string) => Promise<void>;
  onMessageSent?: (message: SDKUserMessage) => Promise<void>;
  onMessageReceived?: (message: SDKAssistantMessage) => Promise<void>;
}

/**
 * Export format options
 */
export type ExportFormat = 'markdown' | 'json' | 'html' | 'pdf';

/**
 * Export configuration
 */
export interface ExportConfig {
  format: ExportFormat;
  includeMetadata: boolean;
  includeTimestamps: boolean;
  maxMessages?: number;
  outputPath?: string;
}

/**
 * Type guard functions for SDK messages
 */
export function isSDKUserMessage(msg: SDKMessage): msg is SDKUserMessage {
  return 'type' in msg && msg.type === 'user';
}

export function isSDKAssistantMessage(msg: SDKMessage): msg is SDKAssistantMessage {
  return 'type' in msg && msg.type === 'assistant';
}

export function isSDKSystemMessage(msg: SDKMessage): msg is SDKSystemMessage {
  return 'type' in msg && msg.type === 'system';
}

export function isSDKResultMessage(msg: SDKMessage): msg is SDKResultMessage {
  return 'type' in msg && msg.type === 'result';
}

/**
 * Type guard functions for session file entries
 */
export function isMetadataEntry(entry: SessionFileEntry): entry is MetadataEntry {
  return entry.type === 'metadata';
}

export function isSummaryEntry(entry: SessionFileEntry): entry is SummaryEntry {
  return entry.type === 'summary';
}

export function isWrappedMessageEntry(entry: SessionFileEntry): entry is WrappedMessageEntry {
  return entry.type === 'message';
}

export function isDirectUserEntry(entry: SessionFileEntry): entry is DirectUserEntry {
  return entry.type === 'user';
}

export function isDirectAssistantEntry(entry: SessionFileEntry): entry is DirectAssistantEntry {
  return entry.type === 'assistant';
}

/**
 * Check if an entry is any type of message (wrapped or direct)
 */
export function isMessageEntry(entry: SessionFileEntry): entry is WrappedMessageEntry | DirectUserEntry | DirectAssistantEntry {
  return entry.type === 'message' || entry.type === 'user' || entry.type === 'assistant';
}

/**
 * Normalize any message entry to a common format
 */
export function normalizeMessageEntry(entry: SessionFileEntry): {
  role: 'user' | 'assistant' | 'system';
  content: any;
  timestamp: string;
  isMeta?: boolean;
} | null {
  if (!isMessageEntry(entry)) {
    return null;
  }

  // Skip meta messages
  if (entry.isMeta) {
    return {
      role: 'system',
      content: '',
      timestamp: entry.timestamp,
      isMeta: true,
    };
  }

  if (isWrappedMessageEntry(entry)) {
    return {
      role: entry.message.role,
      content: entry.message.content,
      timestamp: entry.timestamp,
    };
  }

  if (isDirectUserEntry(entry)) {
    return {
      role: 'user',
      content: entry.message.content,
      timestamp: entry.timestamp,
    };
  }

  if (isDirectAssistantEntry(entry)) {
    return {
      role: 'assistant',
      content: entry.message.content,
      timestamp: entry.timestamp,
    };
  }

  return null;
}

/**
 * Extract text content from message content
 */
export function extractTextContent(content: any): string {
  if (typeof content === 'string') {
    return content;
  }

  if (Array.isArray(content)) {
    const texts = content
      .filter((item: any) => item.type === 'text' && item.text)
      .map((item: any) => item.text);
    return texts.join('\n');
  }

  return '';
}