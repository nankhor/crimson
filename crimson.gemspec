require_relative "lib/crimson/version"

Gem::Specification.new do |spec|
  spec.name          = "crimson"
  spec.version       = Crimson::VERSION
  spec.authors       = ["cmoiadib"]
  spec.email         = ["cmoiadib@users.noreply.github.com"]

  spec.summary       = "A minimal Ruby-based coding agent"
  spec.description   = "Crimson is an open-source minimal coding agent that gets things done. " \
                        "Supports OpenAI, Anthropic, OpenRouter, Mistral, xAI, and custom providers."
  spec.homepage      = "https://github.com/cmoiadib/crimson"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "lib/**/*.rb",
    "skills/*.md",
    "exe/*",
    "README.md",
    "LICENSE.txt"
  ]

  spec.bindir        = "exe"
  spec.executables   = ["crimson"]

  spec.add_dependency "openai", "~> 0.66"
  spec.add_dependency "anthropic", "~> 1.48"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "reline", "~> 0.6"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "pry", "~> 0.16"
  spec.add_development_dependency "pry-byebug", "~> 3.12"
end
