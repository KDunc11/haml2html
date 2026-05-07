# haml2html

`haml2html` converts Haml templates to Rails ERB templates. It is built for Rails app migrations where rendered HTML equivalence matters more than preserving original source formatting.

## Install

```sh
gem install haml2html
```

Or in a Gemfile:

```ruby
gem "haml2html"
```

## CLI

```sh
haml2html app/views/posts/show.html.haml app/views/posts/show.html.erb
haml2html --stdin < app/views/posts/show.html.haml
```

The CLI writes to stdout unless an output path is provided. Unsupported syntax is reported with file and line diagnostics and exits nonzero.

## Ruby API

```ruby
require "haml2html"

erb = Haml2html::Converter.new("%p= post.title\n", filename: "show.html.haml").render
```

## Examples

Haml:

```haml
= form_with model: post do |form|
  = form.text_field :title
```

ERB:

```erb
<%= form_with model: post do |form| %>
  <%= form.text_field :title %>
<% end %>
```

Haml:

```haml
:ruby
  if published
    status = "Published"
  else
    status = "Draft"
  end
%p= status
```

ERB:

```erb
<%
if published
  status = "Published"
else
  status = "Draft"
end
%>
<p><%= status %></p>
```

## Supported

- Haml tags, nesting, static attributes, text, interpolation.
- Ruby output and control flow: `=`, `!=`, `- if`, `- each do`, and similar blocks.
- Public comments and silent comments.
- `:plain`, `:escaped`, `:javascript`, `:css`, `:erb`, and `:ruby` filters.
- Dynamic Haml attributes through Rails `tag.attributes`.

## Limitations

This is a migration tool, not a full source-preserving formatter. Output whitespace and quote style may differ from Haml output, while rendered HTML should remain equivalent for supported constructs. Unsupported filters or nodes fail with diagnostics instead of emitting known-wrong ERB.

Object references such as `%div[user]` are not converted yet.
