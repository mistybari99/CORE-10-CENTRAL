"""CORE10 S1-c 390/1440 isolated synthetic reviewer UI smoke.
No hosted Auth/SG SQL, service tokens or external network; no operational writes.
"""
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
PORT=8781
URL=f"http://127.0.0.1:{PORT}/docs/preview/c10-np01-canonical-reviewer-preview.html"

def check(ok,label):
    if not ok: raise AssertionError(label)
    print("PASS",label)

def run():
    server=subprocess.Popen(
        [sys.executable,"-m","http.server",str(PORT),"--bind","127.0.0.1","--directory",str(ROOT)],
        stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            try:urllib.request.urlopen(URL,timeout=1).close();break
            except Exception:time.sleep(.15)
        else:raise RuntimeError("preview_http_server_unavailable")
        with sync_playwright() as p:
            candidates=[os.getenv("C10_CHROMIUM"),"/usr/bin/chromium",
                        "/usr/bin/google-chrome","/opt/google/chrome/chrome"]
            installed=next((x for x in candidates if x and Path(x).is_file()),None)
            browser=(p.chromium.launch(headless=True,executable_path=installed,args=["--no-sandbox"])
                     if installed else p.chromium.launch(headless=True,args=["--no-sandbox"]))
            try:
                for width in [390,1440]:
                    page=browser.new_page(viewport={"width":width,"height":900})
                    errors,external=[],[]
                    page.on("pageerror",lambda e:errors.append(str(e)))
                    page.on("request",lambda r:external.append(r.url)
                            if not r.url.startswith(f"http://127.0.0.1:{PORT}/") else None)
                    page.goto(URL)
                    page.get_by_text("Approval Desk").wait_for()
                    page.get_by_text("adjust · #405").wait_for()
                    check(not errors,f"{width}px no JS errors: {errors}")
                    check(not external,f"{width}px no external requests: {external}")
                    check(page.evaluate("document.documentElement.scrollWidth <= innerWidth+1"),
                          f"{width}px no horizontal overflow")
                    check(page.locator(".c10np-card").count()==1,f"{width}px 1 scoped review task")
                    check(page.get_by_role("button",name="Approve").count()==0,
                          f"{width}px decision action disabled in synthetic preview")
                    page.get_by_role("button",name="Approval Status").click()
                    check(page.locator(".c10np-card").count()==1,
                          f"{width}px status from canonical RPC")
                    check(page.get_by_text("1/3").count()==1,f"{width}px pending stage progress")
                    page.get_by_role("button",name="Audit Activity").click()
                    check(page.locator(".c10np-card").count()==1,
                          f"{width}px canonical audit event")
                    check(page.get_by_text("Audit #9001").count()==1,
                          f"{width}px audit receipt reference")
                    page.evaluate("window.__c10npSignout()")
                    page.get_by_text("Session invalidated",exact=False).wait_for()
                    check(page.locator(".c10np-card").count()==0,
                          f"{width}px logout clears all scoped data")
                    check(not errors,f"{width}px no signout JS errors: {errors}")
                    page.close()
            finally:browser.close()
    finally:
        server.terminate();server.wait(timeout=5)

if __name__=="__main__":run()
