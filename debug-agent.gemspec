require_relative 'lib/debug_agent/version'

Gem::Specification.new do |spec|
  spec.name = 'debug-agent'
  spec.version = DebugAgent::VERSION
  spec.summary = 'AI-powered runtime debugging agent for Ruby applications'
  spec.description = 'Embed an AI debugging assistant into your Ruby web app. Inspect GC, threads, memory, ObjectSpace, routes, HTTP requests, and more.'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7'

  spec.files = Dir['lib/**/*.rb'] + ['README.md']
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.add_runtime_dependency 'json', '~> 2.6'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'sinatra', '~> 3.0'
end
