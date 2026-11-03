# frozen_string_literal: true

require "prism"

module RailsVis
  # Statically reads one method body: which constants it touches and which Inertia component it renders.
  class BodyScan
    attr_reader :constants, :inertia_component

    def initialize(path, method_name, line)
      @constants = []
      @inertia_component = nil
      definition = find_def(Prism.parse_file(path.to_s).value, method_name.to_sym, line)
      definition&.body&.accept(Collector.new(self))
      @constants.uniq!
    end

    def add_constant(name) = @constants << name

    def inertia!(component) = @inertia_component ||= component

    private

    def find_def(node, name, line)
      return node if node.is_a?(Prism::DefNode) && node.name == name && node.location.start_line == line
      node.compact_child_nodes.each do |child|
        found = find_def(child, name, line)
        return found if found
      end
      nil
    end

    class Collector < Prism::Visitor
      def initialize(scan)
        super()
        @scan = scan
      end

      def visit_constant_read_node(node) = @scan.add_constant(node.name.to_s)

      def visit_constant_path_node(node)
        @scan.add_constant(node.full_name)
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
        super # e.g. self.class::FOO: no static name, but keep walking the parts
      end

      def visit_call_node(node)
        inertia(node) if node.name == :render
        super
      end

      private

      def inertia(call)
        hash = call.arguments&.arguments&.first
        return unless hash.is_a?(Prism::KeywordHashNode)
        pair = hash.elements.find { |e| e.is_a?(Prism::AssocNode) && e.key.is_a?(Prism::SymbolNode) && e.key.unescaped == "inertia" }
        return unless pair
        @scan.inertia!(pair.value.is_a?(Prism::StringNode) ? pair.value.unescaped : :dynamic)
      end
    end
  end
end
