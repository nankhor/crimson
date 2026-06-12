# frozen_string_literal: true

require "set"

module Crimson
  class ProjectContext
    CONTEXT_FILE_NAMES = %w[
      AGENTS.md AGENTS.MD
      CLAUDE.md CLAUDE.MD
      GEMINI.md GEMINI.MD
    ].freeze

    def self.detect(root_dir = Dir.pwd)
      context = []
      context << "Working directory: #{root_dir}"
      context << "OS: #{RUBY_PLATFORM}"

      lang = detect_language(root_dir)
      context << "Language: #{lang}" if lang

      framework = detect_framework(root_dir)
      context << "Framework: #{framework}" if framework

      pkg = detect_package_manager(root_dir)
      context << "Package manager: #{pkg}" if pkg

      testing = detect_testing(root_dir)
      context << "Testing: #{testing}" if testing

      git = detect_git(root_dir)
      context << "Git: #{git}" if git

      context.join("\n")
    end

    def self.load_context_files(root_dir = Dir.pwd)
      files = []
      seen_paths = Set.new
      dir = File.expand_path(root_dir)

      loop do
        CONTEXT_FILE_NAMES.each do |name|
          path = File.join(dir, name)
          next unless File.exist?(path)
          real = File.realpath(path) rescue File.expand_path(path)
          next if seen_paths.include?(real)

          seen_paths.add(real)
          files << { path: path, content: File.read(path) }
        end

        break if git_root?(dir)
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end

      global = File.join(Crimson::CONFIG_DIR, "AGENTS.md")
      if File.exist?(global)
        real = File.realpath(global) rescue File.expand_path(global)
        unless seen_paths.include?(real)
          files << { path: global, content: File.read(global) }
        end
      end

      files
    end

    def self.format_context_files(files)
      return "" if files.nil? || files.empty?

      parts = ["<project_context>", "", "Project-specific instructions and guidelines:", ""]
      files.each do |f|
        parts << "<project_instructions path=\"#{f[:path]}\">"
        parts << f[:content]
        parts << "</project_instructions>"
        parts << ""
      end
      parts << "</project_context>"
      parts.join("\n")
    end

    def self.git_root?(dir)
      Dir.exist?(File.join(dir, ".git"))
    end

    def self.detect_language(root_dir)
      indicators = {
        "Ruby"     => ["Gemfile", "*.rb", "*.gemspec"],
        "Python"   => ["requirements.txt", "pyproject.toml", "*.py", "Pipfile"],
        "TypeScript" => ["tsconfig.json", "*.ts", "*.tsx"],
        "JavaScript" => ["package.json", "*.js", "*.jsx"],
        "Go"       => ["go.mod", "*.go"],
        "Rust"     => ["Cargo.toml", "*.rs"],
        "Java"     => ["pom.xml", "build.gradle", "*.java"],
        "Elixir"   => ["mix.exs", "*.ex"],
      }

      indicators.each do |lang, patterns|
        patterns.each do |pattern|
          return lang if Dir.glob(File.join(root_dir, pattern)).any?
        end
      end

      nil
    end

    def self.detect_framework(root_dir)
      return "Rails" if File.exist?(File.join(root_dir, "bin", "rails"))
      return "Sinatra" if gem_in_gemfile?(root_dir, "sinatra")
      return "Hanami" if gem_in_gemfile?(root_dir, "hanami")
      return "Next.js" if file_has_dep?(root_dir, "package.json", "next")
      return "React" if file_has_dep?(root_dir, "package.json", "react")
      return "Vue" if file_has_dep?(root_dir, "package.json", "vue")
      return "Express" if file_has_dep?(root_dir, "package.json", "express")
      return "Django" if File.exist?(File.join(root_dir, "manage.py"))
      return "Flask" if file_has_dep?(root_dir, "requirements.txt", "flask")
      nil
    end

    def self.detect_package_manager(root_dir)
      return "bundler" if File.exist?(File.join(root_dir, "Gemfile"))
      return "npm" if File.exist?(File.join(root_dir, "package-lock.json"))
      return "yarn" if File.exist?(File.join(root_dir, "yarn.lock"))
      return "pnpm" if File.exist?(File.join(root_dir, "pnpm-lock.yaml"))
      return "pip" if File.exist?(File.join(root_dir, "requirements.txt"))
      return "cargo" if File.exist?(File.join(root_dir, "Cargo.toml"))
      return "go modules" if File.exist?(File.join(root_dir, "go.mod"))
      nil
    end

    def self.detect_testing(root_dir)
      return "RSpec" if File.exist?(File.join(root_dir, ".rspec")) || gem_in_gemfile?(root_dir, "rspec")
      return "Minitest" if Dir.glob(File.join(root_dir, "test/**/*_test.rb")).any?
      return "Jest" if file_has_dep?(root_dir, "package.json", "jest")
      return "pytest" if File.exist?(File.join(root_dir, "pytest.ini"))
      return "Go testing" if Dir.glob(File.join(root_dir, "**/*_test.go")).any?
      nil
    end

    def self.detect_git(root_dir)
      return nil unless Dir.exist?(File.join(root_dir, ".git"))

      branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      return nil if branch.empty?

      dirty = !`git status --porcelain 2>/dev/null`.strip.empty?
      status = dirty ? "#{branch} (dirty)" : "#{branch} (clean)"
      status
    end

    def self.gem_in_gemfile?(root_dir, gem_name)
      gemfile = File.join(root_dir, "Gemfile")
      return false unless File.exist?(gemfile)
      File.read(gemfile).include?(gem_name)
    end

    def self.file_has_dep?(root_dir, filename, dep_name)
      path = File.join(root_dir, filename)
      return false unless File.exist?(path)
      File.read(path).include?(dep_name)
    end
  end
end
