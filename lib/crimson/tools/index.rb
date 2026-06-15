# frozen_string_literal: true

require_relative "schema"
require_relative "diff_util"
require_relative "truncator"
require_relative "file_mutation_queue"
require_relative "read_file"
require_relative "write_file"
require_relative "edit_file"
require_relative "list_directory"
require_relative "run_command"
require_relative "search_files"
require_relative "glob"

module Crimson
  module Tools
    # All built-in tool modules available for registration.
    ALL = [ReadFile, WriteFile, EditFile, ListDirectory, RunCommand, SearchFiles, Glob].freeze
  end
end
