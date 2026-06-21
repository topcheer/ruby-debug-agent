# YouTube Video Description

## Title

Ruby Debug Agent — AI-Powered In-Process Diagnostics for Ruby/Sinatra Apps (8 Inspectors / 25 Tools)

## Description

Chat with your LIVE Ruby application at runtime. The Ruby Debug Agent embeds directly into your Sinatra/Rack app and gives an AI assistant access to 25+ diagnostic tools across 8 inspectors — GC, ObjectSpace, threads, routes, middleware stack, process info, HTTP request tracking, and system resources.

No external agents. No attach-to-process. No separate monitoring stack. Just one gem, one line of code, and you're chatting with your running app.

### What you'll see in this demo

**Section 1 — Ruby Runtime + Memory + GC**
GC stats, ObjectSpace analysis, memory sizes by type, forcing a full garbage collection, process info and CPU time — all through natural language.

**Section 2 — Threads + System Info**
Thread listing with backtraces, main thread details, system resources (CPU, disk, hostname).

**Section 3 — Routes + Middleware Stack**
Discovering Sinatra routes, inspecting the Rack middleware stack.

**Section 4 — HTTP Request Tracking**
Analyzing recent HTTP traffic, latency percentiles (P50/P95/P99), error detection.

**Section 5 — Comprehensive Debugging**
Multi-tool correlation: memory + GC + threads + HTTP requests + routes — all in one analysis.

### Quick Start

```ruby
# Gemfile
gem 'debug-agent'

# config.ru or Sinatra app
require 'debug_agent'
use DebugAgent::RackMiddleware
```

Open `http://localhost:4567/agent` and start chatting with your app.

### Features

- 25+ diagnostic tools across 8 inspectors
- Streaming AI responses with real-time tool call badges
- LLM-based context compression for long conversations
- SSE streaming via standard Rack middleware
- Works with Z.ai GLM or any OpenAI-compatible LLM endpoint
- Zero external dependencies (no Datadog, no New Relic, no Grafana)
- Dark-themed chat UI built-in (single HTML page, no frontend framework)
- Sinatra + Rack compatible

### Inspector Coverage

| Inspector | Tools | What it inspects |
|-----------|-------|-----------------|
| GC | 3 | GC stats, profiler data, force GC |
| ObjectSpace | 3 | Object counts by type, memory size, class counts |
| Runtime | 6 | GC stats, memory summary, threads, runtime info, allocations |
| Threads | 3 | Thread list, count, main thread info |
| Routes | 2 | Sinatra routes, Rack middleware stack |
| Process | 2 | Process info, CPU time |
| System | 4 | System info, disk usage, env variables, process info |
| HTTP Requests | 3 | Recent requests, errors, stats (P50/P95/P99) |

### GitHub

https://github.com/topcheer/ruby-debug-agent

### Tags

#ruby #sinatra #AI #Debugging #Diagnostics #LLM #GLM #DeveloperTools #DevOps #ApplicationMonitoring #RubyOnRails #AIOps #Observability #Rack #Gem

## Chapters

00:00 Introduction
01:15 Ruby Runtime — Memory, GC, ObjectSpace
03:30 Threads + System Info
05:15 Routes + Middleware Stack
06:45 HTTP Request Tracking
08:20 Comprehensive Multi-Tool Debugging
10:00 Summary + Quick Start Guide

---

## Thumbnail Text (for image)

Ruby Debug Agent
Chat with your LIVE app
25+ tools / 8 inspectors

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
