local opened,busy,hovered,pressed=false,false,false,false
local function render()
  local w=tonumber(SKIN:GetVariable('SCREENAREAWIDTH')) or 2560
  local h=tonumber(SKIN:GetVariable('SCREENAREAHEIGHT')) or 1440
  local s=math.min(w/2560,h/1440)
  local state=busy and 'disabled' or pressed and 'pressed' or hovered and 'hover' or opened and 'active' or 'normal'
  local palette={normal={'17,35,45,215','212,247,241,110','222,249,244,255'},
    active={'32,64,65,245','177,237,220,170','220,255,242,255'},
    hover={'44,67,77,250','209,250,239,195','245,255,251,255'},
    pressed={'18,40,47,255','209,250,239,245','197,240,225,255'},
    disabled={'18,28,35,170','164,184,194,28','137,158,167,145'}}
  local p=palette[state]
  SKIN:Bang('!SetOption','ButtonBody','Shape',string.format('Rectangle 0,0,%.3f,%.3f,%.3f | Fill Color %s | StrokeWidth %.3f | Stroke Color %s',74*s,74*s,25*s,p[1],s,p[2]))
  SKIN:Bang('!SetOption','Controller','ImageTint',p[3])
  SKIN:Bang('!SetOption','ButtonHit','MouseActionCursor',busy and '0' or '1')
  SKIN:Bang('!UpdateMeter','ButtonBody');SKIN:Bang('!UpdateMeter','Controller');SKIN:Bang('!UpdateMeter','ButtonHit');SKIN:Bang('!Redraw')
end
function SetOpen(value) opened=tonumber(value)==1;if not opened then pressed=false end;render() end
function SetBusy(value) busy=tonumber(value)==1;pressed=false;render() end
function Control(event)
  if event=='over' then hovered=true
  elseif event=='leave' then hovered=false;pressed=false
  end
  render()
end
function ReleasePress() pressed=false;render() end
function Click()
  if busy then return end
  -- Mouse-down actions disable Rainmeter's native dragging. Use a short
  -- release pulse so the desktop controller keeps its drag-to-position gesture.
  pressed=true;render()
  SKIN:Bang('!CommandMeasure','ButtonFeedback','Stop 1')
  SKIN:Bang('!CommandMeasure','ButtonFeedback','Execute 1')
  Open()
end
function Place()
  render()
  local resources=SKIN:GetVariable('@')
  local f=io.open(resources..'State.ini','rb')
  local data=f and f:read('*a') or ''
  if f then f:close() end
  if not data:match('ButtonPositioned=1') then
    local w=tonumber(SKIN:GetVariable('SCREENAREAWIDTH')) or 2560
    local h=tonumber(SKIN:GetVariable('SCREENAREAHEIGHT')) or 1440
    local s=math.min(w/2560,h/1440)
    SKIN:Bang('!Move',w*.51-42*s,h*.265-42*s)
    SKIN:Bang('!WriteKeyValue','State','ButtonPositioned','1',resources..'State.ini')
  end
end
function Open()
  if busy then return end
  opened=true;render()
  local config=SKIN:GetVariable('ROOTCONFIG')..'\\Main'
  local x=tonumber(SKIN:GetVariable('CURRENTCONFIGX')) or 0
  local y=tonumber(SKIN:GetVariable('CURRENTCONFIGY')) or 0
  local w=tonumber(SKIN:GetVariable('CURRENTCONFIGWIDTH')) or 84
  local h=tonumber(SKIN:GetVariable('CURRENTCONFIGHEIGHT')) or 84
  SKIN:Bang('!ActivateConfig',config,'Main.ini')
  SKIN:Bang('!CommandMeasure','Hub',string.format('Open(%.3f,%.3f)',x+w/2,y+h/2),config)
end
