# frozen_string_literal: true

require "prism"

module RailsVis
  # One Prism pass over a Ruby source (a controller, or a template compiled by Templates.compile):
  # route helper calls with their form/redirect/def context, rendered partials and view components.
  class ViewScan
    FORM_CALLS = %i[form_with form_for form_tag button_to].freeze
    WRAPPER = "_rails_vis_template"

    attr_reader :error, :helpers, :partials, :components

    def initialize(source, path:)
      @helpers = []
      @partials = []
      @components = []
      result = Prism.parse(source)
      if (first = result.errors.first)
        @error = "#{path}: #{first.message} (line #{first.location.start_line})"
      end
      Collector.new(self).visit(result.value)
      @partials.uniq!
      @components.uniq!
    end

    def add_helper(hash) = @helpers << hash

    def add_partial(name) = @partials << name

    def add_component(name) = @components << name

    class Collector < Prism::Visitor
      HELPER = /\A(\w+)_(path|url)\z/

      def initialize(scan)
        super()
        @scan = scan
        @frames = [] # [:def, name] | [:form, method] | [:redirect]
      end

      def visit_def_node(node)
        @frames.push([:def, node.name.to_s])
        super
      ensure
        @frames.pop
      end

      def visit_call_node(node)
        helper(node) if node.name.match?(HELPER)
        render(node) if node.name == :render && node.receiver.nil?
        frame = frame_for(node)
        @frames.push(frame) if frame
        super
      ensure
        @frames.pop if frame
      end

      private

      def helper(node)
        form = @frames.reverse_each.find { |kind, _| kind == :form }
        name = @frames.reverse_each.find { |kind, _| kind == :def }&.last
        @scan.add_helper(
          "stem" => node.name.to_s[HELPER, 1], "name" => node.name.to_s, "receiver" => receiver_of(node.receiver),
          "line" => node.location.start_line, "form" => !form.nil?, "method" => form&.last,
          "redirect" => @frames.any? { |kind, _| kind == :redirect }, "def" => (name == WRAPPER ? nil : name)
        )
      end

      def receiver_of(recv)
        return nil if recv.nil?
        return recv.name.to_s if recv.is_a?(Prism::CallNode) && recv.receiver.nil? && recv.arguments.nil?
        :other
      end

      def frame_for(node)
        return unless node.receiver.nil?
        if FORM_CALLS.include?(node.name)
          [:form, nil]
        elsif node.name == :redirect_to
          [:redirect]
        elsif node.name == :link_to
          verb = link_method(node)
          [:form, verb] if verb
        end
      end

      # Downcased literal of `method: :delete` or `data: { turbo_method: :delete }`, or nil.
      def link_method(node)
        node.arguments&.arguments.to_a.grep(Prism::KeywordHashNode).each do |hash|
          found = pairs(hash)
          value = found["method"]
          value = pairs(found["data"])["turbo_method"] if value.nil? && found["data"].is_a?(Prism::HashNode)
          return value.unescaped.downcase if value.is_a?(Prism::SymbolNode) || value.is_a?(Prism::StringNode)
        end
        nil
      end

      def pairs(hash)
        hash.elements.grep(Prism::AssocNode).select { |e| e.key.is_a?(Prism::SymbolNode) }.to_h { |e| [e.key.unescaped, e.value] }
      end

      def render(node)
        first = node.arguments&.arguments&.first
        case first
        when Prism::StringNode then @scan.add_partial(first.unescaped)
        when Prism::KeywordHashNode
          value = pairs(first)["partial"]
          @scan.add_partial(value.unescaped) if value.is_a?(Prism::StringNode)
        when Prism::CallNode
          name = first.name == :new && constant_name(first.receiver)
          @scan.add_component(name) if name
        end
      end

      def constant_name(node)
        case node
        when Prism::ConstantReadNode then node.name.to_s
        when Prism::ConstantPathNode then node.full_name
        end
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
        nil
      end
    end
  end
end
