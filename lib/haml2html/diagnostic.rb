# frozen_string_literal: true

module Haml2html
  Diagnostic = Struct.new(:filename, :line, :feature, :message, keyword_init: true) do
    def to_s
      location = [filename, line].compact.join(":")
      location = "haml" if location.empty?
      "#{location}: #{feature}: #{message}"
    end
  end

  class ConversionError < StandardError
    attr_reader :diagnostics

    def initialize(diagnostics)
      @diagnostics = diagnostics
      super(diagnostics.map(&:to_s).join("\n"))
    end
  end
end
