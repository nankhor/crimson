require "spec_helper"

RSpec.describe Crimson::Agent do
  let(:mock_client) { MockClient.new }
  let(:registry) { Crimson::ToolRegistry.new }
  let(:system_prompt) { "You are a helpful assistant." }

  module EchoTool
    TOOL_NAME = "echo"
    def self.definition
      { type: "function", function: { name: TOOL_NAME, description: "Echo", parameters: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } } }
    end
    def self.anthropic_definition
      { name: TOOL_NAME, description: "Echo", input_schema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } }
    end
    def self.call(text:)
      "echo: #{text}"
    end
  end

  class MockClient
    attr_accessor :responses

    def initialize
      @responses = []
      @call_count = 0
    end

    def chat(messages:, tools: [], &stream_callback)
      response = @responses[@call_count]
      @call_count += 1

      if response.nil?
        return [Crimson::Message::Assistant.new(content: "No more responses"), nil]
      end

      if block_given? && response[:stream_text]
        response[:stream_text].each_char do |char|
          stream_callback.call(char, nil)
        end
      end

      [response[:message], response[:usage]]
    end
  end

  before do
    registry.register(EchoTool)
    config = double("config", provider: :openai, model: "gpt-4o", api_key: "test", base_url: nil, max_tokens: 4096)
    allow(Crimson).to receive(:config).and_return(config)
  end

  subject(:agent) do
    described_class.new(
      client: mock_client,
      tool_registry: registry,
      system_prompt: system_prompt
    )
  end

  describe "#prompt" do
    it "emits agent_start and agent_end events" do
      events_received = []
      agent.on(Crimson::Agent::Events::AGENT_START) { |event, **| events_received << event }
      agent.on(Crimson::Agent::Events::AGENT_END) { |event, **| events_received << event }

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "Hello!"), usage: nil }
      ]

      agent.prompt("Hi")

      expect(events_received).to eq([:agent_start, :agent_end])
    end

    it "emits turn_start and turn_end events" do
      events_received = []
      agent.on(Crimson::Agent::Events::TURN_START) { |event, **| events_received << event }
      agent.on(Crimson::Agent::Events::TURN_END) { |event, **| events_received << event }

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "Hello!"), usage: nil }
      ]

      agent.prompt("Hi")

      expect(events_received).to eq([:turn_start, :turn_end])
    end

    it "emits message_update events for streaming text" do
      deltas = []
      agent.on(Crimson::Agent::Events::MESSAGE_UPDATE) { |_event, delta:, **| deltas << delta }

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "Hi there"), usage: nil, stream_text: "Hi there" }
      ]

      agent.prompt("Hello")

      expect(deltas.join).to eq("Hi there")
    end

    it "executes tool calls and continues the loop" do
      tool_events = []
      agent.on(Crimson::Agent::Events::TOOL_EXECUTION_START) { |_event, tool_name:, **| tool_events << { start: tool_name } }
      agent.on(Crimson::Agent::Events::TOOL_EXECUTION_END) { |_event, result:, **| tool_events << { end: result } }

      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "world" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "Done!"), usage: nil }
      ]

      agent.prompt("echo world")

      expect(tool_events).to eq([
        { start: "echo" },
        { end: "echo: world" }
      ])
    end

    it "adds tool results to history" do
      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "test" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "Got it"), usage: nil }
      ]

      agent.prompt("echo test")

      history = agent.history
      expect(history.any? { |m| m.is_a?(Crimson::Message::ToolResult) }).to be true
    end

    it "tracks token usage" do
      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "Hello"), usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }
      ]

      agent.prompt("Hi")

      expect(agent.token_usage).to eq({ prompt: 10, completion: 5, total: 15 })
    end

    it "accumulates token usage across turns" do
      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "x" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } },
        { message: Crimson::Message::Assistant.new(content: "Done"), usage: { prompt_tokens: 20, completion_tokens: 3, total_tokens: 23 } }
      ]

      agent.prompt("echo x")

      expect(agent.token_usage).to eq({ prompt: 30, completion: 8, total: 38 })
    end
  end

  describe "#steer" do
    it "injects steering message after tool calls" do
      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "first" }
      )

      tool_call2 = Crimson::Message::ToolCall.new(
        id: "tc-2",
        name: "echo",
        arguments: { "text" => "second" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call2]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "Steered!"), usage: nil }
      ]

      turn_count = 0
      agent.on(Crimson::Agent::Events::TURN_END) do
        turn_count += 1
        agent.steer("do something else") if turn_count == 1
      end

      agent.prompt("do stuff")

      expect(turn_count).to be >= 2
    end
  end

  describe "#follow_up" do
    it "injects follow-up message when agent would stop" do
      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "First response"), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "Follow-up response"), usage: nil }
      ]

      agent.on(Crimson::Agent::Events::TURN_END) do |_event, message:, **|
        if message.content == "First response"
          agent.follow_up("now summarize")
        end
      end

      agent.prompt("hello")

      expect(agent.history.last.content).to eq("Follow-up response")
    end
  end

  describe "#abort!" do
    it "stops the loop when abort is called" do
      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "first" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "Should not reach"), usage: nil }
      ]

      agent.on(Crimson::Agent::Events::TOOL_EXECUTION_END) do
        agent.abort!
      end

      agent.prompt("do stuff")

      expect(agent.history.count { |m| m.is_a?(Crimson::Message::Assistant) }).to eq(1)
    end
  end

  describe "hooks" do
    it "before_tool_call can block execution" do
      agent.before_tool_call do |tool_call:, args:, history:|
        { block: true, reason: "blocked!" }
      end

      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "test" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "ok"), usage: nil }
      ]

      agent.prompt("echo test")

      tool_results = agent.history.select { |m| m.is_a?(Crimson::Message::ToolResult) }
      expect(tool_results.first.content).to eq("Blocked: blocked!")
    end

    it "after_tool_call can modify result" do
      agent.after_tool_call do |tool_call:, result:, is_error:, history:|
        { result: "MODIFIED" }
      end

      tool_call = Crimson::Message::ToolCall.new(
        id: "tc-1",
        name: "echo",
        arguments: { "text" => "test" }
      )

      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: nil, tool_calls: [tool_call]), usage: nil },
        { message: Crimson::Message::Assistant.new(content: "ok"), usage: nil }
      ]

      agent.prompt("echo test")

      tool_results = agent.history.select { |m| m.is_a?(Crimson::Message::ToolResult) }
      expect(tool_results.first.content).to eq("MODIFIED")
    end
  end

  describe "#reset" do
    it "clears history and token usage" do
      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "Hello"), usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }
      ]

      agent.prompt("Hi")
      agent.reset

      expect(agent.history).to be_empty
      expect(agent.token_usage).to eq({ prompt: 0, completion: 0, total: 0 })
    end
  end

  describe "#save_history and #load_history" do
    it "saves and loads history" do
      mock_client.responses = [
        { message: Crimson::Message::Assistant.new(content: "Saved!"), usage: nil }
      ]

      agent.prompt("Test message")
      agent.save_history

      new_agent = described_class.new(
        client: mock_client,
        tool_registry: registry,
        system_prompt: system_prompt
      )

      result = new_agent.load_history
      expect(result).to eq("Loaded 2 messages")
      expect(new_agent.history.size).to eq(2)

      File.delete(Crimson::Agent::HISTORY_FILE) if File.exist?(Crimson::Agent::HISTORY_FILE)
    end
  end
end
