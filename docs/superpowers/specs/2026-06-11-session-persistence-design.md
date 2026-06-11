# Session Persistence & Branching — Design Spec

## Problem

Crimson has no automatic session persistence. Users lose their conversation when they exit. There is a manual `/save` and `/load` that writes to a single `.crimson_history` file, but it is flat (no branching), crash-unsafe (file rewrite), and not tied to working directories.

Pi solves this with JSONL append-only session files organized by working directory, with tree-structured entries that enable branching from any point.

## Approach

JSONL append-only log with in-file tree branching, stored globally in `~/.crimson/sessions/<dir_hash>/<session_id>.jsonl`.

## Storage Layout

```
~/.crimson/sessions/
  a1b2c3d4e5f6/                    # SHA256 hash of working directory path (first 12 chars)
    550e8400-e29b-41d4-a716-446655440000.jsonl
    6ba7b810-9dad-11d1-80b4-00c04fd430c8.jsonl
```

The directory hash isolates sessions per project without exposing full paths.

## JSONL Entry Format

Each line is a JSON object:

```json
{
  "id": "uuid",
  "parentId": "uuid | null",
  "role": "user | assistant | tool_result | system",
  "content": "string",
  "toolCalls": [],
  "toolCallId": "string | null",
  "toolName": "string | null",
  "tokenUsage": { "prompt": 0, "completion": 0, "total": 0 },
  "timestamp": "ISO 8601"
}
```

Fields:
- `id` — unique entry identifier (UUID)
- `parentId` — points to the previous entry in the conversation chain, enabling tree traversal
- `role` — message role
- `content` — message body (text content for user/assistant/system, result text for tool_result)
- `toolCalls` — array of `{ id, name, arguments }` objects, present only on assistant messages with tool calls
- `toolCallId` — present only on tool_result entries, links back to the tool call
- `toolName` — present only on tool_result entries
- `tokenUsage` — token counts for the turn, present on assistant entries
- `timestamp` — when the entry was created

## New Classes

### `Crimson::SessionManager`

Responsible for CRUD operations on session files.

```ruby
class SessionManager
  SESSIONS_DIR = File.join(Crimson::CONFIG_DIR, "sessions")

  def initialize
    FileUtils.mkdir_p(SESSIONS_DIR)
  end

  def create(cwd:) -> String (session_id)
  def load(session_id, cwd:) -> Array<SessionEntry> (linearized branch)
  def append(session_id, cwd:, entry:) -> void
  def list(cwd:) -> Array<SessionMeta>
  def latest(cwd:) -> SessionMeta?
  def fork(session_id, cwd:, from_entry_id:) -> String (new session_id)
  def delete(session_id, cwd:) -> void
  def session_file(session_id, cwd:) -> String (file path)
  def dir_hash(cwd:) -> String
end
```

`list` returns `SessionMeta` objects containing session_id, entry count, last timestamp, and the last user message (as a preview).

`load` reads all entries from the JSONL file sequentially (they are already in chronological order since the file is append-only and linear). Returns them as an array.

### `Crimson::SessionEntry`

Simple data object representing a single JSONL line.

```ruby
class SessionEntry
  attr_accessor :id, :parent_id, :role, :content,
                :tool_calls, :tool_call_id, :tool_name,
                :token_usage, :timestamp

  def to_h -> Hash
  def self.from_h(hash) -> SessionEntry
  def self.from_message(message, parent_id:) -> SessionEntry
  def to_message -> Message::User | Message::Assistant | Message::ToolResult
end
```

`from_message` converts a `Message::User`, `Message::Assistant`, or `Message::ToolResult` into a `SessionEntry`. `to_message` performs the reverse conversion for loading sessions back into agent history.

### `Crimson::SessionMeta`

Lightweight metadata for listing sessions.

```ruby
SessionMeta = Struct.new(:id, :entry_count, :last_timestamp, :preview)
```

## Branching

### Copy-on-Fork Model

Each session file is a flat, linear sequence of entries. Branching creates a new session file that copies entries up to the fork point. No tree structure within a single file.

**Why copy-on-fork over in-file branching:**
- Simpler to implement and reason about
- No tree traversal logic needed in `load`
- Each session file is always a single linear conversation
- Easier to debug (read file top to bottom = conversation order)

### Fork Implementation

```ruby
def fork(session_id, cwd:, from_entry_id:)
  entries = read_all_entries(session_id, cwd:)
  fork_point = entries.index { |e| e.id == from_entry_id }
  raise "Entry not found" unless fork_point

  prefix = entries[0..fork_point]
  new_id = SecureRandom.uuid
  prefix.each { |e| append(new_id, cwd:, entry: e) }
  new_id
end
```

This creates a new session file with the conversation up to the fork point. The user then continues from there. The original session file is untouched.

## Agent Integration

### Session-Aware Agent

The `Agent` class gets optional session tracking:

```ruby
class Agent
  attr_reader :session_id, :session_manager, :session_cwd

  def start_session(cwd:)
    @session_manager = SessionManager.new
    @session_id = @session_manager.create(cwd:)
    @session_cwd = cwd
    @last_entry_id = nil
  end

  def resume_session(session_id, cwd:)
    @session_manager = SessionManager.new
    entries = @session_manager.load(session_id, cwd:)
    @session_id = session_id
    @session_cwd = cwd
    @history = entries.map(&:to_message).compact
    @last_entry_id = entries.last&.id
  end
end
```

### Appending on Events

In the existing `run_loop`, after each message is added to `@history`:

```ruby
# After @history << assistant_message
if @session_manager && @session_id
  entry = SessionEntry.from_message(assistant_message, parent_id: @last_entry_id)
  @session_manager.append(@session_id, cwd: @session_cwd, entry: entry)
  @last_entry_id = entry.id
end
```

Same for tool results. The session is append-only — each event writes one line.

### Session Lifecycle

- **No session active** — agent works exactly as today (backward compatible)
- **Session active** — entries are appended on every message/tool result
- **Abort** — session file contains everything up to abort point (crash-safe)
- **Reset** — clears in-memory history, does NOT delete session file

## REPL Integration

### New CLI Flags

```
ruby bin/crimson                  # Start new session
ruby bin/crimson --continue       # Resume latest session for cwd
ruby bin/crimson --resume         # Interactive session picker
ruby bin/crimson --session ID     # Resume specific session
ruby bin/crimson --no-session     # Ephemeral, no session saved
```

### New Slash Commands

| Command | Description |
|---------|-------------|
| `/sessions` | List sessions for current directory |
| `/resume [id]` | Resume a session (default: latest) |
| `/fork` | Fork from current point into new session |
| `/tree` | Show conversation tree for current session |

### Updated REPL Flow

On startup:
1. If `--continue` flag: load latest session, populate agent history
2. If `--resume` flag: show session picker (TTY::Prompt), then load
3. If `--session ID`: load specific session
4. If `--no-session`: skip session creation
5. Default: create new session, append entries as conversation progresses

On exit: session file already has all data (append-only). No explicit save needed.

## Error Handling

- **Corrupt JSONL line**: Skip line, log warning, continue
- **Missing session file**: Treat as "no session found", start fresh
- **Disk full**: Append fails silently, session is incomplete but not corrupt
- **Concurrent access**: Not handled in v1 (single-process assumption)

## Testing Strategy

- `SessionManager` unit tests with temp directories
- `SessionEntry` serialization round-trip tests
- Agent integration test: start session, run conversation, verify JSONL content
- Branch test: fork from midpoint, verify both branches load correctly
- Crash test: simulate partial write, verify recovery

## Out of Scope (Future Phases)

- Auto-compaction of old sessions
- Session search/filter
- Session export (HTML, Markdown)
- Multi-process locking
- Session sharing

## Files to Create/Modify

### New Files
- `lib/crimson/session_manager.rb`
- `lib/crimson/session_entry.rb`
- `lib/crimson/session_meta.rb`
- `spec/crimson/session_manager_spec.rb`
- `spec/crimson/session_entry_spec.rb`

### Modified Files
- `lib/crimson.rb` — add requires
- `lib/crimson/agent.rb` — add session tracking hooks
- `lib/crimson/repl.rb` — add slash commands, session resume
- `exe/crimson` — add CLI flags for session management
