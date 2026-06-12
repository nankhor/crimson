require 'json'
require 'open3'
require 'fileutils'
require 'timeout'
require 'diff/lcs'

module Crimson
  module Tools
    module ReadFile
      TOOL_NAME = "read_file"

      IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .bmp .ico .svg .tiff .tif].freeze
      BINARY_EXTENSIONS = %w[.zip .tar .gz .bz2 .xz .7z .rar .exe .dll .so .dylib .o .a .class .jar .wasm .pdf .doc .docx .xls .xlsx .ppt .pptx .woff .woff2 .ttf .eot .otf .mp3 .mp4 .avi .mov .mkv .flac .ogg .wav].freeze

      def self.prepare_arguments(args)
        args["offset"] = args["offset"].to_i if args["offset"]
        args["limit"] = args["limit"].to_i if args["limit"]
        args
      end

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Read the contents of a file. Supports offset/limit for reading portions of large files.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "The path to the file to read" },
                offset: { type: "integer", description: "Line number to start reading from (1-indexed). Defaults to 1." },
                limit: { type: "integer", description: "Maximum number of lines to read. Defaults to all lines." }
              },
              required: ["path"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Read the contents of a file. Supports offset/limit for reading portions of large files.",
          input_schema: {
            type: "object",
            properties: {
              path: { type: "string", description: "The path to the file to read" },
              offset: { type: "integer", description: "Line number to start reading from (1-indexed). Defaults to 1." },
              limit: { type: "integer", description: "Maximum number of lines to read. Defaults to all lines." }
            },
            required: ["path"]
          }
        }
      end

      def self.call(path:, offset: nil, limit: nil)
        return "Error: No path provided" if path.nil? || path.strip.empty?

        expanded = File.expand_path(path)

        return "Error: File not found: #{path}" unless File.exist?(expanded)
        return "Error: Not a file: #{path}" unless File.file?(expanded)

        ext = File.extname(expanded).downcase
        return describe_image(expanded, ext) if IMAGE_EXTENSIONS.include?(ext)
        return describe_binary(expanded, ext) if BINARY_EXTENSIONS.include?(ext)

        content = File.read(expanded)
        lines = content.lines

        if offset || limit
          start_line = [(offset || 1) - 1, 0].max
          end_line = limit ? start_line + limit : lines.length
          end_line = [end_line, lines.length].min
          total = lines.length

          selected = lines[start_line...end_line]
          numbered = selected.each_with_index.map do |line, i|
            "#{start_line + i + 1}: #{line}"
          end

          header = "(lines #{start_line + 1}-#{end_line} of #{total})"
          "#{header}\n#{numbered.join}"
        else
          content
        end
      rescue => e
        "Error reading file: #{e.message}"
      end

      def self.describe_image(path, ext)
        size = File.size(path)
        size_str = size > 1_048_576 ? "#{(size / 1_048_576.0).round(1)}MB" : "#{(size / 1024.0).round(1)}KB"
        "Image file: #{File.basename(path)} (#{ext}, #{size_str}). Image reading not yet supported — use run_command with identify/ffprobe for metadata."
      end

      def self.describe_binary(path, ext)
        size = File.size(path)
        size_str = size > 1_048_576 ? "#{(size / 1_048_576.0).round(1)}MB" : "#{(size / 1024.0).round(1)}KB"
        "Binary file: #{File.basename(path)} (#{ext}, #{size_str}). Cannot display binary content."
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

        old_content = File.exist?(expanded) ? File.read(expanded) : nil

        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        File.write(expanded, content)

        diff = format_diff(old_content, content, path)
        "Successfully wrote to #{path}\n#{diff}"
      rescue => e
        "Error writing file: #{e.message}"
      end

      def self.format_diff(old_content, new_content, path)
        require 'pastel'
        pastel = Pastel.new

        if old_content.nil?
          # New file - show all lines as added
          output = []
          output << pastel.dim("--- /dev/null")
          output << pastel.dim("+++ #{path}")
          new_content.each_line do |line|
            output << pastel.green("+ #{line.chomp}")
          end
          return output.join("\n")
        end

        old_lines = old_content.each_line.map(&:chomp)
        new_lines = new_content.each_line.map(&:chomp)

        changes = Diff::LCS.sdiff(old_lines, new_lines)

        output = []
        output << pastel.dim("--- #{path}")
        output << pastel.dim("+++ #{path}")

        changes.each do |change|
          case change.action
          when "-"
            output << pastel.red("- #{change.old_element}")
          when "+"
            output << pastel.green("+ #{change.new_element}")
          when "!"
            output << pastel.red("- #{change.old_element}")
            output << pastel.green("+ #{change.new_element}")
          when "="
            output << pastel.dim("  #{change.old_element}")
          end
        end

        output.join("\n")
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
      EXECUTION_MODE = :sequential

      class << self
        attr_accessor :on_update
      end

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

        stdout = String.new
        stderr = String.new
        status = nil
        start_time = Time.now

        begin
          Timeout.timeout(timeout) do
            Open3.popen3(command) do |stdin, out, err, wait_thr|
              stdin.close

              readers = [out, err]
              while readers.any?
                ready = IO.select(readers, nil, nil, 0.1)
                next unless ready

                ready[0].each do |io|
                  chunk = io.read_nonblock(4096, exception: false)
                  if chunk == :wait_readable || chunk.nil?
                    readers.delete(io) if io.eof?
                    next
                  end
                  if io == out
                    stdout << chunk
                  else
                    stderr << chunk
                  end
                  elapsed = Time.now - start_time
                  if @on_update
                    @on_update.call(command, elapsed, stdout.length + stderr.length)
                  end
                end
              end

              status = wait_thr.value
            end
          end

          output = String.new
          output << stdout if !stdout.empty?
          output << stderr if !stderr.empty?
          output = "(no output)" if output.strip.empty?
          output << "\n(exit code: #{status.exitstatus})" unless status.success?
          output
        rescue Timeout::Error
          "Error: Command timed out after #{timeout} seconds"
        rescue => e
          "Error executing command: #{e.message}"
        end
      end
    end

    module EditFile
      TOOL_NAME = "edit_file"

      def self.prepare_arguments(args)
        if args["edits"].is_a?(Array)
          args["edits"].each do |edit|
            edit["replace_all"] = !!edit["replace_all"] if edit.key?("replace_all")
          end
        end
        args["replace_all"] = !!args["replace_all"] if args.key?("replace_all")
        args
      end

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Replace strings in a file. Supports single edit or multiple edits in one call.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "The path to the file to edit" },
                old_string: { type: "string", description: "The exact string to find and replace (single edit mode)" },
                new_string: { type: "string", description: "The string to replace it with (single edit mode)" },
                replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" },
                edits: {
                  type: "array",
                  description: "Array of edits for multiple replacements in one call. Each edit has old_string, new_string, and optional replace_all.",
                  items: {
                    type: "object",
                    properties: {
                      old_string: { type: "string", description: "The exact string to find" },
                      new_string: { type: "string", description: "The replacement string" },
                      replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" }
                    },
                    required: ["old_string", "new_string"]
                  }
                }
              },
              required: ["path"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Replace strings in a file. Supports single edit or multiple edits in one call.",
          input_schema: {
            type: "object",
            properties: {
              path: { type: "string", description: "The path to the file to edit" },
              old_string: { type: "string", description: "The exact string to find and replace (single edit mode)" },
              new_string: { type: "string", description: "The string to replace it with (single edit mode)" },
              replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" },
              edits: {
                type: "array",
                description: "Array of edits for multiple replacements in one call.",
                items: {
                  type: "object",
                  properties: {
                    old_string: { type: "string", description: "The exact string to find" },
                    new_string: { type: "string", description: "The replacement string" },
                    replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" }
                  },
                  required: ["old_string", "new_string"]
                }
              }
            },
            required: ["path"]
          }
        }
      end

      def self.call(path:, old_string: nil, new_string: nil, replace_all: false, edits: nil)
        return "Error: No path provided" if path.nil? || path.strip.empty?

        expanded = File.expand_path(path)

        return "Error: File not found: #{path}" unless File.exist?(expanded)
        return "Error: Not a file: #{path}" unless File.file?(expanded)

        content = File.binread(expanded)
        has_bom = content.start_with?("\xEF\xBB\xBF")
        content = content.byteslice(3..) if has_bom
        content = content.force_encoding("UTF-8")

        line_ending = detect_line_ending(content)
        content = content.gsub("\r\n", "\n") if line_ending == :crlf

        old_content = content.dup

        if edits.is_a?(Array) && !edits.empty?
          results = edits.map { |e| apply_edit(content, e["old_string"], e["new_string"], e["replace_all"]) }
          error = results.find { |r| r[:error] }
          return error[:error] if error

          results.each { |r| content = r[:content] }
          count = results.sum { |r| r[:count] }
        elsif old_string
          return "Error: No old_string provided" if old_string.nil? || old_string.empty?

          result = apply_edit(content, old_string, new_string, replace_all)
          return result[:error] if result[:error]

          content = result[:content]
          count = result[:count]
        else
          return "Error: Provide either old_string/new_string or edits array"
        end

        content = content.gsub("\n", "\r\n") if line_ending == :crlf
        content = "\xEF\xBB\xBF#{content}" if has_bom

        File.binwrite(expanded, content)

        clean_old = old_content.gsub("\r\n", "\n")
        clean_new = content.gsub("\r\n", "\n").gsub("\xEF\xBB\xBF", "")
        diff = format_diff(clean_old, clean_new, path)
        "Successfully edited #{path} (#{count} replacement#{'s' if count != 1})\n#{diff}"
      rescue => e
        "Error editing file: #{e.message}"
      end

      def self.apply_edit(content, old_string, new_string, replace_all = false)
        return { error: "Error: old_string not provided" } if old_string.nil? || old_string.empty?
        return { error: "Error: new_string not provided" } if new_string.nil?

        count = content.scan(Regexp.escape(old_string)).length

        if count == 0
          return { error: "Error: old_string not found in file. Make sure it matches exactly." }
        end

        if !replace_all && count > 1
          return { error: "Error: old_string found #{count} times. It must be unique, or use replace_all: true." }
        end

        if replace_all
          new_content = content.gsub(old_string, new_string)
        else
          new_content = content.sub(old_string, new_string)
        end

        { content: new_content, count: count }
      end

      def self.detect_line_ending(content)
        crlf_pos = content.index("\r\n")
        lf_pos = content.index("\n")
        return :lf if lf_pos.nil?
        return :lf if crlf_pos.nil?
        crlf_pos < lf_pos ? :crlf : :lf
      end

      def self.format_diff(old_text, new_text, path)
        require 'pastel'
        pastel = Pastel.new

        old_lines = old_text.lines.map(&:chomp)
        new_lines = new_text.lines.map(&:chomp)

        changes = Diff::LCS.sdiff(old_lines, new_lines)

        output = []
        output << pastel.dim("--- #{path}")
        output << pastel.dim("+++ #{path}")

        changes.each do |change|
          case change.action
          when "-"
            output << pastel.red("- #{change.old_element}")
          when "+"
            output << pastel.green("+ #{change.new_element}")
          when "!"
            output << pastel.red("- #{change.old_element}")
            output << pastel.green("+ #{change.new_element}")
          when "="
            output << pastel.dim("  #{change.old_element}")
          end
        end

        output.join("\n")
      end
    end

    module SearchFiles
      TOOL_NAME = "search_files"

      def self.prepare_arguments(args)
        args["context_lines"] = args["context_lines"].to_i if args["context_lines"]
        args
      end

      def self.definition
        {
          type: "function",
          function: {
            name: TOOL_NAME,
            description: "Search for a regex pattern in files. Returns matching file paths, line numbers, and context.",
            parameters: {
              type: "object",
              properties: {
                pattern: { type: "string", description: "The regex pattern to search for" },
                path: { type: "string", description: "The directory to search in. Defaults to current directory." },
                file_pattern: { type: "string", description: "Glob pattern to filter files (e.g. '*.rb'). Defaults to all files." },
                context_lines: { type: "integer", description: "Number of context lines to show around each match (default: 0)" }
              },
              required: ["pattern"]
            }
          }
        }
      end

      def self.anthropic_definition
        {
          name: TOOL_NAME,
          description: "Search for a regex pattern in files. Returns matching file paths, line numbers, and context.",
          input_schema: {
            type: "object",
            properties: {
              pattern: { type: "string", description: "The regex pattern to search for" },
              path: { type: "string", description: "The directory to search in. Defaults to current directory." },
              file_pattern: { type: "string", description: "Glob pattern to filter files (e.g. '*.rb'). Defaults to all files." },
              context_lines: { type: "integer", description: "Number of context lines to show around each match (default: 0)" }
            },
            required: ["pattern"]
          }
        }
      end

      def self.call(pattern:, path: ".", file_pattern: nil, context_lines: 0)
        return "Error: No pattern provided" if pattern.nil? || pattern.strip.empty?

        expanded = File.expand_path(path)
        context = [context_lines, 5].min

        if system("which rg > /dev/null 2>&1")
          search_with_rg(pattern, expanded, file_pattern, context)
        else
          search_with_grep(pattern, expanded, file_pattern, context)
        end
      rescue => e
        "Error searching files: #{e.message}"
      end

      def self.search_with_rg(pattern, path, file_pattern, context)
        cmd = ["rg", "--no-heading", "--line-number", "--color=never", "-E"]
        cmd << "-C" << context.to_s if context > 0
        cmd += ["--glob", "!{.git,node_modules,vendor,.bundle,tmp,log}"]
        cmd += ["--glob", file_pattern] if file_pattern
        cmd << "--max-count" << "500"
        cmd << pattern << path

        stdout, stderr, status = Open3.capture3(*cmd)

        return "No matches found." if status.exitstatus == 1
        return "Error: #{stderr}" unless status.success? || status.exitstatus == 2

        lines = stdout.lines
        if lines.length > 200
          "#{lines.first(200).join}\n... (truncated, #{lines.length - 200} more lines)"
        else
          stdout
        end
      end

      def self.search_with_grep(pattern, path, file_pattern, context)
        cmd = ["grep", "-rn", "--color=never", "-E"]
        cmd << "-C" << context.to_s if context > 0
        cmd += ["--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=vendor"]
        cmd += ["--exclude-dir=.bundle", "--exclude-dir=tmp", "--exclude-dir=log"]
        cmd += ["--include=#{file_pattern}"] if file_pattern
        cmd << "-m" << "500" if context == 0
        cmd << pattern << path

        stdout, _stderr, status = Open3.capture3(*cmd)

        return "No matches found." if status.exitstatus == 1

        lines = stdout.lines
        if lines.length > 200
          "#{lines.first(200).join}\n... (truncated, #{lines.length - 200} more lines)"
        else
          stdout
        end
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
