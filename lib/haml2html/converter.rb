# frozen_string_literal: true

require "cgi"
require "haml"

require_relative "diagnostic"

module Haml2html
  class Converter
    VOID_TAGS = %w[area base br col embed hr img input link meta param source track wbr].freeze
    SUPPORTED_FILTERS = %w[plain escaped javascript css erb ruby].freeze

    attr_reader :diagnostics

    def initialize(template, options = {})
      @template = template.respond_to?(:read) ? template.read : template.to_s
      @lines = @template.lines
      @filename = options[:filename]
      @diagnostics = []
    end

    def render
      ast = Haml::Parser.new(filename: @filename).call(@template)
      output = emit_children(ast.children, 0)
      raise ConversionError, diagnostics if diagnostics.any?

      output
    end

    private

    def emit_children(children, indent)
      children.map { |child| emit_node(child, indent) }.join
    end

    def emit_node(node, indent)
      case node.type
      when :root
        emit_children(node.children, indent)
      when :plain
        emit_plain(node, indent)
      when :tag
        emit_tag(node, indent)
      when :script
        emit_script(node, indent)
      when :silent_script
        emit_silent_script(node, indent)
      when :haml_comment
        "#{spaces(indent)}<%# #{node.value[:text].to_s.strip} %>\n"
      when :comment
        emit_comment(node, indent)
      when :doctype
        emit_doctype(node, indent)
      when :filter
        emit_filter(node, indent)
      else
        unsupported(node, node.type, "unsupported Haml node")
        ""
      end
    end

    def emit_plain(node, indent)
      text = interpolate_text(node.value[:text].to_s)
      "#{spaces(indent)}#{text}\n"
    end

    def emit_tag(node, indent)
      value = node.value
      name = value.fetch(:name)
      attrs = emit_attributes(node)
      open = "#{spaces(indent)}<#{name}#{attrs}>"
      close = "</#{name}>"

      if value[:self_closing] || (VOID_TAGS.include?(name) && node.children.empty? && blank?(value[:value]))
        return "#{spaces(indent)}<#{name}#{attrs}>\n"
      end

      inline = inline_tag_value(node)
      if node.children.empty? && !blank?(inline)
        return "#{open}#{inline}#{close}\n"
      end

      "#{open}\n#{emit_children(node.children, indent + 1)}#{spaces(indent)}#{close}\n"
    end

    def inline_tag_value(node)
      value = node.value
      return nil if value[:parse].nil? && blank?(value[:value])

      if value[:parse]
        marker = raw_script_line?(node) ? "<%==" : "<%="
        raw = "#{marker} #{value[:value].to_s.strip} %>"
        value[:preserve_script] ? raw : raw
      else
        interpolate_text(value[:value].to_s)
      end
    end

    def emit_attributes(node)
      value = node.value
      return runtime_attributes(value) if runtime_attributes?(value)

      attrs = value[:attributes].sort.map do |name, attr_value|
        %( #{name}="#{escape_attr(interpolate_text(attr_value.to_s))}")
      end
      attrs.join
    end

    def emit_script(node, indent)
      code = node.value[:text].to_s.strip
      if interpolated_string_literal?(code)
        return "#{spaces(indent)}#{interpolate_text(unquote_string_literal(code))}\n"
      end

      marker = raw_script_line?(node) ? "<%==" : "<%="
      if node.children.any?
        output = +"#{spaces(indent)}#{marker} #{code} %>\n"
        output << emit_children(node.children, indent + 1)
        output << "#{spaces(indent)}<% end %>\n" if closes_with_end?(node)
        output
      else
        "#{spaces(indent)}#{marker} #{code} %>\n"
      end
    end

    def emit_silent_script(node, indent)
      code = node.value[:text].to_s.strip
      output = +"#{spaces(indent)}<% #{code} %>\n"
      output << emit_children(node.children, indent + 1)
      output << "#{spaces(indent)}<% end %>\n" if closes_with_end?(node)
      output
    end

    def emit_comment(node, indent)
      conditional = node.value[:conditional]
      text = node.value[:text].to_s
      if conditional
        "#{spaces(indent)}<!--[#{conditional}]>#{text}<![endif]-->\n"
      elsif text.include?("\n")
        "#{spaces(indent)}<!--\n#{indent_block(text, indent + 1)}#{spaces(indent)}-->\n"
      else
        "#{spaces(indent)}<!-- #{text.strip} -->\n"
      end
    end

    def emit_doctype(node, indent)
      version = node.value[:version]
      type = node.value[:type].to_s
      html5 = version.nil? && type.empty?
      text = html5 ? "<!DOCTYPE html>" : "<!DOCTYPE html>"
      "#{spaces(indent)}#{text}\n"
    end

    def emit_filter(node, indent)
      name = node.value[:name].to_s
      text = node.value[:text].to_s

      unless SUPPORTED_FILTERS.include?(name)
        unsupported(node, "filter :#{name}", "unsupported filter")
        return ""
      end

      case name
      when "plain"
        indent_block(text, indent)
      when "escaped"
        indent_block(CGI.escapeHTML(text), indent)
      when "javascript"
        "#{spaces(indent)}<script>\n#{indent_block(text, indent + 1)}#{spaces(indent)}</script>\n"
      when "css"
        "#{spaces(indent)}<style>\n#{indent_block(text, indent + 1)}#{spaces(indent)}</style>\n"
      when "erb"
        indent_block(text, indent)
      when "ruby"
        "#{spaces(indent)}<%\n#{indent_block(text, indent)}#{spaces(indent)}%>\n"
      end
    end

    def runtime_attributes?(value)
      object_ref = value[:object_ref]
      return true unless object_ref.nil? || object_ref == :nil

      dynamic = value[:dynamic_attributes]
      return false unless dynamic

      dynamic_literals(dynamic).any?
    end

    def runtime_attributes(value)
      args = ["true", '"\\"".freeze', ":html", object_ref_literal(value[:object_ref])]
      args << value[:attributes].inspect unless value[:attributes].empty?
      args.concat(dynamic_literals(value[:dynamic_attributes]))

      %(<%== (require "haml"; ::Haml::AttributeBuilder.build(#{args.join(", ")})) %>)
    end

    def object_ref_literal(object_ref)
      return "nil" if object_ref.nil? || object_ref == :nil

      object_ref
    end

    def dynamic_literals(dynamic)
      return [] unless dynamic

      [dynamic.new, stripped_old_dynamic_literal(dynamic.old)].compact
    end

    def stripped_old_dynamic_literal(old)
      return nil if old.nil?

      old.dup.sub(/\A{/, "").sub(/}\z/m, "")
    end

    def diagnose_object_ref(node, value)
      object_ref = value[:object_ref]
      return if object_ref.nil? || object_ref == :nil

      unsupported(node, "object reference", "object references cannot be faithfully converted to inline attrs")
    end

    def diagnose_dynamic_attributes(node, value)
      dynamic = value[:dynamic_attributes]
      return unless dynamic

      if dynamic.respond_to?(:new) && dynamic.new
        unsupported(node, "dynamic attributes", "new-style dynamic attributes are not supported")
      end

      if dynamic.respond_to?(:old) && dynamic.old
        unsupported(node, "dynamic attributes", "old-style dynamic attributes are not supported")
      end
    end

    def closes_with_end?(node)
      keyword = node.value[:keyword].to_s
      return true if %w[if unless case begin for while until].include?(keyword)

      node.value[:text].to_s.match?(/\bdo(\s*\|.*\|)?\s*\z/)
    end

    def interpolate_text(text)
      text.gsub(/#\{([^{}]+)\}/, '<%= \1 %>')
    end

    def interpolated_string_literal?(code)
      code.match?(/\A"(?:[^"\\]|\\.|#\{[^{}]+\})*"\z/)
    end

    def unquote_string_literal(code)
      code[1...-1].gsub('\"', '"').gsub('\n', "\n")
    end

    def escape_attr(value)
      value.gsub("&", "&amp;").gsub('"', "&quot;")
    end

    def indent_block(text, indent)
      text.to_s.each_line.map { |line| "#{spaces(indent)}#{line}" }.join
    end

    def unsupported(node, feature, message)
      diagnostics << Diagnostic.new(filename: @filename, line: node.line, feature: feature.to_s, message: message)
    end

    def raw_script_line?(node)
      line = @lines.fetch(node.line.to_i - 1, "")
      line.lstrip.start_with?("!=") || line.include?("!=")
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

    def spaces(indent)
      "  " * indent
    end
  end
end
