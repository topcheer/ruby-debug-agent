# Ruby Debug Agent

[![Gem Version](https://img.shields.io/badge/gem-debug--agent-red)](https://github.com/topcheer/ruby-debug-agent)
![Tools](https://img.shields.io/badge/tools-54-blue)
![Inspectors](https://img.shields.io/badge/inspectors-20-green)

An AI-powered runtime debugging agent that embeds directly into your Ruby application. Add one gem, configure an LLM key, and chat with your live app at `/agent` to inspect GC, ObjectSpace, threads, routes, Redis, Rails models/routes, Sidekiq queues, Puma stats, fibers/signals, process info, HTTP requests, and more — **54 diagnostic tools across 20 inspectors**.

## Quick Start

### 1. Install

```bash
# Gemfile
gem 'debug-agent', github: 'topcheer/ruby-debug-agent'
```

Or install directly:

```bash
gem install debug-agent --source https://github.com/topcheer/ruby-debug-agent
```

### 2. Integrate (Sinatra)

```ruby
require 'sinatra/base'
require 'debug_agent'

class MyApp < Sinatra::Base
  # One line to integrate
  register DebugAgent::Middleware
end
```

### 3. Configure LLM

```bash
export LLM_API_KEY=your-key
export LLM_BASE_URL=https://open.bigmodel.cn/api/coding/paas/v4  # default
export LLM_MODEL=glm-5.2                                          # default
```

Supports any OpenAI-compatible endpoint.

### 4. Run and open

```
http://localhost:4567/agent
```

## Features

- **Streaming AI responses** with real-time tool call badges (pending / success / error)
- **Context compression** — automatically summarizes old conversation when token limit is approached
- **Dark-themed chat UI** with full markdown rendering (tables, code blocks, lists)
- **Max tool rounds** (25) with forced final summary when limit is reached
- **54 diagnostic tools** across **20 inspectors**
- Zero external dependencies (no Datadog, no Grafana, no APM)

## Inspectors & Tools (54)

### GC Inspector
| Tool | Description |
|------|-------------|
| `get_gc_stats` | GC.stat details: count, heap pages, slots, total allocated objects |
| `get_gc_profiler` | GC::Profiler data if available |
| `force_gc` | Trigger full GC (GC.start full_mark: true) |

### ObjectSpace Inspector
| Tool | Description |
|------|-------------|
| `get_object_space_stats` | ObjectSpace.count_objects summary by type |
| `get_memory_size` | Total memory size of all objects (memsize_of_all) |
| `get_object_count_by_class` | Top N classes by instance count |

### Thread Inspector
| Tool | Description |
|------|-------------|
| `get_thread_list` | List all threads with status and backtrace summary |
| `get_thread_count` | Thread count |
| `get_main_thread_info` | Main thread priority, status |
| `get_thread_backtrace` | Full backtrace for a specific thread |

### Route Inspector
| Tool | Description |
|------|-------------|
| `get_routes` | Discover Sinatra/Rails routes |
| `get_middleware_stack` | List Rack middleware |

### Process Inspector
| Tool | Description |
|------|-------------|
| `get_process_info` | PID, ppid, platform, Ruby version, uptime |
| `get_cpu_time` | Process.times() user/sys CPU time |
| `get_environment_variables` | Environment variables (masked secrets) |
| `get_process_memory` | Process RSS, VMS, and memory growth trend |

### Runtime Inspector
| Tool | Description |
|------|-------------|
| `get_ruby_info` | Ruby version, engine, platform, RUBYOPT |
| `get_memory_info` | RSS memory usage |
| `get_load_average` | System load average |

### HTTP Tracker Inspector
| Tool | Description |
|------|-------------|
| `get_recent_requests` | Recent HTTP requests ring buffer |
| `get_slow_requests` | Slowest requests by duration |
| `get_error_requests` | Error requests (4xx/5xx) |
| `get_request_stats` | P50/P95/P99 latency, error rate |

### System Inspector
| Tool | Description |
|------|-------------|
| `get_system_info` | Hostname, CPU cores, disk |
| `get_disk_usage` | Disk usage for the working directory |
| `get_file_descriptors` | Open file descriptor count |

### Redis Inspector
| Tool | Description |
|------|-------------|
| `get_redis_info` | Redis server info: memory, clients, persistence |
| `get_redis_keys` | Scan Redis keyspace with pattern matching |
| `get_redis_slowlog` | Redis slow query log entries |
| `get_redis_stats` | Per-command call count, hit/miss ratio, keyspace stats |

### Rails Inspector
| Tool | Description |
|------|-------------|
| `get_rails_models` | List ActiveRecord models with table names and associations |
| `get_rails_routes` | List Rails routes with helper names and HTTP verbs |
| `get_rails_db_schema` | Database schema version and pending migrations |

### Sidekiq Inspector
| Tool | Description |
|------|-------------|
| `get_sidekiq_queues` | Queue list with depth, latency, and size |
| `get_sidekiq_workers` | Active Sidekiq workers with job and host info |
| `get_sidekiq_jobs` | Inspect jobs in a queue/retry set with payload |

### Puma Inspector
| Tool | Description |
|------|-------------|
| `get_puma_stats` | Puma cluster stats: workers, threads, running/backlog, boot time |

### Fibers/Signals Inspector
| Tool | Description |
|------|-------------|
| `get_fiber_list` | List active Ruby Fibers with state and backtrace |
| `get_signal_handlers` | List registered signal handlers (Signal.trap) |
| `get_trap_handlers` | Inspect trap handlers for SIGINT, SIGTERM, etc. |

### Logging Inspector
| Tool | Description |
|------|-------------|
| `get_log_buffer` | Recent log entries from the built-in ring buffer |
| `get_logger_info` | Current log level and configuration for registered loggers |
| `set_log_level` | Dynamically set the log level for a registered logger |

### Cache Inspector
| Tool | Description |
|------|-------------|
| `get_cache_stats` | Stats for registered caches (hit rate, miss count, key count) |
| `get_cache_keys` | List keys from a registered cache with optional prefix filter |
| `clear_cache` | Clear all entries from a registered cache |

### Outbound HTTP Inspector
| Tool | Description |
|------|-------------|
| `get_http_connections` | HTTP client connection stats (Net::HTTP, connection pool) |
| `get_outbound_summary` | Aggregated outbound HTTP call stats (total, avg latency, error rate) |

### Metrics Inspector
| Tool | Description |
|------|-------------|
| `get_registered_metrics` | List all registered Prometheus metrics |
| `get_metric_value` | Get current value of a specific metric by name |

### ActiveRecord Stats Inspector
| Tool | Description |
|------|-------------|
| `get_active_record_query_stats` | ActiveRecord query statistics (queries per model, N+1 detection) |

### Faraday Inspector
| Tool | Description |
|------|-------------|
| `get_faraday_connections` | List Faraday connection objects with host, port, and adapter info |

### Concurrent Inspector
| Tool | Description |
|------|-------------|
| `get_concurrent_state` | Ruby concurrency primitives state (Mutex, ConditionVariable, Queue) |

## Custom Tools

```ruby
require 'debug_agent'

DebugAgent.register_tool('check_redis', 'Check Redis connection') do
  { connected: true }
end
```

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `LLM_BASE_URL` | `https://open.bigmodel.cn/api/coding/paas/v4` | LLM endpoint |
| `LLM_API_KEY` | (required) | API key |
| `LLM_MODEL` | `glm-5.2` | Model name |
| `LLM_MAX_TOOL_ROUNDS` | `25` | Max tool-calling rounds |
| `LLM_CONTEXT_WINDOW_TOKENS` | `100000` | Context window size |

## Run the Demo

The demo uses **Sinatra** + **redis-rb** + **SQLite** + **Sidekiq**. Start Redis with Docker Compose first:

### Docker Compose

```yaml
# docker-compose.yml
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --save 60 1 --loglevel warning
```

```bash
docker compose up -d
```

### Start the app

```bash
export LLM_API_KEY=your-key
cd demo && ruby -I../lib app.rb
# Open http://localhost:4567/agent
```

## RubyGems

[![Gem](https://img.shields.io/badge/rubygems-debug--agent-red)](https://github.com/topcheer/ruby-debug-agent)

## License

MIT
