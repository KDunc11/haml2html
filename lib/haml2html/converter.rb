# frozen_string_literal: true

require "cgi"
require "haml"
require "ripper"

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
      return "#{open}#{close}\n" if node.children.empty?

      "#{open}\n#{emit_children(node.children, indent + 1)}#{spaces(indent)}#{close}\n"
    end

    def inline_tag_value(node)
      value = node.value
      return nil if value[:parse].nil? && blank?(value[:value])

      if value[:parse]
        marker = raw_script?(node) ? "<%==" : "<%="
        raw = "#{marker} #{value[:value].to_s.strip} %>"
        value[:preserve_script] ? raw : raw
      else
        interpolate_text(value[:value].to_s)
      end
    end

    def emit_attributes(node)
      value = node.value
      attrs = value[:attributes].dup
      diagnose_object_ref(node, value)

      dynamic = dynamic_attributes_expression(value[:dynamic_attributes])
      return static_attributes(attrs) unless dynamic

      if (simple_attrs = simple_dynamic_attributes(dynamic))
        dynamic_class = simple_attrs.delete("class")
        return "#{static_attributes(attrs, dynamic_class: dynamic_class)}#{simple_attrs.map { |name, attr_value| dynamic_attribute(name, attr_value) }.join}"
      end

      "#{static_attributes(attrs)}#{dynamic_attributes(dynamic)}"
    end

    def emit_script(node, indent)
      code = node.value[:text].to_s.strip
      if interpolated_string_literal?(code)
        return "#{spaces(indent)}#{interpolate_text(unquote_string_literal(code))}\n"
      end

      marker = raw_script?(node) ? "<%==" : "<%="
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

    def static_attributes(attrs, dynamic_class: nil)
      emitted_attrs = attrs.dup
      emitted_attrs["class"] = "" if dynamic_class && !emitted_attrs.key?("class")

      emitted_attrs.sort.map do |name, attr_value|
        value = escape_attr(interpolate_text(attr_value.to_s))
        value = value.empty? ? dynamic_class : "#{value} #{dynamic_class}" if name == "class" && dynamic_class
        %( #{name}="#{value}")
      end.join
    end

    def dynamic_attributes(dynamic)
      %(<%== (_haml2html_attrs = tag.attributes(**#{dynamic})).empty? ? "" : " \#{_haml2html_attrs}" %>)
    end

    def dynamic_attribute(name, value)
      %( #{name}="#{value}")
    end

    def simple_dynamic_attributes(dynamic)
      program = Ripper.sexp(dynamic)
      hash = program&.dig(1, 0)
      return nil unless hash&.first == :hash

      associations = hash.dig(1, 1)
      return nil unless associations.is_a?(Array)

      associations.each_with_object({}) do |association, attrs|
        return nil unless association&.first == :assoc_new

        label = association[1]
        return nil unless label&.first == :@label

        value = simple_dynamic_attribute_value(association[2])
        return nil unless value

        attrs[label[1].delete_suffix(":")] = value
      end
    end

    def simple_dynamic_attribute_value(node)
      case node&.first
      when :string_literal
        escape_attr(string_literal_content(node))
      when :vcall
        ident = node.dig(1, 1)
        return nil unless ident

        "<%= #{ident} %>"
      end
    end

    def string_literal_content(node)
      content = node.dig(1, 1, 1)
      content.to_s
    end

    def dynamic_attributes_expression(dynamic)
      return nil unless dynamic

      expressions = [dynamic.new, dynamic.old].compact
      return nil if expressions.empty?
      return expressions.first if expressions.one?

      expressions.reduce("{}") { |merged, expression| "#{merged}.merge(#{expression})" }
    end

    def diagnose_object_ref(node, value)
      object_ref = value[:object_ref]
      return if object_ref.nil? || object_ref == :nil

      unsupported(node, "object reference", "object references cannot be faithfully converted to inline attrs")
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

    def raw_script?(node)
      return true if node.type == :tag && node.value[:preserve_script] == false

      line = @lines.fetch(node.line.to_i - 1, "")
      line.lstrip.start_with?("!=")
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

    def spaces(indent)
      "  " * indent
    end
  end
end
