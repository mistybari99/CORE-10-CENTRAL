/* CORE 10 | Owner-only browser chrome theme.
   Keeps the PWA/address-bar color independent of Islamia's business profile. */
(function(){
 "use strict";
 if(!document.body||document.body.dataset.core10Owner!=="1")return;
 var meta=document.querySelector('meta[name="theme-color"]');
 if(!meta)return;
 function sync(){
   if(meta.getAttribute("content")!=="#0d2133")meta.setAttribute("content","#0d2133");
 }
 if(window.BOS_THEME&&typeof window.BOS_THEME.set==="function"){
   var oldSet=window.BOS_THEME.set;
   window.BOS_THEME.set=function(next){
     var result=oldSet.apply(this,arguments);
     sync();
     return result
   }
 }
 if(typeof MutationObserver==="function"){
   var observer=new MutationObserver(sync);
   observer.observe(meta,{attributes:true,attributeFilter:["content"]})
 }
 sync();
})();