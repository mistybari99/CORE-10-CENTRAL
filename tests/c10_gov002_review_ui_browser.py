"""Executable 390/1440 Chromium browser smoke + signed mock-RPC UX tests.
Run locally: python -m pip install playwright && python tests/c10_gov002_review_ui_browser.py
CI uses a real Chrome/Chromium executable; no deployment or Supabase touched.
"""
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
PORT = 8767
URL = f'http://127.0.0.1:{PORT}/docs/preview/c10-gov002-approval-preview.html'

def check(condition, label):
    if not condition:
        raise AssertionError(label)
    print('PASS', label)


def run():
    proc = subprocess.Popen([sys.executable, '-m', 'http.server', str(PORT),
                             '--bind', '127.0.0.1', '--directory', str(ROOT)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(URL, timeout=1).close()
                break
            except Exception:
                time.sleep(.1)
        else:
            raise RuntimeError('browser_fixture_server_not_ready')
        with sync_playwright() as p:
            candidates = [os.getenv('C10_CHROMIUM'),
                          '/usr/bin/chromium','/usr/bin/google-chrome',
                          '/opt/google/chrome/chrome']
            installed = next((v for v in candidates if v and Path(v).is_file()), None)
            browser = p.chromium.launch(executable_path=installed, headless=True,
                                        args=['--no-sandbox']) if installed else p.chromium.launch(headless=True)
            try:
                for width in [390, 1440]:
                    page = browser.new_page(viewport={'width':width,'height':900})
                    errors = []
                    page.on('pageerror', lambda e: errors.append(str(e)))
                    page.goto(URL)
                    page.get_by_text('অনুমোদন ব্যবস্থাপনা').wait_for()
                    page.get_by_text('STOCK_ADJUST · #102').wait_for()
                    check(not errors, f'{width}px JS free of uncaught errors: {errors}')
                    check(page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'),
                          f'{width}px no horizontal overflow')
                    check(page.locator('.c10a-request').count()==2,
                          f'{width}px pending inbox contains 2 synthetic rows')
                    check(page.get_by_role('button',name='Approve').is_disabled(),
                          f'{width}px fixture actions disabled')
                    page.get_by_role('tab',name='অনুমোদিত').click()
                    check(page.locator('.c10a-request').count()==1,
                          f'{width}px approved view and correct count')
                    page.get_by_role('tab',name='মেয়াদোত্তীর্ণ').click()
                    check(page.locator('.c10a-request').count()==1,
                          f'{width}px expired approval state')
                    page.get_by_role('button', name='Escalations').click()
                    check(page.get_by_text('Escalation #11').count()==1,
                          f'{width}px bounded escalation visible')
                    page.get_by_role('button', name='Activity',exact=True).click()
                    check(page.get_by_text('submitted · Request #102').count()==1,
                          f'{width}px timeline visible')
                    page.locator('#c10a-business-id').select_option('102')
                    page.get_by_role('button', name='Approval Inbox').click()
                    check(page.locator('.c10a-request').count()==0,
                          f'{width}px business switch clears other business rows')
                    page.close()
                # Action route is tested only against a deliberately injected mock.
                page = browser.new_page(viewport={'width':390,'height':900})
                page.goto(URL)
                page.get_by_text('STOCK_ADJUST · #102').wait_for()
                page.evaluate("""async () => {
                  window.__c10Demo.destroy();
                  const {mountGov002ApprovalUI}=await import('/internal/enterprise-client/c10_gov002_review_ui_v1.mjs');
                  let approved=false;window.__c10MockCalls=[];
                  const pending={request_id:88,business_id:101,domain:'demo_stock',action_code:'SAFE_APPROVAL',
                    source_key:'<svg onload=alert(1)>',source_version:1,requested_by:'fake-maker',
                    requested_at:'2026-11-12T12:00:00Z',expires_at:'2035-01-01T00:00:00Z',
                    stored_status:'pending',display_status:'pending'};
                  const api={
                    listStatus:async()=>[{...pending,...(approved?{stored_status:'approved',display_status:'approved'}:{})}],
                    listExceptions:async()=>[],listActivity:async()=>[],
                    decideApproval:async a=>{window.__c10MockCalls.push(a);approved=true;return 1234;},
                    withdrawApproval:async()=>{throw Error('denied')},
                    requestException:async()=>{throw Error('denied')},
                    decideException:async()=>{throw Error('denied')},
                    withdrawException:async()=>{throw Error('denied')},
                    exportActivityCsv:async()=>{throw Error('denied')}
                  };
                  window.__c10UI=mountGov002ApprovalUI({root:document.querySelector('#c10-approval-workspace'),
                    reviewClient:api,businessId:101,businesses:[{id:101,name:'Fixture A'}],
                    actionsEnabled:true,environmentLabel:'TEST ONLY · SIGNED MOCK'});
                }""")
                page.get_by_text('SAFE_APPROVAL · #88').wait_for()
                check(page.locator('svg').count()==0,'server source injected as text, not SVG/script')
                page.get_by_role('button',name='Approve').click()
                check(page.get_by_role('dialog').count()==1,'confirmation required before approve')
                check(page.evaluate('window.__c10MockCalls.length')==0,'no mutation before confirmation')
                page.get_by_role('button',name='Confirm · Server RPC').click()
                check(page.evaluate('window.__c10MockCalls.length')==1,'one explicit mock decision RPC')
                check(page.evaluate('window.__c10MockCalls[0].requestId')==88,'correct request id forwarded')
                page.get_by_role('tab',name='অনুমোদিত').click()
                check(page.get_by_role('button',name='Approve').is_disabled(), 'final approval cannot be repeated from UI')
                page.close()
            finally:
                browser.close()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

if __name__=='__main__':
    run()