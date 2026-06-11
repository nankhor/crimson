require 'json'
require 'open3'
require 'fileutils'

module Crimson
  module Tools
    module ReadFile
      TOOL_NAME = "read_file"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Read the contents of a file at the given path.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "The path to the file to read" }
              },
              required: ["path"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Read the contents of a file at the given path.",
          input_schema: {
            type: "object",
            properties: {
              path: { type: "string", description: "The path to the file to read" }
            },
            required: ["path"]
          }
        }
      end

      def self.call(path:)
        return "Error: No path provided" if path.nil? || path.strip.empty?

        expanded = File.expand_path(path)

        return "Error: File not found: #{path}" unless File.exist?(expanded)
        return "Error: Not a file: #{path}" unless File.file?(expanded)

        File.read(expanded)
      rescue => e
        "Error reading file: #{e.message}"
      end
    end

    module WriteFile
      TOOL_NAME = "write_file"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Write content to a file. Creates the file and parent directories if needed.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "The path to the file to write" },
                content: { type: "string", description: "The content to write" }
              },
              required: ["path", "content"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Write content to a file. Creates the file and parent directories if needed.",
          input_schema: {
            type: "object",
            properties: {
              path: { type: "string", description: "The path to the file to write" },
              content: { type: "string", description: "The content to write" }
            },
            required: ["path", "content"]
          }
        }
      end

      def self.call(path:, content:)
        return "Error: No path provided" if path.nil? || path.strip.empty?

        expanded = File.expand_path(path)
        dir = File.dirname(expanded)

        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        File.write(expanded, content)
        "Successfully wrote to #{path}"
      rescue => e
        "Error writing file: #{e.message}"
      end
    end

    module ListDirectory
      TOOL_NAME = "list_directory"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "List files and directories at the given path.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "The directory path to list. Defaults to current directory." }
              },
              required: ["path"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "List files and directories at the given path.",
          input_schema: {
            type: "object",
            properties: {
              path: { type: "string", description: "The directory path to list. Defaults to current directory." }
            },
            required: ["path"]
          }
        }
      end

      def self.call(path: ".")
        expanded = File.expand_path(path)

        return "Error: Directory not found: #{path}" unless Dir.exist?(expanded)

        entries = Dir.entries(expanded).sort - [".", ".."]

        entries.map do |entry|
          full_path = File.join(expanded, entry)
          File.directory?(full_path) ? "#{entry}/" : entry
        end.join("\n")
      rescue => e
        "Error listing directory: #{e.message}"
      end
    end

    module RunCommand
      TOOL_NAME = "run_command"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Execute a shell command and return stdout and stderr.",
            parameters: {
              type: "object",
              properties: {
                command: { type: "string", description: "The shell command to execute" },
                timeout: { type: "integer", description: "Timeout in seconds (default: 30)" }
              },
              required: ["command"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Execute a shell command and return stdout and stderr.",
          input_schema: {
            type: "object",
            properties: {
              command: { type: "string", description: "The shell command to execute" },
              timeout: { type: "integer", description: "Timeout in seconds (default: 30)" }
            },
            required: ["command"]
          }
        }
      end

      def self.call(command:, timeout: 30)
        return "Error: No command provided" if command.nil? || command.strip.empty?

        pid = nil
        stdout, stderr, status = Open3.capture3(command) do |stdin|
          stdin.close
          pid = stdin.pid
        end

        output = String.new
        output << stdout if stdout && !stdout.empty?
        output << stderr if stderr && !stderr.empty?
        output = "(no output)" if output.strip.empty?
        output << "\n(exit code: #{status.exitstatus})" unless status.success?
        output
      rescue => e
        "Error executing command: #{e.message}"
      end
    end

    module EditFile
      TOOL_NAME = "edit_file"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Replace a specific string in a file. The old_string must appear exactly once in the file unless replace_all is true.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "The path to the file to edit" },
                old_string: { type: "string", description: "The exact string to find and replace" },
                new_string: { type: "string", description: "The string to replace it with" },
                replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" }
              },
              required: ["path", "old_string", "new_string"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Replace a specific string in a file. The old_string must appear exactly once in the file unless replace_all is true.",
          input_schema: {
            type: "object",
            properties: {
              path: { type: "string", description: "The path to the file to edit" },
              old_string: { type: "string", description: "The exact string to find and replace" },
              new_string: { type: "string", description: "The string to replace it with" },
              replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" }
            },
            required: ["path", "old_string", "new_string"]
          }
        }
      end

      def self.call(path:, old_string:, new_string:, replace_all: false)
        return "Error: No path provided" if path.nil? || path.strip.empty?
        return "Error: No old_string provided" if old_string.nil? || old_string.empty?

        expanded = File.expand_path(path)

        return "Error: File not found: #{path}" unless File.exist?(expanded)
        return "Error: Not a file: #{path}" unless File.file?(expanded)

        content = File.read(expanded)

        if replace_all
          count = content.scan(old_string).length
          return "No occurrences of old_string found in #{path}" if count == 0

          new_content = content.gsub(old_string, new_string)
          File.write(expanded, new_content)
          "Successfully replaced #{count} occurrence(s) in #{path}"
        else
          count = content.scan(old_string).length

          if count == 0
            "Error: old_string not found in #{path}. Make sure it matches exactly."
          elsif count > 1
            "Error: old_string found #{count} times in #{path}. It must be unique, or use replace_all: true."
          else
            new_content = content.sub(old_string, new_string)
            File.write(expanded, new_content)
            "Successfully edited #{path}"
          end
        end
      rescue => e
        "Error editing file: #{e.message}"
      end
    end

    module SearchFiles
      TOOL_NAME = "search_files"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Search for a regex pattern in files. Returns matching file paths and line numbers.",
            parameters: {
              type: "object",
              properties: {
                pattern: { type: "string", description: "The regex pattern to search for" },
                path: { type: "string", description: "The directory to search in. Defaults to current directory." },
                file_pattern: { type: "string", description: "Glob pattern to filter files (e.g. '*.rb'). Defaults to all files." }
              },
              required: ["pattern"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Search for a regex pattern in files. Returns matching file paths and line numbers.",
          input_schema: {
            type: "object",
            properties: {
              pattern: { type: "string", description: "The regex pattern to search for" },
              path: { type: "string", description: "The directory to search in. Defaults to current directory." },
              file_pattern: { type: "string", description: "Glob pattern to filter files (e.g. '*.rb'). Defaults to all files." }
            },
            required: ["pattern"]
          }
        }
      end

      def self.call(pattern:, path: ".", file_pattern: nil)
        return "Error: No pattern provided" if pattern.nil? || pattern.strip.empty?

        expanded = File.expand_path(path)
        cmd = ["grep", "-rn", "--color=never", "-E"]
        cmd += ["--include=#{file_pattern}"] if file_pattern
        cmd << pattern << expanded

        pid = nil
        stdout, _stderr, status = Open3.capture3(*cmd)

        return "No matches found." if status.exitstatus == 1

        lines = stdout.lines
        if lines.length > 100
          "#{lines.first(100).join}\n... (truncated, #{lines.length - 100} more matches)"
        else
          stdout
        end
      rescue => e
        "Error searching files: #{e.message}"
      end
    end

    module Glob
      TOOL_NAME = "glob"

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Find files matching a glob pattern (e.g. '**/*.rb', 'src/**/*.ts'). Returns sorted file paths.",
            parameters: {
              type: "object",
              properties: {
                pattern: { type: "string", description: "The glob pattern to match files against" },
                path: { type: "string", description: "The directory to search in. Defaults to current directory." }
              },
              required: ["pattern"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Find files matching a glob pattern (e.g. '**/*.rb', 'src/**/*.ts'). Returns sorted file paths.",
          input_schema: {
            type: "object",
            properties: {
              pattern: { type: "string", description: "The glob pattern to match files against" },
              path: { type: "string", description: "The directory to search in. Defaults to current directory." }
            },
            required: ["pattern"]
          }
        }
      end

      def self.call(pattern:, path: ".")
        return "Error: No pattern provided" if pattern.nil? || pattern.strip.empty?

        expanded = File.expand_path(path)
        return "Error: Directory not found: #{path}" unless Dir.exist?(expanded)

        files = Dir.glob(File.join(expanded, pattern)).sort

        if files.empty?
          "No files found matching pattern: #{pattern}"
        elsif files.length > 200
          "#{files.first(200).join("\n")}\n... (truncated, #{files.length - 200} more files)"
        else
          files.join("\n")
        end
      rescue => e
        "Error searching files: #{e.message}"
      end
    end

    ALL = [ReadFile, WriteFile, EditFile, ListDirectory, RunCommand, SearchFiles, Glob].freeze
  end
end
