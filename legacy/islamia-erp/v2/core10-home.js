/* CORE 10 owner entry/home route. No staff or Islamia stylesheet changes. */
(function(){
 "use strict";
 if(!document.body||document.body.dataset.core10Owner!=="1")return;
 var A=window.BOS_APP;
 function sendMasterHome(){
  if(window.location.hash===""||/^#\/?home$/.test(window.location.hash)){
    window.location.hash="#/organization"
  }
 }
 // Set the owner entry point before the app's DOMContentLoaded auth boot runs.
 sendMasterHome();
 window.addEventListener("hashchange",sendMasterHome);
 if(!A||!A.H)return;
 var original=A.H.go;
 if(typeof original==="function")A.H.go=function(button){
  if(A.S&&A.S.ctx&&A.S.ctx.is_owner&&button&&button.dataset&&button.dataset.v==="home"){
   window.location.hash="#/organization";return
  }
  return original.apply(this,arguments)
 };
 var main=A.H.navmain;
 if(typeof main==="function")A.H.navmain=function(){
  if(A.S&&A.S.ctx&&A.S.ctx.is_owner){
   window.location.hash="#/organization";return
  }
  return main.apply(this,arguments)
 };
})();