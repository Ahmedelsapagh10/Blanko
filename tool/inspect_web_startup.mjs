// Bounded, fresh-browser startup diagnostic; no frame-performance qualification.
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {performance} from 'node:perf_hooks';
const require=createRequire(import.meta.url);
const args=process.argv.slice(2);
const option=(name,fallback)=>args.includes(name)?args[args.indexOf(name)+1]:fallback;
const {chromium}=require(option('--playwright','playwright'));
const browser=await chromium.launch({headless:true,executablePath:option('--executable',undefined),args:['--enable-gpu','--use-angle=metal']});
const report={diagnosticOnly:true,renderingGateQualified:false,requests:[],console:[],errors:[]};
let timer;
try {
  const page=await browser.newPage({viewport:{width:1200,height:796},deviceScaleFactor:1});
  if(args.includes('--block-external')) {
    report.blockedExternal=[];
    await page.route('**/*',route=>{
      const url=route.request().url();
      if(new URL(url).origin==='http://127.0.0.1:8765') return route.continue();
      report.blockedExternal.push(url);
      return route.abort('blockedbyclient');
    });
  }
  const started=performance.now();
  const entries=new Map();
  page.on('request',request=>{
    if(entries.size>=256){report.errors.push('Request evidence overflow');return;}
    const row={url:request.url(),resourceType:request.resourceType(),startMs:performance.now()-started};
    entries.set(request,row);report.requests.push(row);
  });
  page.on('response',response=>{const row=entries.get(response.request());if(row)row.status=response.status();});
  page.on('requestfinished',request=>{const row=entries.get(request);if(row){row.endMs=performance.now()-started;row.timing=request.timing();}});
  page.on('requestfailed',request=>{const row=entries.get(request);if(row){row.endMs=performance.now()-started;row.failure=request.failure();}});
  const ready=new Promise((resolve,reject)=>{
    timer=setTimeout(()=>reject(new Error('No first-ready event within90s')),90000);
    page.on('pageerror',error=>{report.errors.push(String(error));reject(error);});
    page.on('console',message=>{
      const text=message.text();
      if(report.console.length<128 && ['error','warning'].includes(message.type()))report.console.push({type:message.type(),text,ms:performance.now()-started});
      if(text.startsWith('PHASE0_READY ')){report.firstReady=JSON.parse(text.slice('PHASE0_READY '.length));report.navigationToReadyWallMs=performance.now()-started;resolve();}
      if(text.startsWith('PHASE0_FONT_FAILED '))reject(new Error(text));
    });
  });
  ready.catch(()=>{});
  await page.goto('http://127.0.0.1:8765/?phase0=startup-audit',{waitUntil:'domcontentloaded',timeout:30000});
  await ready;
  if(args.includes('--block-external') && (report.blockedExternal.length || report.firstReady?.fonts?.ready!==true))throw new Error('Local font startup readiness failed');
  report.runtime=await Promise.race([page.evaluate(()=>({crossOriginIsolated,skwasmLoaded:!!window._flutter_skwasmInstance,skwasmIsMultiThreaded:typeof window._flutter_skwasmInstance?._skwasm_isMultiThreaded==='function'?!!window._flutter_skwasmInstance._skwasm_isMultiThreaded():null})),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Runtime probe exceeded5s')),5000))]);
} catch(error){report.errors.push(String(error));process.exitCode=1;}
finally {
  clearTimeout(timer);
  fs.writeFileSync(option('--output','benchmark_results/execution-04/startup-diagnostic.json'),JSON.stringify(report,null,2)+'\n');
  await browser.close();
}
