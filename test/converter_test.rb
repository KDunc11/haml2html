# frozen_string_literal: true

require_relative "test_helper"

class ConverterTest < Minitest::Test
  def convert(source)
    Haml2html::Converter.new(source, filename: "inline.haml").render
  end

  def test_plain_text
    assert_equal "Hello\n", convert("Hello\n")
  end

  def test_tag_with_static_attrs
    assert_equal "<p class=\"lead\" id=\"intro\">Hi</p>\n", convert("%p.lead#intro Hi\n")
  end

  def test_nested_tags
    assert_equal "<div>\n  <span>Hi</span>\n</div>\n", convert("%div\n  %span Hi\n")
  end

  def test_script
    assert_equal "<%= user.name %>\n", convert("= user.name\n")
  end

  def test_raw_script
    assert_equal "<%== html %>\n", convert("!= html\n")
  end

  def test_silent_script_block
    assert_equal "<% if ok %>\n  Yes\n<% end %>\n", convert("- if ok\n  Yes\n")
  end

  def test_interpolation
    assert_equal "Hi <%= name %>\n", convert("Hi \#{name}\n")
  end

  def test_comments
    assert_equal "<%# hidden %>\n<!-- shown -->\n", convert("-# hidden\n/ shown\n")
  end

  def test_common_filters
    assert_equal "hi\n<script>\n  alert(1)\n</script>\n", convert(":plain\n  hi\n:javascript\n  alert(1)\n")
  end

  def test_unknown_filter_diagnostic
    error = assert_raises(Haml2html::ConversionError) { convert(":markdown\n  hi\n") }
    assert_includes error.message, "inline.haml:1: filter :markdown: unsupported filter"
  end

  def test_dynamic_attribute_fallback
    assert_includes convert("%p{class: css_class} Hi\n"), "Haml::AttributeBuilder.build"
  end

  def test_object_ref_fallback
    assert_includes convert("%div[user]\n"), "Haml::AttributeBuilder.build"
  end
end
