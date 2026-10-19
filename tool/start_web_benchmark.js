// Execute this function in an existing Playwright page/session. The collector
// lives in the browser, so later tool calls can read window.__phase0.
async (page) => {
  await page.setViewportSize({ width: 1200, height: 796 });
  await page.addInitScript(() => {
    window.__phase0 = { complete: false, ready: [], runs: [], diagnostics: [], errors: [] };
    const heap = () => performance.memory ? {
      usedJSHeapSize: performance.memory.usedJSHeapSize,
      totalJSHeapSize: performance.memory.totalJSHeapSize,
      jsHeapSizeLimit: performance.memory.jsHeapSizeLimit,
    } : null;
    for (const method of ['log', 'debug', 'info', 'warn', 'error']) {
      const original = console[method].bind(console);
      console[method] = (...args) => {
        const line = args.map(String).join(' ');
        const start = line.indexOf('PHASE0_');
        if (start >= 0) {
          const message = line.slice(start);
          const split = message.indexOf(' ');
          const prefix = message.slice(0, split);
          const payload = message.slice(split + 1);
          try {
            if (prefix === 'PHASE0_READY') {
              window.__phase0.ready.push({ ...JSON.parse(payload), navigationToFrameworkReadyMs: performance.now() });
            } else if (prefix === 'PHASE0_RESULT') {
              window.__phase0.runs.push({ ...JSON.parse(payload), approximateJsHeap: heap() });
            } else if (prefix === 'PHASE0_DIAGNOSTIC') {
              window.__phase0.diagnostics.push({...JSON.parse(payload),approximateJsHeap:heap()});
            } else if (prefix === 'PHASE0_SUITE_DONE') {
              window.__phase0.complete = window.__phase0.runs.length === JSON.parse(payload).runs;
            } else if (prefix === 'PHASE0_SUITE_FAILED' || prefix === 'PHASE0_FONT_FAILED') {
              window.__phase0.errors.push(payload);
            }
          } catch (error) { window.__phase0.errors.push(String(error)); }
        }
        original(...args);
      };
    }
    window.addEventListener('error', event => window.__phase0.errors.push(event.message));
  });
  const session = await page.context().browser().newBrowserCDPSession();
  const system = await session.send('SystemInfo.getInfo');
  const environment = {
    browser: page.context().browser().version(),
    gpu: system.gpu.devices,
    webgl: system.gpu.featureStatus.webgl,
    gpuCompositing: system.gpu.featureStatus.gpu_compositing,
    viewport: { width: 1200, height: 796 },
  };
  await page.goto('http://127.0.0.1:8765/?phase0=profile', { waitUntil: 'domcontentloaded' });
  return environment;
}
