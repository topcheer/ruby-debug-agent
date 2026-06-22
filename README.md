# Ruby Debug Agent

An AI-powered runtime debugging agent that embeds directly into your Ruby application. Add one gem, configure an LLM key, and chat with your live app at `/agent` to inspect GC, ObjectSpace, threads, routes, process info, HTTP requests, and more.

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
- **26 diagnostic tools** across 8 inspectors

## Inspectors & Tools (26)

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
| `get_disk_usage` | Disk usage for working directory |
| `get_file_descriptors` | Open file descriptor count |

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

```bash
export LLM_API_KEY=your-key
cd demo && ruby -I../lib app.rb
# Open http://localhost:4567/agent
```

## License

MIT
