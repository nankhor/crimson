require "spec_helper"

RSpec.describe Crimson::Agent::SteeringManager do
  subject(:manager) { described_class.new }

  describe "#steer and #has_steering?" do
    it "returns false when no steering messages" do
      expect(manager.has_steering?).to be false
    end

    it "returns true after a steering message is added" do
      manager.steer("stop!")
      expect(manager.has_steering?).to be true
    end
  end

  describe "#pop_steering" do
    it "returns nil when queue is empty" do
      expect(manager.pop_steering).to be_nil
    end

    it "returns messages in FIFO order" do
      manager.steer("first")
      manager.steer("second")

      expect(manager.pop_steering).to eq("first")
      expect(manager.pop_steering).to eq("second")
    end
  end

  describe "#pop_all_steering" do
    it "returns all messages and clears the queue" do
      manager.steer("a")
      manager.steer("b")
      manager.steer("c")

      result = manager.pop_all_steering
      expect(result).to eq(["a", "b", "c"])
      expect(manager.has_steering?).to be false
    end
  end

  describe "#follow_up and #has_follow_up?" do
    it "tracks follow-up messages separately from steering" do
      manager.steer("steer")
      manager.follow_up("follow")

      expect(manager.has_steering?).to be true
      expect(manager.has_follow_up?).to be true
    end
  end

  describe "#pop_all_follow_up" do
    it "returns all follow-up messages and clears" do
      manager.follow_up("x")
      manager.follow_up("y")

      result = manager.pop_all_follow_up
      expect(result).to eq(["x", "y"])
      expect(manager.has_follow_up?).to be false
    end
  end

  describe "#clear_all" do
    it "clears both steering and follow-up queues" do
      manager.steer("a")
      manager.follow_up("b")
      manager.clear_all

      expect(manager.has_steering?).to be false
      expect(manager.has_follow_up?).to be false
    end
  end

  describe "thread safety" do
    it "handles concurrent steer calls" do
      threads = 10.times.map do |i|
        Thread.new { manager.steer("msg-#{i}") }
      end
      threads.each(&:join)

      expect(manager.steering_count).to eq(10)
    end
  end
end
