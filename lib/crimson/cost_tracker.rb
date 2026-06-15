# frozen_string_literal: true

module Crimson
  # Model pricing in USD per million tokens.
  # @!parse
  #   MODEL_PRICING = Hash[String, Hash]
  MODEL_PRICING = {
    "gpt-4o" => { input: 2.50, output: 10.00 },
    "gpt-4o-mini" => { input: 0.15, output: 0.60 },
    "gpt-4-turbo" => { input: 10.00, output: 30.00 },
    "gpt-3.5-turbo" => { input: 0.50, output: 1.50 },
    "claude-sonnet-4-20250514" => { input: 3.00, output: 15.00 },
    "claude-3-5-sonnet-20241022" => { input: 3.00, output: 15.00 },
    "claude-3-5-haiku-20241022" => { input: 0.80, output: 4.00 },
    "claude-3-opus-20240229" => { input: 15.00, output: 75.00 },
    "claude-3-haiku-20240307" => { input: 0.25, output: 1.25 }
  }

  # Per-model cost tracking for API usage.
  class CostTracker
    # @return [Float] accumulated cost in USD
    attr_reader :total_cost

    def initialize
      @total_cost = 0.0
      @cost_breakdown = []
    end

    # Record usage for a single turn.
    # @param model [String] model name
    # @param usage [Hash, nil] token usage with prompt_tokens/completion_tokens
    # @return [Hash] input/output/total cost for this turn
    def track(model, usage)
      pricing = MODEL_PRICING[model]
      return { input: 0, output: 0, total: 0 } unless pricing && usage

      prompt_tokens = usage[:prompt_tokens] || usage["prompt_tokens"] || usage[:prompt] || 0
      completion_tokens = usage[:completion_tokens] || usage["completion_tokens"] || usage[:completion] || 0

      input_cost = (pricing[:input] / 1_000_000.0) * prompt_tokens
      output_cost = (pricing[:output] / 1_000_000.0) * completion_tokens
      turn_cost = input_cost + output_cost

      @total_cost += turn_cost
      @cost_breakdown << { input: input_cost, output: output_cost, total: turn_cost }

      { input: input_cost, output: output_cost, total: turn_cost }
    end

    # @return [Array<Hash>] per-turn cost breakdown
    def breakdown
      @cost_breakdown.dup
    end

    # Reset all tracked costs.
    # @return [void]
    def reset
      @total_cost = 0.0
      @cost_breakdown = []
    end
  end
end
