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

## Supported

- Haml tags, nesting, static attributes, text, interpolation.
- Ruby output and control flow: `=`, `!=`, `- if`, `- each do`, and similar blocks.
- Public comments and silent comments.
- `:plain`, `:escaped`, `:javascript`, `:css`, and `:erb` filters.
- Dynamic Haml attributes and object references through `Haml::AttributeBuilder`.

Generated ERB may call `Haml::AttributeBuilder` for dynamic attributes and object references. Keep `haml` available at runtime until those converted templates are simplified.

## Limitations

This is a migration tool, not a full source-preserving formatter. Output whitespace and quote style may differ from Haml output, while rendered HTML should remain equivalent for supported constructs. Unsupported filters or nodes fail with diagnostics instead of emitting known-wrong ERB.

Batch directory conversion is planned after the single-file converter is stable.

## Publishing Checklist

1. Verify gemspec URLs match the final repository URL.
2. Run `rake test`.
3. Run `gem build haml2html.gemspec --strict`.
4. Inspect package contents with `gem spec haml2html-0.1.0.gem files`.
5. Publish with RubyGems MFA enabled.
