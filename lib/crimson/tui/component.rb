# frozen_string_literal: true

module Crimson
  module Tui
    # Base component interface - all components must implement render(width) -> string[]
    class Component
      # Render the component to lines for the given viewport width
      # Returns Array of strings, each representing a line
      def render(width)
        raise NotImplementedError, "#{self.class}#render must be implemented"
      end

      # Invalidate cached rendering state
      def invalidate
        # Default no-op
      end
    end

    # Container that holds child components and renders them sequentially
    class Container < Component
      def initialize
        super()
        @children = []
      end

      def add_child(child)
        @children << child
        self
      end

      def remove_child(child)
        @children.delete(child)
        self
      end

      def clear_children
        @children.clear
        self
      end

      def render(width)
        lines = []
        @children.each do |child|
          lines.concat(child.render(width))
        end
        lines
      end

      def invalidate
        super
        @children.each(&:invalidate)
      end
    end
  end
end
