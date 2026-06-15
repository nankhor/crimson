# frozen_string_literal: true

module Crimson
  # Routes user intents to skills based on trigger keyword matching.
  # Supports auto-inject skills triggered by tool usage and domain-based priority sorting.
  class SkillRouter
    # Directory where bundled skills are stored in the repository.
    REPO_SKILLS_DIR = File.expand_path("../../skills", __dir__)

    # Skill domain descriptor.
    Domain = Struct.new(:name, :priority, keyword_init: true)

    # Built-in skill domains with their priority levels.
    DOMAINS = {
      engineering: Domain.new(name: "engineering", priority: 10),
      analysis:    Domain.new(name: "analysis",    priority: 5),
      communication: Domain.new(name: "communication", priority: 5),
      safety:      Domain.new(name: "safety",      priority: 20),
    }.freeze

    MAX_CONDITIONAL_SKILLS = 2

    # @param skills_dirs [Array<String>, nil] directories to search for skill markdown files
    def initialize(skills_dirs: nil)
      @skills_dirs = skills_dirs || [REPO_SKILLS_DIR]
      @manifests = {}
      @skill_paths = {}
      load_manifests
    end

    # Resolve which skills are relevant to a user message.
    # @param user_message [String] the user's input
    # @param tools_invoked [Array<String>] tools used in the current turn
    # @return [Array<String>] list of active skill names (always includes "coding")
    def resolve(user_message, tools_invoked: [])
      lower = user_message.to_s.downcase.strip
      matched = []

      @manifests.each do |name, manifest|
        next if manifest[:auto_inject]
        next unless triggers_match?(lower, manifest[:triggers])
        matched << { name: name, priority: manifest[:domain_priority], domain: manifest[:domain] }
      end

      matched.sort_by! { |s| -s[:priority] }

      result = ["coding"]
      seen_domains = Set.new

      matched.each do |skill|
        break if result.length >= MAX_CONDITIONAL_SKILLS + 1
        next if seen_domains.include?(skill[:domain])
        result << skill[:name].to_s
        seen_domains << skill[:domain]
      end

      @manifests.each do |name, manifest|
        next unless manifest[:auto_inject]
        next unless (tools_invoked & manifest[:auto_inject_tools]).any?
        result << name.to_s unless result.include?(name.to_s)
      end

      result
    end

    # Load a skill's content (with front matter stripped).
    # @param name [String] skill name
    # @return [String, nil] skill content or nil if not found
    def load_skill(name)
      path = @skill_paths[name.to_sym]
      return nil unless path && File.exist?(path)
      content = File.read(path)
      strip_front_matter(content)
    end

    # @return [Array<String>] all discovered skill names
    def skill_names
      @manifests.keys.map(&:to_s)
    end

    private

    # @api private
    def load_manifests
      @skills_dirs.each do |dir|
        next unless Dir.exist?(dir)
        Dir.glob(File.join(dir, "*.md")).each do |path|
          name = File.basename(path, ".md").to_sym
          next if @manifests.key?(name)
          content = File.read(path)
          manifest = parse_front_matter(content, name)
          if manifest
            @manifests[name] = manifest
            @skill_paths[name] = path
          end
        end
      end
    rescue Errno::ENOENT
      nil
    end

    # @api private
    def parse_front_matter(content, name)
      return default_manifest(name) unless content.start_with?("---")

      parts = content.split("---", 3)
      return default_manifest(name) if parts.length < 3

      yaml_block = parts[1]
      manifest = default_manifest(name)

      yaml_block.each_line do |line|
        line = line.strip
        case line
        when /^domain:\s*(\S+)/
          domain_name = $1.to_sym
          manifest[:domain] = domain_name
          manifest[:domain_priority] = DOMAINS[domain_name]&.priority || 0
        when /^triggers:\s*\[(.+)\]/
          manifest[:triggers] = $1.split(",").map { |t| t.strip.downcase }
        when /^priority:\s*(\d+)/
          manifest[:priority] = $1.to_i
        when /^auto_inject:\s*true/
          manifest[:auto_inject] = true
          manifest[:auto_inject_tools] = %w[write_file edit_file]
        when /^auto_inject_tools:\s*\[(.+)\]/
          manifest[:auto_inject_tools] = $1.split(",").map { |t| t.strip }
        end
      end

      manifest[:triggers]&.map!(&:downcase)
      manifest
    end

    # @api private
    def default_manifest(name)
      {
        domain: :base,
        domain_priority: 0,
        triggers: [],
        priority: 0,
        auto_inject: false,
        auto_inject_tools: [],
      }
    end

    # @api private
    def triggers_match?(message, triggers)
      triggers&.any? do |t|
        if t.include?(" ")
          message.include?(t)
        else
          message.match?(/\b#{Regexp.escape(t)}\b/)
        end
      end
    end

    # @api private
    def strip_front_matter(content)
      return content unless content.start_with?("---")
      parts = content.split("---", 3)
      parts.length >= 3 ? parts[2].strip : content
    end
  end
end
