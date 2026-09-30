-- Lua 5.1. Run from the skin folder: lua Maintenance/Test-Motion.lua
local source=arg[1] or '@Resources/Scripts/Motion.lua'
local mod=dofile(source)
local function harness(settings)
 local h={commands={},writes=0,starts=0,frames=0,eligible=true,alphas={},idle=false}
 local api={}
 api.command=function(data)
  h.writes=h.writes+1;h.commands[#h.commands+1]=data
  return h.writeOK~=false
 end
 api.start=function()h.starts=h.starts+1 end
 api.delay=function(enabled,ms)h.armed=enabled;h.delay=ms end
 api.eligible=function()return h.eligible end
 api.alpha=function(a)h.alphas[#h.alphas+1]=a end
 api.animate=function()h.frames=h.frames+1 end
 api.idle=function(value)h.idle=value end
 h.m=mod.new(api);h.m:settings(settings or {})
 function h:event(name,token)self.m:event(self.m.session,tostring(token or self.m.token),name)end
 function h:tick()
  local n=0;local writes=self.writes
  while self.m.mix~=self.m.goal do self.m:tick();n=n+1;assert(n<20)end
  assert(self.writes-writes<=1,'Frame-time command writes')
 end
 function h:focus(g)self.m:focus(g);self.m:enter(g.id)end
 return h
end
local a={id='a',preview="Art/Previews/Tester's [clip] = test.mp4"}
local b={id='b',preview='C:\\Games\\Clips\\game two.mp4',logo='Art/Logos/b.png'}
local none={id='none',preview=''}
local h=harness();h.m:open(true);h:focus(a)
assert(h.armed and h.delay==900 and h.m.mix==0 and h.commands[#h.commands].Action~='play')
h.m:commit();assert(h.commands[#h.commands].Action=='play' and h.commands[#h.commands].Video==a.preview)
local token=h.m.token;h:event('playing');h:tick();assert(h.m.mix==1)
local writes=h.writes;h.m:focus(a);h.m:enter(a.id);h.m:commit();assert(h.writes==writes,'Same hover restarted preview')
h.m:leave();assert(not h.armed and h.commands[#h.commands].Action=='pause' and h.m.goal==0)
h:tick();assert(h.m.mix==0 and h.commands[#h.commands].Action=='hide')
h:event('playing',token);assert(h.m.goal==0,'Late ready callback won')
h:focus(a);h.m:commit();h:event('playing');h:tick();h:event('ended');h:tick();assert(h.m.mix==0)
writes=h.writes;h.m:enter(a.id);assert(h.writes==writes and not h.armed,'Ended preview restarted while stationary')
h:focus(b);h.m:commit();token=h.m.token;h.m:cancel();h:event('playing',token);assert(h.m.mix==0 and not h.armed)
-- Leaving during the delay prevents all playback; this is independent of fast card hover.
h:focus(a);assert(h.armed);h.m:leave();writes=h.writes;h.m:commit();assert(h.writes==writes)
-- Rapid sweeps, delayed out-of-order callbacks, view/manager/launch/close cancellation.
for i=1,120 do
 h:focus(i%2==0 and a or b);h.m:commit();token=h.m.token
 h:focus(i%2==0 and b or a);h:event('playing',token);assert(h.m.mix==0)
end
for _,action in ipairs({'cancel','close','shutdown'})do
 h.m:open(true);h:focus(a);h.m:commit();h:event('playing');h:tick();token=h.m.token
 h.m[action](h.m);h:event('playing',token);assert(h.m.mix==0 and not h.armed)
end
for _,settings in ipairs({{ReduceMotion='1'},{HeroVideo='0'},{ReduceMotion='1',HeroVideo='1',HeroCinematic='1'}})do
 local q=harness(settings);q.m:open(true);q:focus(a);q.m:commit();assert(q.starts==0 and not q.armed and q.m.mix==0)
end
for _,game in ipairs({none,{id='logo',preview='',logo='logo.png'}})do
 local q=harness();q.m:open(false);q:focus(game);q.m:commit();assert(q.starts==0 and not q.armed)
end
h=harness();h.m:open(true);h:focus(a);h.m:commit();h:event('failed');assert(h.m.mix==0 and not h.armed)
h.m:finished();assert(not h.m.started and h.m.failed and h.m.mix==0)
h.m:event('old-session',h.m.token,'playing');assert(h.m.mix==0)
h=harness();h.eligible=false;h.m:open(true);h:focus(a);assert(not h.armed)
h.eligible=true;h.m:arm();assert(h.armed);h.eligible=false;h.m:commit();assert(h.commands[#h.commands].Action~='play')
h=harness({HeroCinematic='1'});h.m:open(false);h:event('idle');assert(h.idle);h:event('activity');assert(not h.idle)
h:event('idle');h.m:close();h:event('idle');assert(not h.idle)
h=harness();h.writeOK=false;h.m:open(true);h:focus(a);assert(h.m.failed and h.starts==0 and not h.armed)
print('PASS: 900ms eligibility, local filenames, static-first fade, same-focus reuse, 120 rapid sweeps, stale callbacks, immediate cancellation, end/failure fallback, ReduceMotion/off, logo-only/empty and idle restoration')
