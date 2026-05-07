require_relative "lib/haml2html/version"

Gem::Specification.new do |gem|
  gem.name = "haml2html"
  gem.version = Haml2html::VERSION
  gem.authors = ["Kyle"]
  gem.email = ["kyle.duncan.dev@gmail.com"]
  gem.summary = "Convert Haml templates to Rails ERB."
  gem.description = "A Haml-to-ERB migration tool for Rails templates."
  gem.homepage = "https://github.com/KDunc11/haml2html"
  gem.license = "MIT"
  gem.required_ruby_version = ">= 3.2"
  gem.metadata = {
    "homepage_uri" => gem.homepage,
    "source_code_uri" => "#{gem.homepage}/tree/main",
    "changelog_uri" => "#{gem.homepage}/blob/main/CHANGELOG.md"
  }

  gem.files = Dir["bin/*", "lib/**/*.rb", "CHANGELOG.md", "LICENSE", "README.md"].select { |path| File.file?(path) }
  gem.bindir = "bin"
  gem.executables = ["haml2html"]
  gem.require_paths = ["lib"]

  gem.add_dependency "haml", "~> 6.3"
  gem.add_development_dependency "actionview", ">= 7.0", "< 9.0"
  gem.add_development_dependency "herb", "~> 0.10"
  gem.add_development_dependency "minitest", "~> 5.0"
  gem.add_development_dependency "rake", "~> 13.0"
end
