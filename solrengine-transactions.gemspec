require_relative "lib/solrengine/transactions/version"

Gem::Specification.new do |spec|
  spec.name = "solrengine-transactions"
  spec.version = Solrengine::Transactions::VERSION
  spec.authors = [ "Jose Ferrer" ]
  spec.email = [ "estoy@moviendo.me" ]

  spec.summary = "SOL transfer model, confirmation tracking, and Stimulus controller for Rails"
  spec.description = "Transfer model concern, transaction confirmation background job, and @solana/kit Stimulus controller for building and signing Solana transactions."
  spec.homepage = "https://github.com/solrengine/transactions"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "LICENSE", "README.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 7.1"
  spec.add_dependency "solrengine-rpc", "~> 0.1"
end
