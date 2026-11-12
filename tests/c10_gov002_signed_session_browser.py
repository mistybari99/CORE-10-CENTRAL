"""Real 390/1440 Chromium session swap smoke against local synthetic Supabase shim.
Does NOT call Supabase, use real credentials or certify server-side auth.
"""
import os, subprocess, sys, time, urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
PORT=8768
URL=f'http://127.0.0.1:{PORT}/docs/preview/c10-gov002-approval-preview.html'

def run():
  server=subprocess.Popen([sys.executable,'-m','http.server',str(PORT),'--bind','127.0.0.1','--directory',str(ROOT)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  try:
    for _ in range(40):
      try: urllib.request.urlopen(URL,timeout=1).close();break
      except Exception:time.sleep(.1)
    else:raise RuntimeError('session_browser_server_unavailable')
    with sync_playwright() as p:
      candidates=[os.getenv('C10_CHROMIUM'),'/usr/bin/chromium','/usr/bin/google-chrome','/opt/google/chrome/chrome']
      exe=next((v for v in candidates if v and Path(v).is_file()),None)
      browser=p.chromium.launch(executable_path=exe,headless=True,args=['--no-sandbox']) if exe else p.chromium.launch(headless=True)
      try:
        for width in [390,1440]:
          page=browser.new_page(viewport={'width':width,'height':900})
          errors=[];page.on('pageerror',lambda e: errors.append(str(e)))
          page.goto(URL)
          page.get_by_text('STOCK_ADJUST · #102').wait_for()
          page.evaluate('''async()=>{
            window.__c10Demo.destroy();
            let current='signed-owner-101', callback,unsubscribed=0;
            const record={request_id:155,business_id:101,domain:'demo_stock',action_code:'SIGNED_TEST',source_key:'SAFE-101',
              source_version:2,policy_version:1,source_fingerprint:'b'.repeat(64),
              requested_by:'signed-maker-102',requested_at:'2026-11-12T00:00:00Z',
              expires_at:'2035-01-01T00:00:00Z',stored_status:'pending',display_status:'awaiting_stage_1',
              required_checks:3,completed_checks:0};
            const client={auth:{
              async getUser(){return {data:{user:current?{id:current}:null}}},
              onAuthStateChange(fn){callback=fn;return {data:{subscription:{unsubscribe(){unsubscribed++}}}}}
            },schema(){return {
              from(view){return {select(){return {eq(){return {order(){return {async limit(){
                return {data:view==='approval_status_report_v1'?[record]:[],error:null};
              }}}}}}}}}},
              async rpc(){return {data:300,error:null}}
            }}};
            window.__testEmit=(event,user=null)=>callback(event,{user:user?{id:user}:null});
            window.__testActor=uid=>{current=uid};
            window.__testUnsubscribe=()=>unsubscribed;
            const {mountSignedGov002Workspace}=await import('/internal/enterprise-client/c10_gov002_signed_review_entry_v1.mjs');
            window.__signedUI=mountSignedGov002Workspace({root:document.querySelector('#c10-approval-workspace'),
              supabaseClient:client,businessId:101,businesses:[{id:101,name:'Fixture A'}],
              allowSignedMutations:true,environmentLabel:'SIGNED SHIM · NOT AUTH CERTIFIED'});
          }''')
          page.get_by_text('SIGNED_TEST · #155').wait_for()
          assert page.get_by_role('button',name='Approve').is_enabled(),f'{width}px confirmed signed shim action label'
          page.evaluate("window.__testEmit('SIGNED_OUT',null)")
          page.get_by_role('alert').get_by_text('সেশন বা ব্যবহারকারী পরিবর্তিত হয়েছে।',exact=False).wait_for()
          assert page.get_by_text('SIGNED_TEST · #155').count()==0,f'{width}px stale approval remains after logout'
          assert page.locator('.c10a-request').count()==0,f'{width}px old session data remains'
          assert not errors,(width,errors)
          page.evaluate('window.__signedUI.destroy()')
          assert page.evaluate('window.__testUnsubscribe()')==1,f'{width}px unsubscribed exactly once'
          page.close()
      finally:browser.close()
  finally:
    server.terminate();server.wait(timeout=5)
if __name__=='__main__':run()