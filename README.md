# Crimson

[![CI](https://github.com/nankhor/crimson/actions/workflows/ci.yml/badge.svg)](https://github.com/nankhor/crimson/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/crimson)](https://rubygems.org/gems/crimson)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-3.2%2B-red)](https://www.ruby-lang.org)

A minimal Ruby-based coding agent that gets things done.

## Quick Start

```bash
# Install
gem install crimson

# Configure your API key
crimson setup

# Start coding
crimson "refactor this module to use dependency injection"
```

## Features

- **Multi-provider support** — OpenAI, Anthropic, OpenRouter, Mistral, xAI, and any OpenAI-compatible endpoint
- **Official SDKs** — Uses the official OpenAI and Anthropic Ruby gems
- **Built-in tools** — Read, write, edit, list files, run commands, search code, and glob
- **Streaming output** — Real-time response with styled markdown rendering (headers, bold, italic, code, lists, links, blockquotes)
- **Colored tool display** — `→Read`, `→Write`, `→Edit`, `$ command`, `✱Search`, `✱Glob`, `→List` with per-tool colors
- **Thinking indicator** — Spinner while thinking, with `+ Thought: X.Xs` timing on first token
- **Run stats** — Token usage, cost, and elapsed time shown at end of every run
- **Skills system** — Customize agent behavior with markdown files
- **Session management** — Save, load, fork, and name conversation sessions per directory
- **Conversation compaction** — Automatic and manual compaction to stay within context limits
- **Cost tracking** — Real-time token usage and cost tracking per run
- **Interactive REPL** — Conversational coding assistant with tab-completion and slash commands

## Requirements

- Ruby 3.2+

## Installation

### Via RubyGems

```bash
gem install crimson
```

### From source

```bash
git clone https://github.com/nankhor/crimson.git
cd crimson
bundle install
bundle exec exe/crimson setup
```

## Configuration

```bash
crimson setup
```

This walks you through selecting a provider, entering your API key, and picking a model.

Configuration is stored in `~/.crimson/config.json` (600 permissions).

You can also set the API key via environment variables:

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | OpenAI API key |
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `MISTRAL_API_KEY` | Mistral API key |
| `XAI_API_KEY` | xAI API key |

## Usage

### Interactive REPL

Start a conversational session:

```bash
crimson
```

Type your task and the agent will use its tools to read, write, and edit files in your project.

### One-shot mode

Pass a task directly as an argument:

```bash
crimson "add error handling to the database module"
```

The agent completes the task and exits, showing the full conversation and cost summary.

### Example session

```
$ crimson
Crimson v0.1.0
Type /help for commands, /exit to quit

> add a health check endpoint to the Sinatra app
→Read config.ru ...
→Read app.rb ...
✱Search app.rb for "get" ...
→Write app.rb ...
Done. Added GET /health endpoint returning JSON status.
Tokens: 1,234 ↑ | Cost: $0.0123 | Time: 12.3s
```

### Slash commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/clear` | Clear conversation history |
| `/model` | Switch model (interactive selector) |
| `/thinking` | Set thinking level (off/low/medium/high) |
| `/tools` | List available tools |
| `/save` | Save conversation to file |
| `/load` | Load conversation from file |
| `/usage` | Show token usage and cost |
| `/sessions` | List sessions for current directory |
| `/name` | Set session name |
| `/session` | Show session info |
| `/fork` | Fork current session into new branch |
| `/tree` | Show conversation tree |
| `/compact` | Compact conversation history |
| `/exit` | Exit crimson |

## Skills

Add `.md` files to `~/.crimson/skills/` to customize agent behavior. These are loaded into the system prompt automatically. Built-in skills are in the `skills/` directory for reference.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT
