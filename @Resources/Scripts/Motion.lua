-- Optional motion state machine. No frame-time I/O, library writes or focus ownership.
local M={}
function M.new(api)
  local m={api=api,session=tostring(os.time())..tostring(math.floor(os.clock()*1000000)),seq=0,token=0,mix=0,goal=0,opened=false,started=false,failed=false}
  function m:settings(s) self.s=s or {} end
  function m:enabled() return self.s.HeroVideo~='0' and self.s.ReduceMotion~='1' end
  function m:cinematic() return self.s.HeroCinematic=='1' and self.s.ReduceMotion~='1' end
  function m:send(action)
    if not self.started and action~='open' then return false end
    self.seq=self.seq+1
    local g=self.game or {}
    local fields={Session=self.session,Sequence=self.seq,Token=self.token,Action=action,
      Opened=self.opened and 1 or 0,Video=g.preview or '',Start=g.previewStart or '',End=g.previewEnd or '',Audio=self.s.PreviewAudio=='1' and 1 or 0,
      Loop=self.s.PreviewLoop=='1' and 1 or 0,Cinematic=self:cinematic() and 1 or 0,
      IdleDelay=math.max(5000,math.min(60000,tonumber(self.s.CinematicDelay) or 10000)),Complete=self.seq}
    if not api.command(fields) then self.failed=true;return false end
    return true
  end
  function m:activity() if self.idle then self.idle=false;api.idle(false) end end
  function m:stop(hard)
    api.delay(false);self.armed=false;self.waiting=false
    self.token=self.token+1;self.goal=0
    if hard then
      self.mix=0;api.alpha(0);self:send('hide')
    else
      self:send('pause')
      if self.mix>0 then api.animate() else self:send('hide') end
    end
  end
  function m:open(hasMedia)
    self.opened=true;self.failed=false;self:activity()
    if self:cinematic() or self:enabled() and hasMedia then
      local first=not self.started
      if self:send('open') and first then self.started=true;api.start() end
    end
  end
  function m:close()
    self:stop(true);self.pointer=nil;self.opened=false;self:activity();self:send('close')
  end
  function m:shutdown() self:close();self:send('quit') end
  function m:focus(g)
    local id=g and g.id
    if self.id~=(id or '') then
      self:stop(true);self.id=id or '';self.used=false
    end
    self.game=g;self:arm()
  end
  function m:enter(id)
    self:activity()
    if self.pointer~=id then self:stop(true);self.used=false end
    self.pointer=id;self:arm()
  end
  function m:leave()
    self.pointer=nil;self.used=false;self:activity();self:stop(false)
  end
  function m:cancel() self.pointer=nil;self.used=false;self:activity();self:stop(true) end
  function m:arm()
    if self.opened and not self.failed and self:enabled() and not self.armed and not self.used
      and self.pointer==self.id and self.game and self.game.preview~='' and api.eligible() then
      self.armed=true
      api.delay(true,math.max(500,math.min(5000,tonumber(self.s.PreviewDelay) or 900)))
    end
  end
  function m:commit()
    if not self.armed then return end
    self.armed=false;api.delay(false)
    if not self.opened or self.failed or not self:enabled() or self.pointer~=self.id or not api.eligible() then return end
    self.used=true;self.waiting=true;self.token=self.token+1
    if not self.started then self:open(true) end
    if not self:send('play') then self.waiting=false end
  end
  function m:event(session,token,event)
    if session~=self.session then return end
    if tonumber(token)~=self.token then return end
    if event=='idle' or event=='activity' then
      if self.opened and self:cinematic() then self.idle=event=='idle';api.idle(self.idle) end
      return
    end
    if event=='playing' then
      if not self.waiting or self.pointer~=self.id or not self.opened or not self:enabled() or not api.eligible() then self:stop(true);return end
      self.waiting=false;self.goal=1;api.animate()
    elseif event=='ended' then
      self.waiting=false;self.goal=0;api.animate()
    elseif event=='failed' then
      self.waiting=false;self:stop(true)
    end
  end
  function m:finished()
    self.started=false;self.failed=true;self:stop(true);self:activity()
  end
  function m:tick()
    if self.mix==self.goal then return false end
    self.mix=math.max(0,math.min(1,self.mix+(self.goal==1 and 1 or -1)*16/180))
    api.alpha(self.mix)
    if self.mix==0 then self:send('hide') end
    return self.mix~=self.goal
  end
  return m
end
-- Managed logo caches are decoded/re-encoded by Manager. Validate PNG framing on load.
function M.pngSize(path)
  local f=io.open(path,'rb');if not f then return end
  local h=f:read(33);local n=f:seek('end') or 0
  if not h or #h<33 or h:sub(1,8)~='\137PNG\13\10\26\10' or h:sub(13,16)~='IHDR' or n<45 then f:close();return end
  f:seek('end',-12);local tail=f:read(12);f:close()
  if tail~='\0\0\0\0IEND\174\66\96\130' then return end
  local function u32(i) local a,b,c,d=h:byte(i,i+3);return ((a*256+b)*256+c)*256+d end
  local w,y=u32(17),u32(21)
  if w>0 and y>0 and w<=8192 and y<=8192 then return w,y end
end
return M
