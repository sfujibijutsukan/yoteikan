// Wire-compatible with iOS SyncModel.swift. Preserve incoming Base64 bytes exactly.
export const canonical = value => JSON.stringify(value, (_, v) => v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.keys(v).sort().map(k => [k,v[k]])) : v);
const utf8 = new TextEncoder();
export const encodeValue = v => {
 const bytes = utf8.encode(canonical(v)); let binary = '';
 for (const byte of bytes) binary += String.fromCharCode(byte);
 return btoa(binary);
};
export const decodeValue = v => JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(Uint8Array.from(atob(v), c=>c.charCodeAt(0))));
export async function mutationID(event) {
 return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',utf8.encode(canonical(event)))),x=>x.toString(16).padStart(2,'0')).join('');
}
export const palette = [ ['準備','E0EDCC'],['仕事','F7E3B3'],['生活','DBE6F7'],['休憩','F5D9CF'] ].map(([name,hex],id)=>({id,name,hex}));
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const integer = (v,min,max) => Number.isInteger(v) && v>=min && v<=max;
export function validate(event) {
 if (!event || typeof event.key !== 'string' || event.key.length>=100 || !Array.isArray(event.parents) || event.parents.length>=10000 || !event.parents.every(x=>typeof x==='string' && /^[a-f0-9]{64}$/.test(x)) || Object.keys(event).some(k=>!['key','parents','value'].includes(k))) throw Error('同期データの形式が不正です。');
 const [type,id] = event.key.split('/');
 const v = event.value === undefined ? undefined : decodeValue(event.value);
 let valid = false;
 if (event.key==='hours') valid = v && integer(v.start,0,1439) && integer(v.end,1,1440) && v.start<v.end && v.start%60===0 && v.end%60===0;
 else if (event.key==='colors') valid = Array.isArray(v) && v.length>0 && v.length<=1000 && new Set(v.map(x=>x.id)).size===v.length && v.every(x=>Number.isInteger(x.id) && typeof x.name==='string' && x.name.length>0 && /^[0-9a-f]{6}$/i.test(x.hex));
 else if (['sticky','preset'].includes(type) && uuid.test(id) && event.key===`${type}/${id}`) valid = v===undefined || v && v.id?.toUpperCase()===id.toUpperCase() && typeof v.title==='string' && integer(v.minutes,5,720) && (v.memo===undefined || typeof v.memo==='string') && (v.tone===undefined || Number.isInteger(v.tone)) && (type!=='sticky' || /^\d{4}-\d{2}-\d{2}$/.test(v.day) && (v.start===undefined || v.start===null || integer(v.start,0,1440-v.minutes))) && (type!=='preset' || v.dailyCount===undefined || integer(v.dailyCount,0,20));
 else if (type==='daily' && /^daily\/\d{4}-\d{2}-\d{2}$/.test(event.key)) valid = v===undefined || v && !Array.isArray(v) && Object.entries(v).every(([k,n])=>uuid.test(k)&&integer(n,0,20));
 if (!valid) throw Error('同期データの形式が不正です。端末のデータは保持しています。');
}
export class Replica {
 constructor(saved={}) { this.events = saved.events || []; this.uploaded = new Set(saved.uploaded||[]); this.downloaded = new Set(saved.downloaded||[]); this.lastSync = saved.lastSync || null; }
 save() { return {events:this.events,uploaded:[...this.uploaded],downloaded:[...this.downloaded],lastSync:this.lastSync}; }
 async index() {
  if(this.indexSource!==this.events){this.indexSource=this.events;this.indexPromise=Promise.all(this.events.map(async e=>[await mutationID(e),e])).then(items=>new Map(items));}
  return new Map(await this.indexPromise);
 }
 async heads(key) {
  const all = (await this.index()); const removed = new Set(this.events.filter(e=>e.key===key).flatMap(e=>e.parents));
  return [...all].filter(([id,e])=>e.key===key && !removed.has(id)).sort(([a],[b])=>a.localeCompare(b));
 }
 async receive(events) {
  events.forEach(validate); const all = await this.index();
  for (const e of events) all.set(await mutationID(e),structuredClone(e));
  for (const [id,e] of all) for(const p of e.parents) { if(p===id || all.has(p) && all.get(p).key!==e.key) throw Error('同期データの参照先が不正です。'); }
  if(all.size>100000) throw Error('同期履歴が上限を超えています。');
  this.events = [...all].sort(([a],[b])=>a.localeCompare(b)).map(([,e])=>e);
 }
 async resolve(key,value) {
  const e = {key,parents:(await this.heads(key)).map(([id])=>id).sort()};
  if(value!==undefined) e.value=encodeValue(value);
  await this.receive([e]);
 }
 async conflicts() {
  const result=[];
  for (const key of new Set(this.events.map(e=>e.key))) {
   if(key.startsWith('daily/')) continue;
   const heads=await this.heads(key);
   if(heads.length>1 && heads.some(([,e])=>e.value!==heads[0][1].value)) result.push({key,choices:heads});
  }
  return result;
 }
 async values() {
  const result={};
  for (const key of new Set(this.events.map(e=>e.key))) {
   const heads=await this.heads(key);
   if(key.startsWith('daily/')) { const counts={}; for(const [,e] of heads) if(e.value) for(const [id,n] of Object.entries(decodeValue(e.value))) counts[id]=Math.max(counts[id]||0,n); result[key]=counts; }
   else if(heads.length && heads[0][1].value!==undefined) result[key]=decodeValue(heads[0][1].value);
  }
  return result;
 }
 async pending() { return [...await this.index()].filter(([id])=>!this.uploaded.has(id)); }
}
export class Drive {
 constructor(token,fetcher=fetch) { this.token=token; this.fetcher=fetcher; }
 async request(url,options={}) {
  const response=await this.fetcher(url,{...options,headers:{Authorization:`Bearer ${this.token}`,...options.headers},signal:AbortSignal.timeout(30000)});
  if(!response.ok) {
   const body=await response.json().catch(()=>({}));
   const reasons=[...(body.error?.errors||[]),...(body.error?.details||[])].map(x=>x.reason);
   if(response.status===401) throw Error('ログインの有効期限が切れました。Googleに再ログインしてください。');
   if(reasons.some(x=>['accessNotConfigured','SERVICE_DISABLED'].includes(x))) throw Error('Google Drive APIが無効です。新しい予定館プロジェクトでDrive APIを有効にしてください。');
   if(reasons.includes('insufficientPermissions')) throw Error('Driveの同期用領域へのアクセスを許可してログインし直してください。');
   throw Error(`Driveへのアクセスに失敗しました（${response.status}${reasons.length?': '+reasons.join(', '):''}）。再試行してください。`);
  }
  const text=await response.text(); if(utf8.encode(text).length>8000000) throw Error('同期ファイルが大きすぎます。');
  return JSON.parse(text);
 }
 async fetchChanges(known) {
  let pageToken; const files=[];
  do {
   const q=new URLSearchParams({spaces:'appDataFolder',q:"appProperties has { key='yoteikan' and value='sync-v1' }",fields:'nextPageToken,files(id,size)',pageSize:'1000'});
   if(pageToken) q.set('pageToken',pageToken);
   const page=await this.request(`https://www.googleapis.com/drive/v3/files?${q}`);
   if(!Array.isArray(page.files)) throw Error('Driveの一覧を読み込めませんでした。');
   files.push(...page.files); pageToken=page.nextPageToken;
   if(files.length>100000) throw Error('同期ファイルが多すぎます。');
  } while(pageToken);
  const events=[];
  for(const file of files) if(!known.has(file.id)) {
   if(!/^\d+$/.test(file.size||'') || Number(file.size)>8000000) throw Error('同期ファイルのサイズが不正です。');
   const batch=await this.request(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(file.id)}?alt=media`);
   if(batch.version!==1) throw Error('新しい同期形式です。Web版を更新してください。');
   if(!Array.isArray(batch.mutations) || batch.mutations.length>100000) throw Error('同期データの形式が不正です。');
   batch.mutations.forEach(validate); events.push(...batch.mutations);
  }
  return {events,files:files.map(x=>x.id)};
 }
 async append(events) {
  const boundary='yoteikan-'+crypto.randomUUID();
  const metadata={name:`yoteikan-sync-v1-${crypto.randomUUID()}.json`,parents:['appDataFolder'],mimeType:'application/json',appProperties:{yoteikan:'sync-v1'}};
  const payload=canonical({version:1,mutations:events});
  if(utf8.encode(payload).length>8000000) throw Error('未送信データが大きすぎます。');
  const body=`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Type: application/json\r\n\r\n${payload}\r\n--${boundary}--\r\n`;
  const result=await this.request('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id',{method:'POST',headers:{'Content-Type':`multipart/related; boundary=${boundary}`},body});
  if(typeof result.id!=='string') throw Error('送信結果を読み込めませんでした。');
  return result.id;
 }
}
export async function synchronize(replica,drive,persist=()=>{}) {
 // Caller holds the per-account Web Lock; failed downloads never partially apply.
 const changes=await drive.fetchChanges(replica.downloaded);
 await replica.receive(changes.events);
 for(const event of changes.events) replica.uploaded.add(await mutationID(event));
 replica.downloaded=new Set(changes.files); await persist();
 const pending=await replica.pending();
 if(pending.length) {
  const file=await drive.append(pending.map(([,e])=>e));
  pending.forEach(([id])=>replica.uploaded.add(id)); replica.downloaded.add(file);
 }
 replica.lastSync=new Date().toISOString(); await persist();
}
