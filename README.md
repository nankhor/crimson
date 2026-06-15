# Crimson

[![CI](https://github.com/cmoiadib/crimson/actions/workflows/ci.yml/badge.svg)](https://github.com/cmoiadib/crimson/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/crimson)](https://rubygems.org/gems/crimson)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-3.2%2B-red)](https://www.ruby-lang.org)

An open-source Ruby-based minimal coding agent made to get things done.

## Features

- **Multi-provider support** — OpenAI, Anthropic, OpenRouter, Mistral, xAI, and custom OpenAI-compatible endpoints
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

```bash
git clone https://github.com/cmoiadib/crimson.git
cd crimson
bundle install
```

## Setup

```bash
ruby bin/crimson setup
```

This walks you through selecting a provider, entering your API key, and picking a model.

## Usage

Start the interactive REPL:

```bash
ruby bin/crimson
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

### Skills

Add `.md` files to the `skills/` directory to customize agent behavior. These are loaded into the system prompt automatically.

## License

MIT
