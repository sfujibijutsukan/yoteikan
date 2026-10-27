import {readFileSync} from 'node:fs';
import test from 'node:test';import assert from 'node:assert/strict';
import {Replica,Drive,canonical,encodeValue,decodeValue,mutationID,palette,synchronize} from '../static/sync.mjs';
const id='12345678-1234-1234-1234-123456789ABC',key='sticky/'+id;
const sticky={id,title:'読書 📚',minutes:30,tone:0,memo:'一行目\n日本語 / <script>',day:'2026-10-27',reminderMinutes:null};
test('Japanese values and canonical mutation IDs match Swift fixture',async()=>{
 assert.deepEqual(decodeValue(encodeValue(sticky)),sticky);
 const fixture={key:'hours',parents:[],value:'eyJlbmQiOjE0NDAsInN0YXJ0IjozMDB9'};
 assert.equal(canonical(fixture),'{"key":"hours","parents":[],"value":"eyJlbmQiOjE0NDAsInN0YXJ0IjozMDB9"}');
 // SHA256 verified independently with Swift CryptoKit in tools/web-sync-fixture.swift.
 const golden=JSON.parse(readFileSync(new URL('./swift-fixture.json',import.meta.url),'utf8'));
 assert.deepEqual(fixture,golden.mutation);
 assert.equal(await mutationID(fixture),golden.sha256);
});
test('independent offline edits converge, deleting an item does not resurrect it',async()=>{
 const a=new Replica();await a.resolve(key,sticky);const b=new Replica(a.save());
 await a.resolve(key,{...sticky,start:480});await b.resolve('hours',{start:420,end:1320});await a.receive(b.events);await b.receive(a.events);
 assert.deepEqual(await a.values(),await b.values());assert.equal((await a.conflicts()).length,0);
 await a.resolve(key,undefined);await b.receive(a.events);assert.equal((await b.values())[key],undefined);await b.receive(a.events);assert.equal((await b.values())[key],undefined);
});
test('same-item edit/delete conflict is explicit and resolves on both clients',async()=>{
 const a=new Replica();await a.resolve(key,sticky);const b=new Replica(a.save());await a.resolve(key,undefined);await b.resolve(key,{...sticky,title:'変更'});await a.receive(b.events);assert.equal((await a.conflicts()).length,1);
 await a.resolve(key,undefined);await b.receive(a.events);assert.equal((await b.conflicts()).length,0);assert.equal((await b.values())[key],undefined);
});
test('unknown data cannot partially apply and cross-key references are rejected',async()=>{
 const a=new Replica();await a.resolve(key,sticky);const before=canonical(a.save());
 await assert.rejects(a.receive([{key:'hours',parents:[],value:encodeValue({start:1,end:1440})}]));assert.equal(canonical(a.save()),before);
 await assert.rejects(a.receive([{key:'colors',parents:[await mutationID(a.events[0])],value:encodeValue(palette)}]));assert.equal(canonical(a.save()),before);
});
test('daily ledger uses maximum count while preserving raw iOS value bytes',async()=>{
 const a=new Replica();const bytes=btoa('{"'+id+'":1}');await a.receive([{key:'daily/2026-10-27',parents:[],value:bytes}]);assert.equal(a.events[0].value,bytes);
 const b=new Replica();await b.resolve('daily/2026-10-27',{[id]:2});await a.receive(b.events);assert.equal((await a.values())['daily/2026-10-27'][id],2);
});
test('failed upload preserves pending edits and retry acknowledges only sent snapshot',async()=>{
 const a=new Replica();await a.resolve(key,sticky);let fail=true,writes=0;
 const drive={fetchChanges:async()=>({events:[],files:[]}),append:async events=>{writes++;if(fail)throw Error('network');assert.equal(events.length,1);return 'new-file';}};
 await assert.rejects(synchronize(a,drive));assert.equal((await a.pending()).length,1);fail=false;await synchronize(a,drive);assert.equal((await a.pending()).length,0);assert.equal(writes,2);assert.ok(a.lastSync);
});
test('remote events are not unnecessarily uploaded again',async()=>{
 const remote=new Replica();await remote.resolve(key,sticky);const local=new Replica();await synchronize(local,{fetchChanges:async()=>({events:remote.events,files:['remote']}),append:async()=>{throw Error('must not upload');}});assert.equal((await local.pending()).length,0);
});
test('Drive paging/cache, multipart metadata and version validation',async()=>{
 const calls=[];const response=x=>new Response(JSON.stringify(x));
 const drive=new Drive('fake-token',async(url,options)=>{calls.push({url,options});if(url.includes('upload/')){assert.match(options.body, /appDataFolder/);assert.match(options.body, /sync-v1/);return response({id:'created'});}if(url.includes('alt=media'))return response({version:1,mutations:[]});if(url.includes('pageToken='))return response({files:[{id:'b',size:'12'}]});return response({files:[{id:'a',size:'12'}],nextPageToken:'next'});});
 const result=await drive.fetchChanges(new Set(['a']));assert.deepEqual(result.files,['a','b']);assert.equal(calls.filter(c=>c.url.includes('alt=media')).length,1);assert.match(calls[0].url,/spaces=appDataFolder/);await drive.append([]);
 const future=new Drive('fake',async url=>response(url.includes('alt=media')?{version:2,mutations:[]}:{files:[{id:'a',size:'12'}]}));await assert.rejects(future.fetchChanges(new Set()),/新しい同期形式/);
});
test('403 API disabled and permission errors differ from auth expiry and rate limits',async()=>{
 for(const [status,reason,expected]of [[403,'SERVICE_DISABLED',/Drive APIが無効/],[403,'insufficientPermissions',/アクセスを許可/],[401,'',/有効期限/],[403,'userRateLimitExceeded',/userRateLimitExceeded/]]){
  const drive=new Drive('fake',async()=>new Response(JSON.stringify({error:{details:[{reason}]}}),{status}));await assert.rejects(drive.fetchChanges(new Set()),expected);
 }
});
