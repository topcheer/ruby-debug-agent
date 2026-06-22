require_relative 'lib/debug_agent/version'

Gem::Specification.new do |spec|
  spec.name = 'debug-agent'
  spec.version = DebugAgent::VERSION
  spec.summary = 'AI-powered runtime debugging agent for Ruby applications'
  spec.description = 'Embed an AI debugging assistant into your Ruby web app. Inspect GC, threads, memory, ObjectSpace, routes, HTTP requests, Redis, Sidekiq, Puma, and more.'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7'
  spec.authors = ['ggcode']
  spec.email = ['noreply@ggcode.dev']
  spec.homepage = 'https://github.com/topcheer/ruby-debug-agent'
  spec.metadata = {
    'homepage_uri' => 'https://github.com/topcheer/ruby-debug-agent',
    'source_code_uri' => 'https://github.com/topcheer/ruby-debug-agent',
    'bug_tracker_uri' => 'https://github.com/topcheer/ruby-debug-agent/issues',
  }

  spec.files = Dir['lib/**/*.rb'] + ['README.md']
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  # Runtime dependency kept loose so it works across Ruby versions.
  spec.add_runtime_dependency 'json', '>= 2.6'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'

  # Optional runtime dependencies for inspectors and the demo app.
  # These are dev/test deps so the gem stays lightweight; the inspectors
  # themselves use defined?() checks and work without any of these installed.
  spec.add_development_dependency 'sinatra', '~> 4.0'
  spec.add_development_dependency 'redis', '~> 5.0'
  spec.add_development_dependency 'connection_pool', '~> 2.4'
  spec.add_development_dependency 'sidekiq', '~> 7.0'
  spec.add_development_dependency 'sqlite3', '~> 2.0'
  spec.add_development_dependency 'puma', '~> 6.0'
  spec.add_development_dependency 'rackup', '~> 2.0'
end
