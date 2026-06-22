const { chromium } = require('playwright');
const fs = require('fs');
const { execSync } = require('child_process');

/**
 * Ruby Debug Agent v0.5.0 — Full demo recording (67 tools / 18 inspectors)
 *
 * 10 sections using NATURAL LANGUAGE prompts (no explicit tool names).
 * The LLM must autonomously decide which tools to invoke.
 *
 * New v0.5.0 inspectors: Security, Health, Scheduler, Error Tracking,
 * WebSocket, plus Redis, Sinatra routes, ORM, Logging, Cache,
 * Outbound HTTP, Metrics.
 *
 * Usage:
 *   1. Start demo: cd ruby-debug-agent && LLM_API_KEY=sk-... ruby demo/app.rb
 *   2. Run: node scripts/demo-record.js
 */

const BASE_URL = process.env.BASE_URL || 'http://localhost:4567';
const OUTPUT_DIR = './demo-recordings';
const VERSION = 'v01';

// ─── Helpers ──────────────────────────────────────────────────────────────

async function typeMessage(page, text, charDelay = 8) {
  const input = page.locator('#input');
  await input.click();
  await input.pressSequentially(text, { delay: charDelay });
}

async function waitForAgentIdle(page, timeout = 180000) {
  // Wait for send button to be re-enabled
  try {
    await page.waitForFunction(() => {
      const btn = document.querySelector('#send');
      return btn && !btn.disabled;
    }, { timeout });
  } catch {
    console.log('  Warning: Agent still busy, waiting more...');
    await page.waitForFunction(() => {
      const btn = document.querySelector('#send');
      return btn && !btn.disabled;
    }, { timeout: 60000 }).catch(() => {
      console.log('  Warning: Force proceeding after extended wait');
    });
  }

  // Wait for DOM to stabilize (no new messages for 3s)
  let lastCount = 0;
  let stableTime = 0;
  let maxWait = 15000;
  const interval = 1000;
  while (stableTime < 3000 && maxWait > 0) {
    const count = await page.evaluate(() => document.querySelectorAll('.message, .tool-badge').length);
    if (count === lastCount) {
      stableTime += interval;
    } else {
      lastCount = count;
      stableTime = 0;
    }
    await page.waitForTimeout(interval);
    maxWait -= interval;
  }
  await page.waitForTimeout(1500);
}

async function sendAndWait(page, timeout = 120000) {
  await page.locator('#send').click();
  await waitForAgentIdle(page, timeout);
}

async function pause(page, ms = 3000) {
  await page.waitForTimeout(ms);
}

// ─── Section 1: GC Stats + ObjectSpace + Memory ────────────────────────────

async function section1_gc_memory(page) {
  console.log('  [1/10] GC Stats + ObjectSpace + Memory');
  await typeMessage(page, "My Ruby app feels sluggish. Can you check the overall runtime health — memory usage, GC stats, and the Ruby version we're running?");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me detailed ObjectSpace statistics — how many objects are alive by type, and what's the total memory size of all objects?");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Try forcing a full garbage collection — I want to see how much memory can be reclaimed.");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Threads + Fibers + Signals');
}

// ─── Section 2: Threads + Fibers + Signals ─────────────────────────────────

async function section2_threads_signals(page) {
  console.log('  [2/10] Threads + Fibers + Signals');
  await typeMessage(page, "How many threads are running? List all of them with their status and backtraces.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Are there any Fibers active? Show me fiber details and their current state.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "What signal handlers are registered? Show me which signals the application is listening for.");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: HTTP Requests + Routes + Redis');
}

// ─── Section 3: HTTP Requests + Routes + Redis ─────────────────────────────

async function section3_http_redis(page) {
  console.log('  [3/10] HTTP Requests + Routes + Redis');
  await typeMessage(page, "What API routes does this Sinatra application expose? List all registered routes with their methods.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "What HTTP requests have come in recently? Show me request statistics — P50, P95, P99 latency, and error rate.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Check the Redis connection pool — how many connections are active and idle? Show me any Redis operation stats.");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Logging + Cache Stats + Metrics');
}

// ─── Section 4: Logging + Cache Stats + Metrics ────────────────────────────

async function section4_logging_cache(page) {
  console.log('  [4/10] Logging + Cache Stats + Metrics');
  await typeMessage(page, "Show me the logging configuration — what log level is set, what logger is used, and recent log entries.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "What's the cache status? Show me cache hit and miss rates, total keys, and memory usage for any in-memory caches.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me the application metrics — request counts, error rates, latency histograms, and any custom metrics.");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Security (auth config, sessions, CORS)');
}

// ─── Section 5: Security (auth config, sessions, CORS) ─────────────────────

async function section5_security(page) {
  console.log('  [5/10] Security (auth config, sessions, CORS)');
  await typeMessage(page, "I'm doing a security audit. What authentication and authorization middleware is configured? Show me the auth settings and any Rack protection.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Are there any active sessions? Show me session details — how many are active and their expiry. Also show me the CORS configuration.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Check for potential security issues — are there any environment variables exposing secrets, insecure headers, or missing protections?");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Health Checks + Scheduler');
}

// ─── Section 6: Health Checks + Scheduler ──────────────────────────────────

async function section6_health_scheduler(page) {
  console.log('  [6/10] Health Checks + Scheduler');
  await typeMessage(page, "Run a health check on the database connection — is it reachable and responding quickly? Also check Redis connection health.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Are there any scheduled or cron jobs running? Show me the scheduler status and any Sidekiq or Rufus scheduler jobs.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Give me an overall readiness summary — are all critical dependencies healthy and are there any queue backlogs?");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Error Tracking + Process Info');
}

// ─── Section 7: Error Tracking + Process Info ─────────────────────────────

async function section7_errors_process(page) {
  console.log('  [7/10] Error Tracking + Process Info');
  await typeMessage(page, "Show me recent errors tracked by the application — any exceptions, rescued errors, or error-level log entries.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Are there any WebSocket connections active? Show me connection details and any connection-related errors.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me process information — PID, CPU time breakdown (user vs system), and memory usage of the process.");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Outbound HTTP + ActiveRecord Stats');
}

// ─── Section 8: Outbound HTTP + ActiveRecord Stats ─────────────────────────

async function section8_outbound_activerecord(page) {
  console.log('  [8/10] Outbound HTTP + ActiveRecord Stats');
  await typeMessage(page, "What outbound HTTP requests has the application made recently? Show me external API calls with their response times.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Is ActiveRecord loaded? If so, show me the connection pool stats, query cache stats, and any slow queries.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me the Rack middleware stack — what middleware layers are configured in this application?");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: System + Disk + FD');
}

// ─── Section 9: System + Disk + FD ─────────────────────────────────────────

async function section9_system_disk(page) {
  console.log('  [9/10] System + Disk + FD');
  await typeMessage(page, "What system resources are available? Check CPU count, load average, and hostname.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "What's the disk usage for the current working directory? How much space is free?");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "How many file descriptors are currently open? Is there any risk of hitting the FD limit?");
  await sendAndWait(page);
  await pause(page, 5000);
  console.log('  → Transition: Comprehensive Multi-Tool Debugging');
}

// ─── Section 10: Comprehensive Multi-Tool Debugging ────────────────────────

async function section10_comprehensive(page) {
  console.log('  [10/10] Comprehensive Multi-Tool Debugging');
  await typeMessage(page, "I'm investigating a production incident. Give me a comprehensive overview: memory and GC status, thread count, recent HTTP requests with errors, database and Redis pool health, and any tracked errors — all in one summary.");
  await sendAndWait(page);
  await pause(page, 6000);

  await typeMessage(page, "Now show me: top classes by instance count and total memory, security configuration, scheduler status, and system load. Summarize the app's overall health and flag any concerns.");
  await sendAndWait(page);
  await pause(page, 5000);
}

// ─── Main ─────────────────────────────────────────────────────────────────

(async () => {
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║  Ruby Debug Agent v0.5.0 — Demo Recording                      ║
║  67 tools / 18 inspectors                                      ║
╚══════════════════════════════════════════════════════════════╝
  `);

  if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  // Verify app is running
  console.log(`Checking app at ${BASE_URL}/agent ...`);
  try {
    const resp = await fetch(`${BASE_URL}/agent/api/tools`);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = await resp.json();
    console.log(`  Found ${data.tools.length} tools registered`);
  } catch (e) {
    console.error(`ERROR: Demo app not running at ${BASE_URL}. Start it first:\n  cd ruby-debug-agent && LLM_API_KEY=sk-... ruby demo/app.rb`);
    process.exit(1);
  }

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    recordVideo: { dir: OUTPUT_DIR, size: { width: 1280, height: 800 } },
  });
  const page = await context.newPage();

  console.log(`Navigating to ${BASE_URL}/agent ...`);
  await page.goto(`${BASE_URL}/agent`);
  await pause(page, 2000);

  // Pre-generate some HTTP traffic for request tracking demos
  console.log('Generating HTTP traffic for demos...');
  const endpoints = [
    '/api/orders', '/api/orders/1', '/api/health',
    '/api/slow', '/api/error', '/api/orders',
    '/api/orders/2', '/api/health', '/api/orders/3',
  ];
  for (const ep of endpoints) {
    try { await fetch(`${BASE_URL}${ep}`); } catch {}
  }

  await pause(page, 1000);

  const sections = [
    { name: '01-gc-objectspace-memory', fn: section1_gc_memory },
    { name: '02-threads-fibers-signals', fn: section2_threads_signals },
    { name: '03-http-routes-redis', fn: section3_http_redis },
    { name: '04-logging-cache-metrics', fn: section4_logging_cache },
    { name: '05-security', fn: section5_security },
    { name: '06-health-scheduler', fn: section6_health_scheduler },
    { name: '07-errors-process', fn: section7_errors_process },
    { name: '08-outbound-activerecord', fn: section8_outbound_activerecord },
    { name: '09-system-disk-fd', fn: section9_system_disk },
    { name: '10-comprehensive', fn: section10_comprehensive },
  ];

  const startTime = Date.now();

  for (let i = 0; i < sections.length; i++) {
    const section = sections[i];
    const elapsed = ((Date.now() - startTime) / 60000).toFixed(1);
    console.log(`\n--- [${i + 1}/${sections.length}] ${section.name} (elapsed: ${elapsed} min) ---`);
    await section.fn(page);
    await page.screenshot({ path: `${OUTPUT_DIR}/${VERSION}-demo-${section.name}.png`, fullPage: true });
    console.log(`  Screenshot: ${VERSION}-demo-${section.name}.png`);
  }

  await pause(page, 3000);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await pause(page, 2000);

  const video = page.video();
  const videoPath = await video.path();
  console.log(`\n  Video path: ${videoPath}`);

  await context.close();
  await browser.close();

  // Rename and convert video
  console.log('\n--- Finalizing video ---');
  const finalWebm = `${OUTPUT_DIR}/${VERSION}-full-demo.webm`;
  const finalMp4 = `${OUTPUT_DIR}/${VERSION}-full-demo.mp4`;

  try { fs.unlinkSync(finalWebm); } catch {}
  try { fs.unlinkSync(finalMp4); } catch {}

  if (videoPath && fs.existsSync(videoPath)) {
    fs.copyFileSync(videoPath, finalWebm);
    const size = fs.statSync(finalWebm).size;
    console.log(`  Saved: ${VERSION}-full-demo.webm (${(size / 1024 / 1024).toFixed(1)} MB)`);
  }

  // Convert to mp4
  try {
    console.log('\n--- Converting to mp4 ---');
    if (fs.existsSync(finalWebm)) {
      execSync(`ffmpeg -y -i "${finalWebm}" -c:v libx264 -preset fast -crf 23 -c:a aac "${finalMp4}"`, { stdio: 'pipe' });
      const size = fs.statSync(finalMp4).size;
      console.log(`  Done: ${VERSION}-full-demo.mp4 (${(size / 1024 / 1024).toFixed(1)} MB)`);
    }
  } catch (e) {
    console.log('  (ffmpeg conversion failed, keeping .webm)');
  }

  const totalMin = ((Date.now() - startTime) / 60000).toFixed(1);
  console.log(`
======================================================
  Recording complete!
  Total time: ${totalMin} minutes
  Output: ${OUTPUT_DIR}/${VERSION}-full-demo.mp4
======================================================
  `);
})();
