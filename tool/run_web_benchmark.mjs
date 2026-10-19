// Uses the existing bundled Playwright runtime; adds no project dependency.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { createGzip } from 'node:zlib';
import { once } from 'node:events';
import { performance } from 'node:perf_hooks';
import { createHash } from 'node:crypto';
const require = createRequire(import.meta.url);
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name)+1] : fallback;
const modulePath = option('--playwright', process.env.PHASE01_PLAYWRIGHT || 'playwright');
const output = option('--output', 'benchmark_results/phase01/web-profile.json');
const stopAfter=Number(option('--stop-after','0'));
const traceAfter=option('--trace-after',undefined);
let resultCount=0;
const { chromium } = require(modulePath);
const executablePath=option('--executable',undefined);
const browser = await chromium.launch({ headless: true, args:args.includes('--hardware-metal') ? ['--enable-gpu','--use-angle=metal'] : [], ...(executablePath ? {executablePath} : {}) });
let timeout;
let captureTimer;
let stopTimer;
let capturePromise = Promise.resolve();
let traced = false;
const page = await browser.newPage({viewport:{width:1200,height:796},deviceScaleFactor:1});
const session = await page.context().newCDPSession(page);
const prefix = output.replace(/\.json$/, '');
const expectedBackend = option('--expect-backend', undefined);
const backendResources = [];
const workerUrls = [];
let documentResponse;
let backendResourceOverflow = false;
const requireLocalFonts = args.includes('--require-local-fonts');
const fontRequests = [];
const fontEntries = new Map();
let fontRequestOverflow = false;
let firstFontReadyAt;
if (requireLocalFonts) {
  page.on('request', request => {
    if (!/\.(?:ttf|otf|woff2?)(?:\?|$)|fonts\.gstatic\.com/.test(request.url())) return;
    if (fontRequests.length >= 64) { fontRequestOverflow = true; return; }
    const row = {url:request.url(),startedAt:performance.now()};
    fontRequests.push(row); fontEntries.set(request,row);
  });
  page.on('response', response => {
    const row = fontEntries.get(response.request());
    if (row) row.status = response.status();
  });
  page.on('requestfinished', request => {
    const row = fontEntries.get(request);
    if (row) row.finishedAt = performance.now();
  });
  page.on('requestfailed', request => {
    const row = fontEntries.get(request);
    if (row) row.failure = request.failure();
  });
}
if (expectedBackend) {
  if (!['canvaskit', 'skwasm-single', 'skwasm-multi'].includes(expectedBackend)) throw new Error('Unknown expected backend');
  page.on('worker', worker => {
    if (workerUrls.length < 256) workerUrls.push(worker.url());
    else backendResourceOverflow = true;
  });
  page.on('response', response => {
    if (response.request().isNavigationRequest()) documentResponse = response;
    if (/main\.dart|canvaskit|skwasm|flutter_bootstrap/.test(response.url())) {
      if (backendResources.length < 256) backendResources.push({url:response.url(),status:response.status()});
      else backendResourceOverflow = true;
    }
  });
}

async function saveTrace() {
  const done = new Promise(resolve => session.once('Tracing.tracingComplete', resolve));
  await session.send('Tracing.end');
  const event = await done;
  const zip = createGzip();
  const stream = fs.createWriteStream(prefix+'.timeline.json.gz');
  zip.pipe(stream);
  while (true) {
    const part = await session.send('IO.read',{handle:event.stream,size:65536});
    const chunk = Buffer.from(part.data,part.base64Encoded ? 'base64' : 'utf8');
    if (!zip.write(chunk)) await once(zip,'drain');
    if (part.eof) break;
  }
  await session.send('IO.close',{handle:event.stream});
  zip.end();
  await once(stream,'finish');
}
try {
  const complete = new Promise((resolve,reject) => {
    timeout=setTimeout(()=>reject(new Error('Benchmark exceeded timeout')),Number(option('--timeout','600'))*1000);
    page.on('pageerror', error => reject(error));
    page.on('console', message => {
      const line = message.text();
      const start = line.indexOf('PHASE0_');
      if (start<0) return;
      const text=line.slice(start);
      const separator=text.indexOf(' ');
      const type=text.slice(0,separator);
      let data;
      try {data=JSON.parse(text.slice(separator+1));} catch {return;}
      if(type==='PHASE0_READY') {
        firstFontReadyAt ??= performance.now();
        console.log(JSON.stringify({ready:data.scene,loadMs:data.loadToInteractiveMs}));
      }
      if(type==='PHASE0_FONT_FAILED') reject(new Error(text));
      if(type==='PHASE0_DIAGNOSTIC' && data.kind!=='pointer') console.log(JSON.stringify({diagnostic:data.kind,cycle:data.cycle,elapsedSeconds:data.elapsedSeconds,tiles:data.tiles ? {bytes:data.tiles.bytes,builds:data.tiles.builds,discarded:data.tiles.discarded} : undefined}));
      if (type==='PHASE0_RESULT') {
        console.log(JSON.stringify({scene:data.scene,workload:data.workload,stage:data.frames.stage}));
        resultCount++;
        if (stopAfter && resultCount>=stopAfter) resolve();
      }
      if (args.includes('--trace-window') && !traced && (traceAfter ? (type==='PHASE0_RESULT' && data.workload===traceAfter) : (type==='PHASE0_READY' && data.scene==='dense'))) {
        traced=true;
        capturePromise=new Promise((captureResolve,captureReject)=>{
          captureTimer=setTimeout(async()=>{
            try {
              const started=performance.now();
              await session.send('Profiler.enable');
              await session.send('Profiler.setSamplingInterval',{interval:1000});
              await session.send('Profiler.start');
              await session.send('Tracing.start',{categories:'devtools.timeline,v8,blink,cc,gpu',transferMode:'ReturnAsStream'});
              stopTimer=setTimeout(async()=>{
                try {
                  const cpu=await session.send('Profiler.stop');
                  const stopped=performance.now();
                  fs.writeFileSync(prefix+'.cpu.json.gz',await new Promise((resolve,reject)=>{
                    const gzip=createGzip(); const chunks=[];
                    gzip.on('data',c=>chunks.push(c));gzip.on('end',()=>resolve(Buffer.concat(chunks)));gzip.on('error',reject);
                    gzip.end(JSON.stringify(cpu));
                  }));
                  await saveTrace();
                  fs.writeFileSync(prefix+'.capture.json',JSON.stringify({trigger:traceAfter ? 'result:'+traceAfter : 'first dense ready',startAfterTriggerMs:7000,requestedDurationMs:3000,actualCpuCaptureWallMs:stopped-started,cpuSampleIntervalMicros:1000,categories:'devtools.timeline,v8,blink,cc,gpu'},null,2)+'\n');
                  captureResolve();
                } catch(error) {captureReject(error);}
              },3000);
            } catch(error) {captureReject(error);}
          },7000);
        });
        // A failed capture must be observed promptly rather than rejected silently.
        capturePromise.catch(reject);
      }
      if (type==='PHASE0_SUITE_DONE') resolve();
      if (type==='PHASE0_SUITE_FAILED') reject(new Error(text));
    });
  });
  const start = eval('('+fs.readFileSync(new URL('./start_web_benchmark.js',import.meta.url),'utf8')+')');
  const environment = await start(page);
  console.log('PHASE01_ENV '+JSON.stringify(environment));
  fs.writeFileSync(prefix+'.environment.json',JSON.stringify(environment,null,2)+'\n');
  if (environment.gpuCompositing!=='enabled' && !args.includes('--allow-software')) throw new Error('Hardware GPU compositing unavailable; refusing a misleading hardware comparison.');
  await complete;
  clearTimeout(timeout);
  await capturePromise;
  const report=await page.evaluate(()=>window.__phase0);
  report.environment=environment;
  if (requireLocalFonts) {
    const expected = ['Roboto-Regular.ttf','Roboto-Medium.ttf','Roboto-Bold.ttf','NotoSansArabic-Regular.ttf'];
    const external = fontRequests.filter(row => new URL(row.url).origin !== 'http://127.0.0.1:8765');
    const assetsCompleteBeforeReady = expected.every(name => fontRequests.some(row =>
      row.url.endsWith('/assets/benchmark_fonts/'+name) && row.status === 200 &&
      row.finishedAt <= firstFontReadyAt && !row.failure));
    const reportsReady = report.ready.length > 0 && report.ready.every(row =>
      row.fonts?.ready === true && row.fonts.manifest === 'roboto-3.015-noto-sans-arabic-2.012-v1');
    report.fontAudit = {expected,requests:fontRequests,firstReadyAt:firstFontReadyAt,
      externalRequests:external,overflow:fontRequestOverflow,assetsCompleteBeforeReady,reportsReady};
    fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
    if (fontRequestOverflow || external.length || !assetsCompleteBeforeReady || !reportsReady) {
      throw new Error('Font readiness/local asset audit failed');
    }
  }
  if (expectedBackend) {
    const audit = await page.evaluate(() => {
      const instance = window._flutter_skwasmInstance;
      return {
        canvasKitLoaded: !!window.flutterCanvasKit,
        skwasmLoaded: !!instance,
        skwasmIsMultiThreaded: typeof instance?._skwasm_isMultiThreaded === 'function'
          ? !!instance._skwasm_isMultiThreaded() : null,
        crossOriginIsolated: window.crossOriginIsolated,
        sharedArrayBufferAvailable: typeof SharedArrayBuffer !== 'undefined',
      };
    });
    const headers = await documentResponse?.allHeaders();
    report.backendAudit = {...audit,workerUrls,resources:backendResources,
      documentHeaders:{coop:headers?.['cross-origin-opener-policy'] ?? null,coep:headers?.['cross-origin-embedder-policy'] ?? null},
      expectedBackend,resourceOverflow:backendResourceOverflow,
      probe:'Flutter3.41.9 loader globals/export; diagnostic private API, not product dependency'};
    const actual = audit.skwasmLoaded ? (audit.skwasmIsMultiThreaded === null ? 'unknown' : (audit.skwasmIsMultiThreaded ? 'skwasm-multi' : 'skwasm-single')) : (audit.canvasKitLoaded ? 'canvaskit' : 'unknown');
    if (backendResourceOverflow || actual !== expectedBackend || (audit.canvasKitLoaded && audit.skwasmLoaded)) {
      report.collectorError = 'Expected backend '+expectedBackend+'; observed '+actual;
      fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
      throw new Error(report.collectorError);
    }
  }

  if(args.includes('--memory')) {
    const beforeGc=await session.send('Runtime.getHeapUsage');
    await session.send('HeapProfiler.collectGarbage');
    const afterGc=await session.send('Runtime.getHeapUsage');
    report.finalJsHeap={beforeGc,afterGc,includesGpuMemory:false};
  }
  if(stopAfter) {report.boundedDiagnosticStopAfter=stopAfter; report.diagnosticComplete=report.runs.length===stopAfter;}
  report.collector={playwright:require(modulePath+'/package.json').version,traceWindow:args.includes('--trace-window') ? '7–10 seconds after '+(traceAfter ? traceAfter+' result' : 'first dense READY')+'; 1 ms CPU samples' : 'disabled for frame comparison',process:'fresh headless browser per suite'};
  fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
  if (args.includes('--input')) {
    const checksum=async()=>createHash('sha256').update(await page.screenshot({clip:{x:100,y:280,width:900,height:300}})).digest('hex');
    const before=await checksum();
    await page.mouse.move(600,450);
    await page.mouse.down();
    await page.mouse.move(850,480,{steps:120});
    await page.mouse.up();
    await page.waitForTimeout(700);
    const panned=await checksum();
    for(let i=0;i<24;i++) await page.mouse.wheel(0,-20);
    await page.waitForTimeout(700);
    const zoomed=await checksum();
    const diagnostics=await page.evaluate(()=>window.__phase0.diagnostics.filter(d=>d.kind==='pointer'));
    fs.writeFileSync(prefix+'.input.json',JSON.stringify({softwareInput:true,physicalInput:false,dragSteps:120,wheelEvents:24,panChangedCanvasRegion:before!==panned,zoomChangedCanvasRegion:panned!==zoomed,diagnostics},null,2)+'\n');
  }
  console.log('Saved '+output+'; complete='+report.complete);
  if((stopAfter ? !report.diagnosticComplete : !report.complete) || report.errors.length) process.exitCode=1;
} catch(error) {
  const bounded=(promise)=>Promise.race([promise,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Diagnostic snapshot timed out')),3000))]);
  try {
    const partial=await bounded(page.evaluate(()=>window.__phase0));
    if (fs.existsSync(output)) {
      try {
        const saved=JSON.parse(fs.readFileSync(output,'utf8'));
        partial.backendAudit=saved.backendAudit;
        partial.fontAudit=saved.fontAudit;
      } catch {}
    }
    partial.collectorError=String(error);
    fs.writeFileSync(output,JSON.stringify(partial,null,2)+'\n');
  } catch {}
  try { await bounded(page.screenshot({path:prefix+'.failure.png'})); } catch {}
  throw error;
} finally {
  clearTimeout(timeout);clearTimeout(captureTimer);clearTimeout(stopTimer);
  await browser.close();
}
