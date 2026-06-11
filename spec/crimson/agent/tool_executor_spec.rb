require "spec_helper"

RSpec.describe Crimson::Agent::ToolExecutor do
  let(:registry) { Crimson::ToolRegistry.new }
  let(:events) { Crimson::Agent::EventEmitter.new }

  module TestTool
    TOOL_NAME = "test_tool"
    def self.call(value:)
      "result: #{value}"
    end
  end

  module FailingTool
    TOOL_NAME = "failing_tool"
    def self.call
      "Error: something went wrong"
    end
  end

  module SequentialTool
    TOOL_NAME = "sequential_tool"
    EXECUTION_MODE = :sequential
    def self.call(value:)
      "sequential: #{value}"
    end
  end

  before do
    registry.register(TestTool)
    registry.register(FailingTool)
    registry.register(SequentialTool)
  end

  let(:executor) { described_class.new(registry, events) }

  def make_tool_call(name, args = {})
    Crimson::Message::ToolCall.new(
      id: SecureRandom.uuid,
      name: name,
      arguments: args
    )
  end

  describe "#execute" do
    it "executes tool calls and returns results" do
      tc = make_tool_call("test_tool", { "value" => "hello" })
      results = executor.execute([tc], [])

      expect(results.size).to eq(1)
      expect(results[0][:result]).to eq("result: hello")
      expect(results[0][:is_error]).to be false
    end

    it "marks errors correctly" do
      tc = make_tool_call("failing_tool")
      results = executor.execute([tc], [])

      expect(results[0][:is_error]).to be true
    end

    it "executes multiple tools in parallel" do
      tcs = 3.times.map { |i| make_tool_call("test_tool", { "value" => i.to_s }) }
      results = executor.execute(tcs, [])

      expect(results.size).to eq(3)
      results.each { |r| expect(r[:is_error]).to be false }
    end

    it "falls back to sequential when tool has EXECUTION_MODE = :sequential" do
      tcs = [make_tool_call("sequential_tool", { "value" => "test" })]
      results = executor.execute(tcs, [])

      expect(results[0][:result]).to eq("sequential: test")
    end

    it "emits tool_execution_start and tool_execution_end events" do
      events_received = []
      events.on(:tool_execution_start) { |event, **payload| events_received << { event: event, **payload } }
      events.on(:tool_execution_end) { |event, **payload| events_received << { event: event, **payload } }

      tc = make_tool_call("test_tool", { "value" => "x" })
      executor.execute([tc], [])

      expect(events_received.size).to eq(2)
      expect(events_received[0][:event]).to eq(:tool_execution_start)
      expect(events_received[0][:tool_name]).to eq("test_tool")
      expect(events_received[1][:event]).to eq(:tool_execution_end)
      expect(events_received[1][:result]).to eq("result: x")
    end
  end

  describe "before_tool_call hook" do
    it "blocks execution when hook returns block: true" do
      blocking_executor = described_class.new(registry, events,
        before_hook: ->(tool_call:, args:, history:) {
          { block: true, reason: "not allowed" }
        }
      )

      tc = make_tool_call("test_tool", { "value" => "hello" })
      results = blocking_executor.execute([tc], [])

      expect(results[0][:result]).to eq("Blocked: not allowed")
      expect(results[0][:is_error]).to be true
    end

    it "allows execution when hook returns nil" do
      allowing_executor = described_class.new(registry, events,
        before_hook: ->(tool_call:, args:, history:) { nil }
      )

      tc = make_tool_call("test_tool", { "value" => "hello" })
      results = allowing_executor.execute([tc], [])

      expect(results[0][:result]).to eq("result: hello")
      expect(results[0][:is_error]).to be false
    end
  end

  describe "after_tool_call hook" do
    it "can modify the result" do
      modifying_executor = described_class.new(registry, events,
        after_hook: ->(tool_call:, result:, is_error:, history:) {
          { result: "modified: #{result}" }
        }
      )

      tc = make_tool_call("test_tool", { "value" => "hello" })
      results = modifying_executor.execute([tc], [])

      expect(results[0][:result]).to eq("modified: result: hello")
    end
  end
end
