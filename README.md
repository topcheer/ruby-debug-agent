# Ruby Debug Agent

An AI-powered runtime debugging agent that embeds directly into your Ruby application. Add one gem, configure an LLM key, and chat with your live app at `/agent` to inspect GC, threads, object counts, HTTP requests, and more.

## Quick Start

### 1. Install

```bash
gem install debug-agent
```

Or in Gemfile:
```ruby
gem 'debug-agent'
```

### 2. Integrate (Rack / Rails)

```ruby
require 'debug_agent'

# Add as Rack middleware (works with Rails, Sinatra, etc.)
use DebugAgent::RackMiddleware
```

### Sinatra

```ruby
require 'debug_agent'
require 'sinatra'

DebugAgent.install_sinatra(self)
```

### 3. Configure LLM

```bash
export LLM_API_KEY=your-key
export LLM_BASE_URL=https://api.openai.com/v1  # optional
export LLM_MODEL=gpt-4o                         # optional
```

### 4. Run and open

```
http://localhost:4567/agent
```

## Built-in Tools (13+)

| Tool | Description |
|------|-------------|
| `get_gc_stats` | GC collection count, live objects, heap pages |
| `get_memory_summary` | RSS, object counts by type |
| `trigger_gc` | Force GC with before/after comparison |
| `get_thread_summary` | Thread count and list |
| `get_runtime_info` | Ruby version, platform, PID |
| `get_object_allocations` | ObjectSpace allocation breakdown |
| `get_recent_requests` | HTTP request ring buffer |
| `get_error_requests` | Error requests (4xx/5xx) |
| `get_request_stats` | P50/P95/P99 latency, error rate |
| `get_system_info` | Hostname, CPU, process count |
| `get_disk_usage` | Disk usage via df |
| `get_environment_variables` | Environment variables (masked secrets) |
| `get_process_info` | PID, RSS, user |

## Custom Tools

```ruby
require 'debug_agent'

DebugAgent.register_tool('check_sidekiq', 'Check Sidekiq queue stats') do
  { queues: ['default', 'mailers'], total_jobs: 42 }
end
```

## Run the Demo

```bash
export LLM_API_KEY=your-key
ruby demo/app.rb
# Open http://localhost:4567/agent
```

## License

MIT
