Gem::Specification.new do |spec|
  spec.name          = "lita-rundeck"
  spec.version       = "0.0.2"
  spec.authors       = ["Harlan Barnes"]
  spec.email         = ["hbarnes@pobox.com"]
  spec.description   = %q{Lita handler for interacting with Rundeck}
  spec.summary       = %q{Lita handler for interacting with Rundeck}
  spec.homepage      = "https://github.com/harlanbarnes/lita-rundeck"
  spec.license       = "MIT"
  spec.metadata      = { "lita_plugin_type" => "handler" }

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "lita", ">= 3.3"
  spec.add_runtime_dependency "xml-simple", ">= 1.1.4"
  spec.add_runtime_dependency "lita-keyword-arguments"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", ">= 3.0.0"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "coveralls"
end
