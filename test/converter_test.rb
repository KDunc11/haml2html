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

  def test_script_block
    assert_equal <<~ERB, convert("= form_with model: user do |f|\n  = f.text_field :name\n")
      <%= form_with model: user do |f| %>
        <%= f.text_field :name %>
      <% end %>
    ERB
  end

  def test_raw_script
    assert_equal "<%== html %>\n", convert("!= html\n")
  end

  def test_inline_raw_script
    assert_equal "<p><%== html %></p>\n", convert("%p!= html\n")
  end

  def test_ruby_not_equal_expression_is_not_raw_script
    assert_equal "<%= html != \"\" ? html : \"\" %>\n", convert("= html != \"\" ? html : \"\"\n")
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

  def test_ruby_filter
    assert_equal <<~ERB, convert(":ruby\n  count = 1\n  name = \"Kyle\"\n%p= name\n")
      <%
      count = 1
      name = "Kyle"
      %>
      <p><%= name %></p>
    ERB
  end

  def test_multiline_ruby_filter
    assert_equal <<~ERB, convert(":ruby\n  if enabled\n    value = \"yes\"\n  else\n    value = \"no\"\n  end\n%p= value\n")
      <%
      if enabled
        value = "yes"
      else
        value = "no"
      end
      %>
      <p><%= value %></p>
    ERB
  end

  def test_unknown_filter_diagnostic
    error = assert_raises(Haml2html::ConversionError) { convert(":markdown\n  hi\n") }
    assert_includes error.message, "inline.haml:1: filter :markdown: unsupported filter"
  end

  def test_simple_dynamic_class_attribute
    erb = convert("%p{class: css_class} Hi\n")

    assert_equal "<p class=\"<%= css_class %>\">Hi</p>\n", erb
    refute_includes erb, "Haml::AttributeBuilder"
    refute_includes erb, "require \"haml\""
  end

  def test_dynamic_class_merges_with_static_class
    assert_equal "<div class=\"accordion__header <%= selectors %>\" type=\"button\"></div>\n",
                 convert(".accordion__header{ type: \"button\", class: selectors }\n")
  end

  def test_simple_data_attributes
    assert_equal "<div data-controller=\"simple-accordion\"></div>\n",
                 convert("%div{ data: { controller: \"simple-accordion\" } }\n")
  end

  def test_dynamic_data_attributes
    assert_equal "<div data-controller=\"<%= controller %>\"></div>\n",
                 convert("%div{ data: { controller: controller } }\n")
  end

  def test_complex_dynamic_attributes_emit_without_rails_tag_attributes
    erb = convert("%button{class: [\"btn\", css_class], data: {controller: :menu}, disabled: !enabled} Save\n")

    assert_equal "<button class=\"<%= class_names(\"btn\", css_class) %>\" data-controller=\"menu\"<%= (!enabled) ? \" disabled\" : \"\" %>>Save</button>\n",
                 erb
    refute_match(/tag[.]attributes/, erb)
  end

  def test_opaque_dynamic_attributes_are_unsupported
    error = assert_raises(Haml2html::ConversionError) { convert("%div{foo_attrs}\n") }

    assert_includes error.message, "inline.haml:1: dynamic attributes: only literal dynamic attribute hashes can be converted safely"
  end

  def test_object_ref_diagnostic
    error = assert_raises(Haml2html::ConversionError) { convert("%div[user]\n") }

    assert_includes error.message, "inline.haml:1: object reference: object references cannot be faithfully converted to inline attrs"
  end
end
