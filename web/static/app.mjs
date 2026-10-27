import {Replica,Drive,palette,decodeValue,synchronize,mutationID} from './sync.mjs';
const $=id=>document.getElementById(id);
const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const today=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};
const clock=n=>`${String(Math.floor(n/60)).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`;
const parseTime=s=>s ? Number(s.slice(0,2))*60+Number(s.slice(3,5)):undefined;
let settingsVersion;
let config={},account=null,replica=new Replica(),values={},conflicts=[],selected=null,busy=false,scale=6,sideDetails=false,drive=null,expires=0,debounce,editorKey,editorVersion,session=0;
const channel=typeof BroadcastChannel!=='undefined'?new BroadcastChannel('yoteikan.web.v1'):null;
const storageKey=()=>`yoteikan.web.v1/${account.id}`;
const hours=()=>values.hours||{start:300,end:1440};
const colors=()=>values.colors||palette;
const day=()=>$('day').value;
function message(text=''){ $('message').textContent=text; }
function load(){const saved=localStorage.getItem(storageKey());replica=new Replica(saved?JSON.parse(saved):{});}
function persist(){localStorage.setItem(storageKey(),JSON.stringify(replica.save()));channel?.postMessage(account.id);}
async function locked(fn){
 if(!account)throw Error('Googleでログインするかサンプルを開いてください。');
 if(!navigator.locks)throw Error('このブラウザーでは安全な保存を利用できません。最新のSafari・Chrome・EdgeをHTTPSでお使いください。');
 const identity=account.id;
 return navigator.locks.request('yoteikan.web.v1/'+identity,async()=>{
  if(account?.id!==identity)throw Error('アカウントが変わりました。もう一度操作してください。');
  load();return fn();
 });
}
async function run(fn){if(busy)return;busy=true;updateButtons();message();try{await fn();await render();}catch(e){message(e.message||'処理に失敗しました。再試行してください。');await render().catch(()=>{});}finally{busy=false;updateButtons();}}
function updateButtons(){for(const id of ['login','welcomeLogin','logout','sync','add','settings','demo'])$(id).disabled=busy;}
async function sync(){
 if(!drive || Date.now()>=expires)throw Error('Googleにログインすると同期できます。端末内の変更は保持されています。');
 await locked(async()=>synchronize(replica,drive,persist));
}
function scheduleSync(){clearTimeout(debounce);if(account?.id!=='demo')debounce=setTimeout(()=>run(sync),2000);}
async function commit(key,value,expected){
 await locked(async()=>{
  if(expected!==undefined && JSON.stringify((await replica.heads(key)).map(([id])=>id))!==expected)throw Error('別の端末やタブで変更されました。付箋を開き直して内容を確認してください。');
  if((await replica.conflicts()).some(c=>c.key===key))throw Error('先に競合する内容を選んでください。');
  await replica.resolve(key,value);persist();
 });
 scheduleSync();
}
async function render(){
 $('workspace').hidden=!account;$('welcome').hidden=!!account;$('logout').hidden=!account;$('login').textContent=account?'Googleに再ログイン':'Googleでログイン';
 $('accountLabel').textContent=account?.email||'あなたの一日を、付箋で。';
 if(!account)return;
 values=await replica.values();conflicts=await replica.conflicts();
 const pending=(await replica.pending()).length;
 $('syncStatus').textContent=account.id==='demo'?'サンプル・Googleへ送信しません':`${pending?`未送信 ${pending}件 · `:''}${replica.lastSync?'最終同期 '+new Date(replica.lastSync).toLocaleTimeString('ja-JP',{hour:'2-digit',minute:'2-digit'}):'まだ同期していません'}`;
 $('sync').hidden=account.id==='demo';
 $('dayTitle').textContent=new Date(day()+'T12:00:00').toLocaleDateString('ja-JP',{month:'long',day:'numeric',weekday:'long'});
 $('zoomLabel').textContent=`${scale/6}倍`;
 const all=Object.entries(values).filter(([key,v])=>key.startsWith('sticky/')&&v.day===day());
 const {start,end}=hours();const scheduled=all.filter(([,v])=>v.start!==undefined&&v.start!==null&&v.start>=start&&v.start+v.minutes<=end).sort((a,b)=>a[1].start-b[1].start||a[0].localeCompare(b[0]));
 const timeline=$('timeline');timeline.replaceChildren();timeline.style.height=(end-start)*scale+'px';
 for(let minute=start;minute<=end;minute+=60){const line=node('div',undefined,'hour');line.style.top=(minute-start)*scale+'px';line.append(node('span',clock(minute)));timeline.append(line);}
 // Compute lanes per connected overlap group, keeping short cards inside their duration.
 const groups=[];let group=[],until=-1;
 for(const item of scheduled){if(item[1].start>=until&&group.length){groups.push(group);group=[];until=-1;}group.push(item);until=Math.max(until,item[1].start+item[1].minutes);}if(group.length)groups.push(group);
 for(const group of groups){const ends=[],placed=[];for(const [key,v] of group){let lane=ends.findIndex(t=>t<=v.start);if(lane<0)lane=ends.length;ends[lane]=v.start+v.minutes;placed.push({key,v,lane});}for(const {key,v,lane}of placed){const card=sticky(key,v);card.style.top=(v.start-start)*scale+'px';card.style.height=(v.minutes*scale-3)+'px';card.style.left=`${lane*100/ends.length}%`;card.style.width=`calc(${100/ends.length}% - 3px)`;timeline.append(card);}}
 const inbox=$('inbox');inbox.replaceChildren();const scheduledKeys=new Set(scheduled.map(([key])=>key));
 for(const [key,v]of all.filter(([key])=>!scheduledKeys.has(key))){const card=sticky(key,v);if(v.start!==undefined&&v.start!==null)card.append(node('small','時間外 '+clock(v.start)));inbox.append(card);}
 inbox.append(node('p','ここに付箋を貯めて、時間割へドラッグ。\nタップして時刻を入力することもできます。','drop-hint'));
 inbox.ondragover=e=>e.preventDefault();inbox.ondrop=e=>drop(e,undefined);
 timeline.ondragover=e=>e.preventDefault();timeline.ondrop=e=>{const minute=Math.round((e.clientY-timeline.getBoundingClientRect().top)/scale/5)*5+start;drop(e,minute);};
 $('presets').replaceChildren();for(const [,v]of Object.entries(values).filter(([key])=>key.startsWith('preset/'))){const b=node('button',`${v.title} · ${v.minutes}分`);b.onclick=()=>openEditor(null,{title:v.title,minutes:v.minutes,tone:v.tone,memo:v.memo});$('presets').append(b);}
 if(!$('presets').children.length)$('presets').append(node('small','iPhoneで作成したプリセットが表示されます。'));
 renderDetails();renderConflicts();
}
function sticky(key,v){
 const b=node('button',undefined,'sticky'+(selected===key?' selected':''));b.dataset.key=key;b.draggable=true;
 const color=colors().find(x=>x.id===v.tone)||palette[0];b.style.backgroundColor='#'+color.hex;b.style.borderLeftColor='#'+color.hex;
 const rgb=parseInt(color.hex,16),brightness=((rgb>>16)*299+((rgb>>8)&255)*587+(rgb&255)*114)/1000;b.style.color=brightness<135?'#ffffff':'#293b36';
 b.append(node('strong',v.title||'名称未設定'),node('small',`${v.start===undefined||v.start===null?'未配置':clock(v.start)} · ${v.minutes}分`));
 b.onclick=()=>{selected=key;render();};b.ondblclick=()=>openEditor(key);
 b.ondragstart=e=>{e.dataTransfer.setData('text/plain',key);e.dataTransfer.effectAllowed='move';};
 return b;
}
async function drop(e,start){e.preventDefault();const key=e.dataTransfer.getData('text/plain');if(!key.startsWith('sticky/')||!values[key])return;
 await run(async()=>{const v=values[key],expected=JSON.stringify((await replica.heads(key)).map(([id])=>id));if(start!==undefined&&(start<hours().start||start+v.minutes>hours().end))throw Error('この長さを配置できる時間にドロップしてください。');const next={...v};if(start===undefined)delete next.start;else next.start=start;await commit(key,next,expected);selected=key;});}
function renderDetails(){for(const id of ['details','compactDetails']){const target=$(id);target.replaceChildren();const v=values[selected];if(!v){target.append(node('p','付箋を選ぶと、詳細メモをここで確認できます。'));continue;}
 target.append(node('h3',v.title),node('small',`${v.day} · ${v.start===undefined||v.start===null?'未配置':clock(v.start)} · ${v.minutes}分`),node('p',v.memo||'メモはまだありません。'));
 const b=node('button','時刻・長さ・メモを編集');b.onclick=()=>openEditor(selected);target.append(b);
 if(v.start!==undefined&&v.start!==null){const back=node('button','未配置へ戻す');back.onclick=()=>run(async()=>{const next={...v};delete next.start;await commit(selected,next);});target.append(back);}
 }$('inbox').hidden=sideDetails;$('compactDetails').hidden=!sideDetails;$('sideTitle').textContent=sideDetails?'予定の詳細':'付箋';$('switchSide').textContent=sideDetails?'付箋へ':'詳細へ';}
function renderConflicts(){const box=$('conflicts');box.hidden=!conflicts.length;box.replaceChildren();if(!conflicts.length)return;box.append(node('h3','別の端末との変更が重なっています'),node('p','残す内容を選んでください。選択した結果はiPhoneにも同期されます。競合中の項目は編集できません。'));
 for(const {key,choices}of conflicts){const row=node('div',undefined,'conflict-row');row.append(node('p',key==='hours'?'計画の時間帯':key==='colors'?'付箋の色':'付箋・プリセット'));
 for(const [,e]of choices){const v=e.value===undefined?undefined:decodeValue(e.value);const text=v===undefined?'削除する':v.title?`${v.title} · ${v.day||'プリセット'} · ${v.start===undefined?'未配置':clock(v.start)} · ${v.minutes}分\n${v.memo||''}`:JSON.stringify(v);const b=node('button',text);b.onclick=()=>run(async()=>{await locked(async()=>{await replica.resolve(key,v);persist();});scheduleSync();});row.append(b);}box.append(row);}}
async function openEditor(key,seed={}){if(busy)return;if(key&&conflicts.some(c=>c.key===key)){message('先に競合する内容を選んでください。');return;}
 editorKey=key;editorVersion=key?JSON.stringify((await replica.heads(key)).map(([id])=>id)):undefined;
 const v=values[key]||{title:'',minutes:30,tone:colors()[0].id,memo:'',day:day(),reminderMinutes:5,...seed};const form=$('editForm');form.reset();
 form.elements.title.value=v.title;form.elements.day.value=v.day;form.elements.minutes.value=v.minutes;form.elements.start.value=v.start===undefined||v.start===null?'':clock(v.start);form.elements.memo.value=v.memo||'';
 form.elements.tone.replaceChildren(...colors().map(c=>{const o=node('option',c.name);o.value=c.id;return o;}));form.elements.tone.value=v.tone;
 if(v.reminderMinutes!==undefined&&v.reminderMinutes!==null&&![...form.elements.reminder.options].some(o=>o.value===String(v.reminderMinutes))){const o=node('option',v.reminderMinutes+'分前');o.value=v.reminderMinutes;form.elements.reminder.append(o);}
 form.elements.reminder.value=v.reminderMinutes===null?'':String(v.reminderMinutes??5);$('delete').hidden=!key;$('editError').textContent='';$('editor').showModal();}
$('editForm').onsubmit=async e=>{e.preventDefault();const form=e.target;await run(async()=>{try{const id=editorKey?.slice(7)||crypto.randomUUID().toUpperCase();const v={...(values[editorKey]||{}),id,title:form.elements.title.value.trim(),day:form.elements.day.value,minutes:Number(form.elements.minutes.value),tone:Number(form.elements.tone.value),memo:form.elements.memo.value,reminderMinutes:form.elements.reminder.value===''?null:Number(form.elements.reminder.value)};
 if(!v.title)throw Error('タイトルを入力してください。');const start=parseTime(form.elements.start.value);if(start!==undefined){if(start%5!==0||start+v.minutes>1440)throw Error('5分刻みで、一日の中に収まる時刻を選んでください。');v.start=start;}else delete v.start;
 await commit('sticky/'+id,v,editorVersion);selected='sticky/'+id;$('editor').close();}catch(error){$('editError').textContent=error.message;throw error;}});};
$('delete').onclick=()=>{if(!confirm('この付箋を削除しますか？同期するとiPhoneからも削除されます。'))return;run(async()=>{await commit(editorKey,undefined,editorVersion);selected=null;$('editor').close();});};
for(const b of document.querySelectorAll('[data-close]'))b.onclick=()=>$(b.dataset.close).close();
$('add').onclick=()=>openEditor(null);
$('switchSide').onclick=()=>{sideDetails=!sideDetails;renderDetails();};
$('zoomIn').onclick=()=>{scale=Math.min(12,scale+3);render();};$('zoomOut').onclick=()=>{scale=Math.max(6,scale-3);render();};
$('settings').onclick=async()=>{const form=$('settingsForm');settingsVersion=JSON.stringify((await replica.heads('hours')).map(([id])=>id));for(const name of ['start','end']){form.elements[name].replaceChildren();for(let n=name==='start'?0:60;n<=(name==='end'?1440:1380);n+=60){const o=node('option',clock(n));o.value=n;form.elements[name].append(o);}form.elements[name].value=hours()[name];}$('settingsError').textContent='';$('settingsDialog').showModal();};
$('settingsForm').onsubmit=e=>{e.preventDefault();run(async()=>{const form=e.target;const v={start:Number(form.elements.start.value),end:Number(form.elements.end.value)};if(v.start>=v.end){$('settingsError').textContent='終了は開始より後にしてください。';return;}await commit('hours',v,settingsVersion);$('settingsDialog').close();});};
$('day').value=today();$('day').onchange=()=>{if(day()) {selected=null;render();}};
function shiftDay(n){const d=new Date(day()+'T12:00:00');d.setDate(d.getDate()+n);$('day').value=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;selected=null;render();}
$('previous').onclick=()=>shiftDay(-1);$('next').onclick=()=>shiftDay(1);$('today').onclick=()=>{$('day').value=today();render();};
$('sync').onclick=()=>run(sync);
$('logout').onclick=()=>{if(busy)return;clearTimeout(debounce);session++;drive=null;expires=0;account=null;selected=null;replica=new Replica();localStorage.removeItem('yoteikan.web.lastAccount');$('editor').close();$('settingsDialog').close();message('ログアウトしました。このブラウザーに保存済みの変更はアカウント別に保持しています。');render();};
async function login(){
 if(!config.clientID){message('Web用GoogleクライアントIDが未設定です。開発者向けの docs/web.md を参照してください。サンプルは試せます。');return;}
 if(!globalThis.google?.accounts?.oauth2){message('Googleのログインを読み込めませんでした。通信環境を確認して再試行してください。');return;}
 const loginSession=++session;
 const client=google.accounts.oauth2.initTokenClient({client_id:config.clientID,scope:'openid email profile https://www.googleapis.com/auth/drive.appdata',error_callback:()=>message('ログイン画面が閉じられたか、ポップアップを開けませんでした。再試行してください。'),callback:response=>run(async()=>{
  if(response.error)throw Error('Googleログインに失敗しました。もう一度お試しください。');
  if(!google.accounts.oauth2.hasGrantedAllScopes(response,'https://www.googleapis.com/auth/drive.appdata'))throw Error('Driveのアプリ専用領域へのアクセスを許可してください。');
  const result=await fetch('https://openidconnect.googleapis.com/v1/userinfo',{headers:{Authorization:`Bearer ${response.access_token}`},signal:AbortSignal.timeout(30000)});if(!result.ok)throw Error('Googleアカウントを確認できませんでした。');const user=await result.json();if(typeof user.sub!=='string')throw Error('Googleアカウントを確認できませんでした。');
  if(session!==loginSession)return;clearTimeout(debounce);account={id:user.sub,email:user.email||'Googleアカウント'};selected=null;load();drive=new Drive(response.access_token);expires=Date.now()+Number(response.expires_in)*1000;localStorage.setItem('yoteikan.web.lastAccount',JSON.stringify(account));await sync();
 })});client.requestAccessToken({prompt:'select_account'});
}
$('login').onclick=login;$('welcomeLogin').onclick=login;
$('demo').onclick=()=>run(async()=>{clearTimeout(debounce);session++;account={id:'demo',email:'サンプル · Googleへ送信しません'};drive=null;expires=0;load();if(!replica.events.length){await replica.resolve('colors',palette);await replica.resolve('hours',{start:420,end:1320});const presetID=crypto.randomUUID().toUpperCase();await replica.resolve('preset/'+presetID,{id:presetID,title:'読書',minutes:30,tone:0,memo:'気になる章を、ゆっくり読む。',dailyCount:0});for(const [title,minutes,start,tone,memo]of [['朝の読書',30,480,0,'気になる章を、ゆっくり読む。'],['資料作成',60,540,1,'今週の振り返りと、来週の準備。'],['運動',30,undefined,2,'いつもの道を散歩する。'],['休憩',15,undefined,3,'お茶をいれて、ひと息。']]){const id=crypto.randomUUID().toUpperCase();const value={id,title,minutes,tone,memo,day:day(),reminderMinutes:null};if(start!==undefined)value.start=start;await replica.resolve('sticky/'+id,value);}persist();}await render();$('timelineScroll').scrollTop=55*scale;});
channel?.addEventListener('message',e=>{if(e.data===account?.id&&!busy)run(async()=>{await locked(async()=>{});});});
window.addEventListener('beforeunload',e=>{if(account&&account.id!=='demo'&&replica.events.length && busy){e.preventDefault();e.returnValue='';}});
try{config=await (await fetch('/config.json')).json();const saved=localStorage.getItem('yoteikan.web.lastAccount');if(saved){const parsed=JSON.parse(saved);if(typeof parsed.id==='string'&&typeof parsed.email==='string'){account=parsed;load();message('保存済みの予定を表示しています。Googleにログインして最新の予定を同期してください。');}}await render();}catch(e){message('設定または保存データを読み込めませんでした。ブラウザーのストレージが利用できるか確認してください。');}
