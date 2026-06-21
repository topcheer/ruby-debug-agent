const { chromium } = require('playwright');
const fs = require('fs');
const { execSync } = require('child_process');

/**
 * Ruby Debug Agent v0.1.0 — Full demo recording
 *
 * 5 sections using NATURAL LANGUAGE prompts (no explicit tool names).
 * The LLM must autonomously decide which tools to invoke.
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

async function waitForAgentIdle(page, timeout = 120000) {
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

// ─── Section 1: Ruby Runtime + Memory + GC ──────────────────────────────
// Tools: get_gc_stats, get_memory_summary, force_gc, get_object_space_stats,
//        get_memory_size, get_runtime_info, get_process_info, get_cpu_time

async function section1_runtime(page) {
  console.log('  [1/5] Ruby Runtime + Memory + GC');
  await typeMessage(page, "My app feels sluggish. Can you check the overall runtime health — memory usage, GC stats, and how long the process has been running?");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me detailed ObjectSpace statistics — how many objects are alive by type, and what's the total memory size of all objects?");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "What's the CPU time breakdown? Show me user vs system time. Also list environment variables.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Try forcing a full garbage collection — I want to see how much memory can be reclaimed.");
  await sendAndWait(page);
  await pause(page, 5000);
}

// ─── Section 2: Threads + Process ─────────────────────────────────────────
// Tools: get_thread_list, get_thread_count, get_main_thread_info,
//        get_system_info, get_disk_usage

async function section2_threads(page) {
  console.log('  [2/5] Threads + System Info');
  await typeMessage(page, "How many threads are running? List all of them with their status and backtraces.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me the main thread details — priority, status, and what it's currently doing.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "What system resources are available? Check CPU count, disk space, and hostname.");
  await sendAndWait(page);
  await pause(page, 5000);
}

// ─── Section 3: Routes + Middleware ───────────────────────────────────────
// Tools: get_routes, get_middleware_stack

async function section3_routes(page) {
  console.log('  [3/5] Routes + Middleware Stack');
  await typeMessage(page, "What API routes does this Sinatra application expose? List all registered routes.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me the Rack middleware stack — what middleware layers are configured?");
  await sendAndWait(page);
  await pause(page, 5000);
}

// ─── Section 4: HTTP Request Tracking ──────────────────────────────────────
// Tools: get_recent_requests, get_error_requests, get_request_stats

async function section4_http(page) {
  console.log('  [4/5] HTTP Request Tracking');
  await typeMessage(page, "What HTTP requests have come in recently? Show me the request history.");
  await sendAndWait(page);
  await pause(page, 4000);

  await typeMessage(page, "Show me request statistics — P50, P95, P99 latency, and error rate. Also show any error requests.");
  await sendAndWait(page);
  await pause(page, 5000);
}

// ─── Section 5: Comprehensive Debugging ─────────────────────────────────────
// Cross-cutting scenario that exercises multiple inspectors together

async function section5_comprehensive(page) {
  console.log('  [5/5] Comprehensive Debugging Scenario');
  await typeMessage(page, "I'm debugging a performance issue. Give me a comprehensive overview: memory and GC status, thread count, recent HTTP requests with errors, and route information — all in one summary.");
  await sendAndWait(page);
  await pause(page, 6000);

  await typeMessage(page, "Now show me the top classes by instance count and total memory. What's using the most memory?");
  await sendAndWait(page);
  await pause(page, 5000);
}

// ─── Main ─────────────────────────────────────────────────────────────────

(async () => {
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║  Ruby Debug Agent v0.1.0 — Demo Recording                      ║
║  ~25 tools / 8 inspectors                                      ║
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
    { name: '01-runtime-gc', fn: section1_runtime },
    { name: '02-threads-system', fn: section2_threads },
    { name: '03-routes-middleware', fn: section3_routes },
    { name: '04-http-requests', fn: section4_http },
    { name: '05-comprehensive', fn: section5_comprehensive },
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
