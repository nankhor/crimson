# frozen_string_literal: true

require "json"
require "fileutils"

module Crimson
  # Manages directory trust state for loading project context files.
  # Persists trust decisions to a JSON file and prompts users for untrusted directories.
  class TrustManager
    # File names considered as project context files.
    CONTEXT_FILE_NAMES = %w[
      AGENTS.md AGENTS.MD
      CLAUDE.md CLAUDE.MD
      GEMINI.md GEMINI.MD
    ].freeze

    # @param trust_file [String, nil] path to the trust JSON file
    def initialize(trust_file: nil)
      @trust_file = trust_file || File.join(Crimson::CONFIG_DIR, "trust.json")
      @trust_data = load_trust_data
    end

    # Check whether a directory (or an ancestor) is trusted.
    # @param cwd [String] directory path
    # @return [Boolean]
    def trusted?(cwd)
      entry = find_nearest_trust(File.expand_path(cwd))
      entry == true
    end

    # Prompt the user to trust a directory that has context files.
    # @param cwd [String] directory path
    # @return [Boolean] whether the directory is now trusted
    def prompt_trust(cwd)
      expanded = File.expand_path(cwd)
      return true unless has_context_files?(expanded)
      return true if trusted?(expanded)

      prompt = TTY::Prompt.new
      puts
      choice = prompt.select("Trust this project?\n#{expanded}\n\nThis allows loading AGENTS.md and project settings.", [
        { name: "Trust", value: :trust },
        { name: "Trust parent folder (#{File.dirname(expanded)})", value: :trust_parent },
        { name: "Trust (this session only)", value: :session_only },
        { name: "Don't trust", value: :deny }
      ])

      case choice
      when :trust
        save_trust(expanded, true)
        true
      when :trust_parent
        save_trust(File.dirname(expanded), true)
        save_trust(expanded, nil)
        true
      when :session_only
        true
      when :deny
        save_trust(expanded, false)
        false
      end
    end

    # Check whether a directory contains any project context files.
    # @param dir [String] directory path
    # @return [Boolean]
    def has_context_files?(dir)
      CONTEXT_FILE_NAMES.any? { |name| File.exist?(File.join(dir, name)) }
    end

    private

    # @api private
    def load_trust_data
      return {} unless File.exist?(@trust_file)
      JSON.parse(File.read(@trust_file))
    rescue JSON::ParserError
      {}
    end

    # @api private
    def save_trust(path, decision)
      @trust_data[File.expand_path(path)] = decision
      FileUtils.mkdir_p(File.dirname(@trust_file))
      File.write(@trust_file, JSON.pretty_generate(@trust_data))
    end

    # Walk up the directory tree looking for a trust decision.
    # @api private
    def find_nearest_trust(dir)
      loop do
        value = @trust_data[dir]
        return value if value == true || value == false

        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end
  end
end
