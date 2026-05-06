# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "test_helper"

class CliTest < Minitest::Test
  BIN = File.expand_path("../bin/haml2html", __dir__)

  def test_stdin_stdout
    output, status = Open3.capture2(RbConfig.ruby, BIN, "--stdin", stdin_data: "%p Hi\n")
    assert status.success?
    assert_equal "<p>Hi</p>\n", output
  end

  def test_input_output_file
    Dir.mktmpdir do |dir|
      input = File.join(dir, "show.html.haml")
      output = File.join(dir, "show.html.erb")
      File.write(input, "%p Hi\n")

      _stdout, status = Open3.capture2(RbConfig.ruby, BIN, input, output)
      assert status.success?
      assert_equal "<p>Hi</p>\n", File.read(output)
    end
  end

  def test_diagnostics_exit_nonzero
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, BIN, "--stdin", stdin_data: ":unknown\n  x\n")
    refute status.success?
    assert_includes stderr, "unsupported filter"
  end
end
