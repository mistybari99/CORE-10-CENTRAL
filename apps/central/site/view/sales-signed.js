/* Signed Sales host. The canonical Sales client owns every permission and receipt. */
(function(win){
  "use strict";
  const d=win.document,root=d.getElementById("sales-signed-root");
  if(!root)return;
  const target="https://rhrqhbyzrhaafynfhdaf.supabase.co",cfg=win.CORE10_CONTROL_CENTRE_CONFIG;
  let lang="bn";
  try{lang=win.localStorage.getItem("core10.preview.lang")==="en"?"en":"bn";}catch(_){}
  d.documentElement.lang=lang;
  const t=(bn,en)=>lang==="en"?en:bn;
  function el(tag,text,cls){const n=d.createElement(tag);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n;}
  function message(bn,en){const p=el("p",t(bn,en),"occ-status");p.setAttribute("role","alert");root.replaceChildren(p);}
  if(!cfg||cfg.url!==target||typeof cfg.key!=="string"||!cfg.key.startsWith("sb_publishable_")||
      !win.supabase?.createClient||!win.CORE10_SALES_ORDER_ENTRY?.attach||!win.CORE10_SALES_INVOICE_UI){
    message("অনুমোদিত বিক্রয় সংযোগ পাওয়া যায়নি।","Authorized Sales connection unavailable.");return;
  }
  const client=win.supabase.createClient(cfg.url,cfg.key,{auth:{detectSessionInUrl:false}});
  let epoch=0,mounted=null,closed=false;
  function clear(){++epoch;try{mounted?.destroy();}finally{mounted=null;root.replaceChildren();}}
  function signIn(){
    if(closed)return;clear();const n=epoch;
    const form=el("form",null,"occ-dialog");form.id="sales-login";
    const email=el("input"),pass=el("input"),submit=el("button",t("সাইন ইন করুন","Sign in"),"occ-primary"),err=el("p");
    email.id="sales-email";email.type="email";email.autocomplete="username";email.required=true;
    pass.id="sales-password";pass.type="password";pass.autocomplete="current-password";pass.required=true;
    const le=el("label",t("ইমেইল","Email")),lp=el("label",t("পাসওয়ার্ড","Password"));le.htmlFor=email.id;lp.htmlFor=pass.id;
    submit.type="submit";err.id="sales-login-error";err.setAttribute("role","alert");
    form.append(el("h2",t("বিক্রয় · সাইন ইন","Sales · Sign in")),el("p",t("CORE10 স্টেজিং: অর্ডার ও খসড়া ইনভয়েস। স্টক বা টাকা পোস্ট হয় না।","CORE10 staging: orders and draft invoices. No Stock or Money posting.")),le,email,lp,pass,submit,err);
    form.addEventListener("submit",async ev=>{
      ev.preventDefault();if(n!==epoch||closed||submit.disabled)return;
      submit.disabled=true;err.textContent="";
      try{
        const res=await client.auth.signInWithPassword({email:email.value.trim(),password:pass.value});pass.value="";
        if(n!==epoch||closed)return;
        if(res.error||!res.data?.user){err.textContent=t("সাইন ইন হয়নি।","Sign-in failed.");return;}
        await refresh();
      }catch(_){pass.value="";if(n===epoch&&!closed)err.textContent=t("সাইন ইন হয়নি।","Sign-in failed.");}
      finally{submit.disabled=false;}
    });
    root.replaceChildren(form);
  }
  async function refresh(){
    if(closed)return;clear();const n=epoch;
    message("সেশন যাচাই হচ্ছে…","Checking signed session…");
    try{
      const check=await client.auth.getUser();
      if(n!==epoch||closed)return;
      if(check.error||!check.data?.user?.id){signIn();return;}
      const toolbar=el("div",null,"occ-topline"),back=el("a",t("মূল ERP","Main ERP")),logout=el("button",t("সাইন আউট","Sign out"),"occ-secondary");
      back.href="/#/sales";logout.id="sales-signout";logout.type="button";
      logout.addEventListener("click",async()=>{if(n!==epoch||closed)return;clear();const k=epoch;message("সাইন আউট হচ্ছে…","Signing out…");try{const res=await client.auth.signOut();if(k===epoch&&!closed){if(res.error)message("সাইন আউট ব্যর্থ। পৃষ্ঠা পুনরায় খুলুন।","Sign-out failed. Reopen this page.");else signIn();}}catch(_){if(k===epoch&&!closed)message("সাইন আউট ব্যর্থ।","Sign-out failed.");}});
      toolbar.append(back,el("strong",t("CORE10 স্টেজিং · খসড়া বিক্রয়","CORE10 staging · draft Sales")),logout);
      const host=el("section");host.id="sales-signed-workspace";root.replaceChildren(toolbar,host);
      const view=win.CORE10_SALES_ORDER_ENTRY.attach(host,{client,backendMode:"signed",lang});
      mounted=view;
      await view.ready;
      if(n!==epoch||closed)view.destroy();
    }catch(_){if(n===epoch&&!closed){clear();message("বিক্রয় সংযোগ যাচাই করা যায়নি। পৃষ্ঠা পুনরায় খুলুন।","Sales connection could not be verified. Reopen this page.");}}
  }
  const sub=client.auth.onAuthStateChange(event=>{
    if(closed||event==="INITIAL_SESSION")return;
    clear();const n=epoch;
    // Never call an async Auth method synchronously inside the Auth callback.
    win.setTimeout(()=>{if(closed||n!==epoch)return;if(event==="SIGNED_OUT")signIn();else refresh();},0);
  })?.data?.subscription;
  if(!sub?.unsubscribe){clear();message("সেশন যাচাই অনুপলব্ধ।","Session verification unavailable.");return;}
  win.addEventListener("pagehide",()=>{closed=true;clear();sub.unsubscribe();},{once:true});
  win.addEventListener("pageshow",event=>{if(event.persisted)win.location.reload();});
  refresh();
})(window);
