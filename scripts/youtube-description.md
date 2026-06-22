# YouTube Video Description

## Title

Ruby Debug Agent v0.5.0 — Security, Health, Scheduler, Error Tracking, WebSocket (65 Tools)

## Description

Chat with your LIVE Ruby application at runtime. The Ruby Debug Agent embeds directly into your Sinatra or Rails app and gives an AI assistant access to 65 diagnostic tools across 25 inspectors — from GC profiling and ObjectSpace analysis to security configs, health checks, scheduled jobs, real-time error tracking, and WebSocket monitoring.

No external agents. No attach-to-process. No separate monitoring stack. Just one gem and you're chatting with your running app.

### What's New in v0.5.0 — Five New Inspectors (13 Tools)

**Security Inspector** — Auth configs, active sessions, CORS settings
Query Devise, Warden, OmniAuth, or custom API-key strategies. Inspect session stores and review CORS middleware rules.

**Health Inspector** — Component-level health checks
Register health blocks for database, Redis, memory, or any dependency. Get UP/DOWN/DEGRADED status with latency sampling and deep-dive diagnostics.

**Scheduler Inspector** — Scheduled job visibility
List jobs from Sidekiq::Cron, rufus-scheduler, or Thread-based timers. Track execution history, success/failure rates, and average duration.

**Error Tracking Inspector** — In-process exception capture
Ring buffer captures the last 50 unhandled exceptions via at_exit and Sinatra error handlers. Error stats, rate-per-minute, and pattern analysis grouped by class.

**WebSocket Inspector** — Real-time connection monitoring
Track WebSocket connections from faye-websocket, websocket-driver, or ActionCable. Monitor message flow, connection stats, and channel subscriber counts.

### Demo Sections

Section 1 — Ruby GC and ObjectSpace: GC.stat, profiler, force GC, object counts, memory size
Section 2 — Threads, Fibers, Signals: thread list, backtraces, fiber info, signal handlers
Section 3 — HTTP Requests and Routes: route discovery, middleware, traffic analysis, latency
Section 4 — Database, Redis, Cache: process info, Redis info, keyspace, cache hit/miss ratios
Section 5 — Rails Models and Sidekiq: ActiveRecord models, routes, schema, queue depth, workers
Section 6 — Security: auth configs, session stores, CORS rules
Section 7 — Health Checks: component status, UP/DOWN/DEGRADED, latency diagnostics
Section 8 — Scheduler: job schedules, execution history, success rates
Section 9 — Error Tracking: captured exceptions, error stats, pattern analysis
Section 10 — WebSocket: connections, message stats, channels

### Quick Start

Add to your Sinatra or Rack app:

    require 'debug_agent'
    use DebugAgent::RackMiddleware

Open http://localhost:4567/agent and start chatting.

### Inspector Coverage — 25 Inspectors, 65 Tools

GC — stats, profiler, force GC (3)
ObjectSpace — count, memory, top classes (3)
Threads — list, count, main, summary (4)
Routes — routes, middleware (2)
Process — info, CPU, env (3)
Runtime — Ruby info, memory, load avg (3)
HTTP Tracker — requests, errors, stats (3)
System — info, disk, fds (3)
Redis — info, latency, pool (4)
Rails — models, routes, schema (3)
Sidekiq — queues, workers, retries (3)
Puma — cluster stats (1)
Fibers/Signals — fiber, signals (3)
Logging — buffer, info, level (3)
Cache — stats, keys, clear (3)
HTTP Client — connections (2)
Metrics — registered, values (2)
ActiveRecord — query stats (2)
Faraday — connections (1)
Concurrent — locks, state (2)
Security — auth, sessions, CORS (3) NEW
Health — status, detail (2) NEW
Scheduler — jobs, history (2) NEW
Error Tracking — errors, patterns (3) NEW
WebSocket — connections, channels (3) NEW

### Features

- 65 tools across 25 inspectors
- Streaming AI responses with tool call badges
- LLM-based context compression
- Custom tool registration
- Any OpenAI-compatible LLM endpoint
- Zero external dependencies — no APM, no Grafana
- Dark-themed chat UI built-in

### GitHub

github.com/topcheer/ruby-debug-agent

### Tags

#ruby #sinatra #security #healthcheck #websocket #errorhandling #scheduler #sidekiq #rails #redis #observability #devops

## Chapters

00:00 Introduction
00:24 GC Stats + ObjectSpace + Memory
03:14 Threads + Fibers + Signals
06:04 HTTP Requests + Routes + Redis
08:55 Logging + Cache + Metrics
11:45 Security — Auth, Sessions, CORS
14:35 Health Checks + Scheduler
17:26 Error Tracking + Process Info
20:16 Outbound HTTP + ActiveRecord Stats
23:07 System + Disk + FD
25:57 Comprehensive Multi-Tool Debugging

---

## Thumbnail Text

Ruby Debug Agent v0.5.0
65 Tools / 25 Inspectors
Security, Health, Errors, WebSocket

---

## Playlist

AI Debug Agents (Spring / .NET / Go / Node / Python / Ruby)

---

## Category

Science and Technology

## Language

English

## Visibility

Public

## Made for Kids

No
