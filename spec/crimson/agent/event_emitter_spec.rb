require "spec_helper"

RSpec.describe Crimson::Agent::EventEmitter do
  subject(:emitter) { described_class.new }

  describe "#on and #emit" do
    it "calls handlers when event is emitted" do
      received = []
      emitter.on(:test) { |_event, **payload| received << payload }
      emitter.emit(:test, value: 42)

      expect(received).to eq([{ value: 42 }])
    end

    it "supports multiple handlers for the same event" do
      received = []
      emitter.on(:test) { |_event, **payload| received << "handler1: #{payload[:value]}" }
      emitter.on(:test) { |_event, **payload| received << "handler2: #{payload[:value]}" }
      emitter.emit(:test, value: 7)

      expect(received).to eq(["handler1: 7", "handler2: 7"])
    end

    it "does not call handlers for other events" do
      received = []
      emitter.on(:foo) { |_event, **payload| received << payload }
      emitter.emit(:bar, value: 1)

      expect(received).to be_empty
    end

    it "passes the event type as the first argument" do
      received_event = nil
      emitter.on(:test) { |event, **| received_event = event }
      emitter.emit(:test)

      expect(received_event).to eq(:test)
    end
  end

  describe "#off" do
    it "removes a specific handler" do
      received = []
      handler = emitter.on(:test) { |_event, **payload| received << payload }
      emitter.off(:test, handler)
      emitter.emit(:test, value: 1)

      expect(received).to be_empty
    end
  end

  describe "#clear" do
    it "removes all handlers" do
      received = []
      emitter.on(:test) { |_event, **payload| received << payload }
      emitter.on(:other) { |_event, **payload| received << payload }
      emitter.clear
      emitter.emit(:test, value: 1)
      emitter.emit(:other, value: 2)

      expect(received).to be_empty
    end
  end

  describe "#listener_count" do
    it "counts listeners for a specific event" do
      emitter.on(:test) { }
      emitter.on(:test) { }
      emitter.on(:other) { }

      expect(emitter.listener_count(:test)).to eq(2)
      expect(emitter.listener_count(:other)).to eq(1)
    end

    it "counts all listeners when no event specified" do
      emitter.on(:test) { }
      emitter.on(:test) { }
      emitter.on(:other) { }

      expect(emitter.listener_count).to eq(3)
    end
  end
end
