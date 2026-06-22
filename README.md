# Ruby Debug Agent

[![Gem Version](https://img.shields.io/badge/gem-debug--agent-red)](https://github.com/topcheer/ruby-debug-agent)
![Tools](https://img.shields.io/badge/tools-98-blue)
![Inspectors](https://img.shields.io/badge/inspectors-36-green)
![Ruby](https://img.shields.io/badge/Ruby-2.7%2B-CC342D)
![Gem](https://img.shields.io/badge/gem-debug--agent-red)

An AI-powered runtime debugging agent that embeds directly into your Ruby application. Add one gem, configure an LLM key, and chat with your live app at `/agent` to inspect GC, ObjectSpace, threads, routes, Redis, Rails models/routes, Sidekiq queues, Puma stats, fibers/signals, process info, HTTP requests, and more — **98 diagnostic tools across 36 inspectors**.

## Version Support

| Ruby Version | Status |
|--------------|--------|
| 2.6          | Not supported |
| 2.7          | Minimum supported |
| 3.0          | Supported (Fiber.list available) |
| 3.1          | Supported |
| 3.2          | Supported |
| 3.3          | Supported |
| 3.4          | Tested |

> Requires Ruby 2.7+ for pattern matching guards. Framework inspectors (Rails, Sidekiq, Puma) are optional and auto-detected via `defined?`.

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
- **98 diagnostic tools** across **36 inspectors**
- Zero external dependencies (no Datadog, no Grafana, no APM)

## Inspectors & Tools (98)

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

### Deadlock & Lock Contention Inspector (v0.6.0)
| Tool | Description |
|------|-------------|
| `get_lock_contention` | Mutex contention stats (wait time, hold time, acquisition count) |
| `detect_deadlock` | Analyze all threads for deadlock patterns (circular wait detection) |
| `get_mutex_stats` | Per-lock statistics: total acquisitions, contentions, average wait time |

### Database Migration Inspector (v0.6.0)
| Tool | Description |
|------|-------------|
| `get_migration_status` | Current schema version, applied count, last migration applied |
| `get_pending_migrations` | Migrations not yet applied (version, description, dependencies) |
| `get_migration_history` | Applied migration history (version, applied_at, duration_ms) |

### Configuration Inspector (v0.6.0)
| Tool | Description |
|------|-------------|
| `get_config_snapshot` | All registered config values (sensitive keys masked) |
| `get_env_vars_masked` | Process environment variables with secret values redacted |
| `get_config_sources` | Config source hierarchy (env, file, defaults) with effective values |

### Feature Flags Inspector (v0.6.0)
| Tool | Description |
|------|-------------|
| `get_feature_flags` | List all registered feature flags with current state |
| `evaluate_feature_flag` | Evaluate a specific flag for a given context/user |

### Endpoint Testing Inspector (v0.6.0)
| Tool | Description |
|------|-------------|
| `test_endpoint` | Make an HTTP request to own app, return full response (status, headers, body) |
| `batch_test_endpoints` | Test multiple endpoints in one call with aggregated results |
| `get_endpoint_coverage` | Compare registered routes vs tested endpoints (coverage report) |

### Connection Pool Inspector (v0.6.0)
| Tool | Description |
|------|-------------|
| `get_pool_details` | Detailed DB pool stats (pool size, active, idle, waiting, max) |
| `detect_pool_leaks` | Heuristic leak detection (growing pool, high wait ratio, saturation) |
| `get_pool_wait_stats` | Connection acquire wait stats (avg, P95, max wait, timeout count) |

### CPU Profiler Inspector (v0.7.0)
| Tool | Description |
|------|-------------|
| `start_cpu_profile` | Start a CPU profiling session (stackprof/stackprof-native) |
| `stop_cpu_profile` | Stop CPU profiling and return collected profile data |
| `get_top_functions` | Get top CPU-consuming functions from the current profile |

### Memory Leak Detector Inspector (v0.7.0)
| Tool | Description |
|------|-------------|
| `take_heap_snapshot` | Capture an ObjectSpace heap snapshot for leak analysis |
| `compare_heap_snapshots` | Compare two heap snapshots to identify object growth |
| `get_leak_candidates` | Identify objects likely to be memory leaks |

### Deployment/Build Info Inspector (v0.7.0)
| Tool | Description |
|------|-------------|
| `get_build_info` | Build version, commit hash, and gem metadata |
| `get_deployment_info` | Deployment environment, container, and orchestration metadata |
| `get_runtime_version` | Ruby interpreter version, engine, and platform details |

### Snapshot & Diff Inspector (v0.7.0)
| Tool | Description |
|------|-------------|
| `take_snapshot` | Capture a runtime state snapshot |
| `compare_snapshots` | Compare two snapshots to identify state changes |
| `list_snapshots` | List all saved snapshots with timestamps |

### Service Registry Inspector (v0.7.0)
| Tool | Description |
|------|-------------|
| `get_registered_services` | List all registered application services |
| `get_service_dependencies` | Map service-to-service dependency graph |

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

## Built With

[![ggcode](https://img.shields.io/badge/built%20with-ggcode-blue)](https://github.com/topcheer/ggcode)

This project was built using [ggcode](https://github.com/topcheer/ggcode) — an AI coding assistant for terminal-based development.

## License

MIT
