# frozen_string_literal: true

require "action_view"
require "nokogiri"
require "tmpdir"
require_relative "test_helper"

class RenderEquivalenceTest < Minitest::Test
  def test_rails_escaped_output_equivalence
    assert_render_equivalent("%p= name\n", name: "<Kyle>")
  end

  def test_nested_markup_equivalence
    assert_render_equivalent(<<~HAML, name: "Kyle")
      %section.panel
        %h1 Hi \#{name}
        %p= message
    HAML
  end

  def test_comment_and_filter_equivalence
    assert_render_equivalent(<<~HAML)
      / shown
      -# hidden
      :javascript
        alert("ok")
    HAML
  end

  def test_dynamic_attribute_equivalence
    assert_render_equivalent(<<~HAML, css_class: "active", enabled: true)
      %button{class: ["btn", css_class], data: {controller: :menu}, disabled: !enabled} Save
    HAML
  end

  def test_object_ref_equivalence
    assert_render_equivalent("%div[user]\n", user: User.new(7))
  end

  private

  User = Struct.new(:id)

  def assert_render_equivalent(haml, locals = {})
    erb = Haml2html::Converter.new(haml, filename: "fixture.html.haml").render
    assert_equal normalize_html(render_haml(haml, locals)), normalize_html(render_erb(erb, locals))
  end

  def render_haml(source, locals)
    code = Haml::Engine.new.call(source)
    context = binding
    default_locals.merge(locals).each { |name, value| context.local_variable_set(name, value) }
    eval(code, context)
  end

  def render_erb(source, locals)
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "fixtures"))
      File.write(File.join(dir, "fixtures", "show.html.erb"), source)
      view = ActionView::Base.with_empty_template_cache.with_view_paths([dir])
      view.render(template: "fixtures/show", locals: default_locals.merge(locals))
    end
  end

  def default_locals
    { message: "Welcome" }
  end

  def normalize_html(html)
    fragment = Nokogiri::HTML.fragment(html)
    fragment.xpath(".//text()[normalize-space(.) = '']").remove
    fragment.to_html
  end
end
