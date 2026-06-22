# YouTube Video Description

## Title

Ruby Debug Agent — AI-Powered In-Process Diagnostics (40 Tools / 13 Inspectors)

## Description

Chat with your LIVE Ruby application at runtime. The Ruby Debug Agent embeds directly into your Sinatra or Rails app and gives an AI assistant access to 40 diagnostic tools across 13 inspectors — GC profiler, ObjectSpace, threads, routes, Redis, Rails models/routes/schema, Sidekiq queues/workers, Puma cluster stats, fibers/signals, process info, HTTP requests, and more.

No external agents. No attach-to-process. No separate monitoring stack. Just one gem, one line of code, and you're chatting with your running app.

### What you'll see in this demo

**Section 1 — Ruby GC & ObjectSpace Deep Dive**
GC.stat details, GC::Profiler data, forcing full GC, ObjectSpace.count_objects by type, total memory size, and top classes by instance count — all through natural language.

**Section 2 — Threads + Fibers**
Listing all threads with status and backtraces, thread count, main thread info, active Ruby Fibers, and registered signal/trap handlers.

**Section 3 — HTTP Requests + Routes**
Discovering Sinatra/Rails routes and Rack middleware, analyzing recent HTTP traffic, identifying slow and error requests.

**Section 4 — Database + Redis**
Process info, CPU time, memory usage, Redis server info, keyspace scan, and slow log.

**Section 5 — Rails Models + Sidekiq**
Listing ActiveRecord models with associations, Rails routes with helper names, schema/migration status, Sidekiq queue depth, active workers, and job payloads.

**Section 6 — Puma Stats + System**
Puma cluster stats (workers, threads, backlog), system info, disk usage, and open file descriptors.

**Section 7 — Comprehensive Debugging**
Multi-tool correlation: GC + ObjectSpace + threads + Redis + Sidekiq + Puma + requests — all in one analysis.

### Quick Start

```ruby
require 'sinatra/base'
require 'debug_agent'

class MyApp < Sinatra::Base
  register DebugAgent::Middleware
end
```

Open `http://localhost:4567/agent` and start chatting with your app.

### Features

- 40 diagnostic tools across 13 inspectors
- Streaming AI responses with real-time tool call badges
- LLM-based context compression for long conversations
- Custom tool registration via DebugAgent.register_tool()
- Works with any OpenAI-compatible LLM endpoint
- Zero external dependencies (no Datadog, no Grafana, no APM)
- Dark-themed chat UI built-in (single HTML page, no frontend framework)

### Inspector Coverage

| Inspector | Tools | What it inspects |
|-----------|-------|-----------------|
| GC | 3 | GC stats, profiler, force GC |
| ObjectSpace | 3 | Count objects, memory size, top classes |
| Thread | 4 | Thread list, count, main thread, backtrace |
| Route | 2 | Routes, Rack middleware |
| Process | 4 | Process info, CPU time, env vars, memory |
| Runtime | 3 | Ruby info, memory, load average |
| HTTP Tracker | 4 | Requests, slow, errors, stats |
| System | 3 | System info, disk, file descriptors |
| Redis | 4 | Server info, keys, slowlog, command stats |
| Rails | 3 | Models, routes, DB schema |
| Sidekiq | 3 | Queues, workers, jobs |
| Puma | 1 | Cluster stats: workers, threads, backlog |
| Fibers/Signals | 3 | Fiber list, signal handlers, trap handlers |

### GitHub

github.com/topcheer/ruby-debug-agent

### Tags

#ruby #rubydebugging #AI #Diagnostics #Sinatra #Rails #Redis #Sidekiq #Puma #GC #ObjectSpace #LLM #GLM #DeveloperTools #DevOps #ApplicationMonitoring #AIOps #Observability

## Chapters

00:00 Introduction
01:15 Ruby GC & ObjectSpace — Stats, Memory, Force GC
03:20 Threads + Fibers/Signals
05:30 HTTP Requests + Routes
07:10 Process Info + Redis
09:15 Rails Models + Sidekiq
10:50 Puma Stats + System
12:20 Comprehensive Multi-Tool Debugging
14:00 Summary + Quick Start Guide

---

## Thumbnail Text (for image)

Ruby Debug Agent
Chat with your LIVE app
40 tools / 13 inspectors

---

## Playlist

AI Debug Agents Collection
(Spring / .NET / Go / Node.js / Python / Ruby)

---

## Category

Science & Technology

## Language

English

## Visibility

Public

## Made for Kids

No
