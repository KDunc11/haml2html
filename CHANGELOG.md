# Changelog

## 0.1.4

- Remove the `tag.attributes` fallback and emit literal dynamic attributes directly.

## 0.1.3

- Fix generated ERB for Haml attributes with mixed static and dynamic classes.

## 0.1.2

- Raise the minimum supported Ruby version to 3.2.
- Switch diagnostics back to `Data.define`.

## 0.1.1

- Add support for `:ruby` filters.
- Support loud Haml script blocks.

## 0.1.0

- Initial Haml-to-ERB converter.
- CLI for stdin/stdout and explicit input/output files.
- Rails render-equivalence test coverage for common Haml constructs.
