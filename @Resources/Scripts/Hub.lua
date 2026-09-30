-- GameHUB 3 (Liquid Glass). Release information: @Resources/Release.ini.
-- Original GameHUB concept: FinchNelson.
-- No per-frame file writes, skin reloads, input polling, or network requests.
local B, root, resources, settings, state, library, games, slots, meters
local release
local motion,motionLib
local W,H,S,margin,gap,cardW,cardH,imageH,panelY,panelH,visible,columns,rows
local view,sortMode,filterMode,selected,pending,offset,target,pageStart
local shown,ready,running,progress,goal,originX,originY,slide,fade,fadePath,backgroundPath
local favorites,history,activeSlots,openRequested
local managerBusy,managerToken,managerChecks,managerHid,managerSerial,hoverSlot,hoverLeaveSlot
-- selected is the committed focus. hoverSlot is immediate pointer feedback only.
local controls,hotControl,pressedControl,pressedGame,navigating,launchErrors,slotTints
local spotlight,refreshHomeHeaders
-- Home shares the 24 existing slots: eight reserved for each local-data shelf.
local homeShelves,homeFocusShelf,homePointerShelf,homeSlideShelf,launchCounts
local discovery
local discover={}
local drawDiscovery,drawPicker,restoreBrowse
local MAX_PICKER=8
local MAX_QUERY=128
local MAX_SLOTS=24
local DEFAULT_ACCENT='209,250,239'
local focusAccent=DEFAULT_ACCENT
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function trim(x) return (tostring(x or ''):gsub('^%s+',''):gsub('%s+$','')) end
local function readAccent(value)
  local r,g,b=tostring(value or ''):match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$')
  r,g,b=tonumber(r),tonumber(g),tonumber(b)
  if not r or r>255 or g>255 or b>255 then return DEFAULT_ACCENT end
  local hi,lo=math.max(r,g,b),math.min(r,g,b)
  if hi<75 or lo>240 or hi-lo<10 or hi-lo>230 then return DEFAULT_ACCENT end
  return string.format('%d,%d,%d',r,g,b)
end
local function accentMix(accent,r,g,b,amount,alpha)
  local ar,ag,ab=accent:match('(%d+),(%d+),(%d+)')
  return string.format('%d,%d,%d,%d',r+(ar-r)*amount+.5,g+(ag-g)*amount+.5,b+(ab-b)*amount+.5,alpha)
end
local function opt(m,k,v) B('!SetOption',m,k,tostring(v)) end
local function update(m) B('!UpdateMeter',m) end
local function paint() B('!Redraw') end
local function exists(path) local f=io.open(path,'rb'); if f then f:close(); return true end; return false end
local function completeImage(path)
  local f=io.open(path,'rb');if not f then return false end
  local ok=true
  if path:lower():match('%.png$') then
    local length=f:seek('end') or 0
    if length<12 then ok=false else f:seek('end',-12);ok=f:read(12)=='\0\0\0\0IEND\174\66\96\130' end
  end
  f:close();return ok
end
local function readIni(path)
  local result,section={},nil
  local f=io.open(path,'rb'); if not f then return result end
  local contents=f:read('*a');f:close();contents=contents:gsub('^\239\187\191','')
  for line in (contents..'\n'):gmatch('(.-)\n') do
    line=line:gsub('\r$','')
    local head=line:match('^%s*%[([^%]]+)%]%s*$')
    if head then section={};result[head]=section
    elseif section and not line:match('^%s*[;#]') then
      local k,v=line:match('^%s*([^=]+)=(.*)$')
      if k then section[trim(k)]=v end
    end
  end
  return result
end
local function writeState(section,key,value)
  B('!WriteKeyValue',section,key,tostring(value),resources..'State.ini')
end
local function asset(path,fallback)
  if path and path~='' then
    local p=resources..path:gsub('/','\\')
    if completeImage(p) then return p end
    -- Repair only an incomplete original cache. A user's replacement art wins.
    local repair=path:match('^Art/Covers/(game%d+%.png)$')
    if repair then
      p=resources..'Art\\Repairs\\'..repair
      if completeImage(p) then return p end
    end
  end
  return resources..(fallback or 'UI\\Placeholder.png')
end
local function findGame(id)
  for _,g in ipairs(library) do if g.id==id then return g end end
end
local function findIndex(id)
  for i,g in ipairs(games) do if g.id==id then return i end end
  return 1
end
local function meter(name)
  if not meters[name] then meters[name]=SKIN:GetMeter(name) end
  return meters[name]
end
local function move(name,x,y)
  local m=meter(name);if m then m:SetX(x);m:SetY(y) end
end
local function rect(name,x,y,w,h,r,fill,stroke)
  move(name,x,y)
  opt(name,'Shape',string.format('Rectangle 0,0,%.3f,%.3f,%.3f | Fill Color %s | StrokeWidth 1 | Stroke Color %s',w,h,r,fill,stroke or '235,250,255,45'))
end
local function textBox(name,x,y,w,h,size,text,color)
  move(name,x,y);opt(name,'W',w);opt(name,'H',h);opt(name,'FontSize',size)
  if text~=nil then opt(name,'Text',text) end
  if color then opt(name,'FontColor',color) end
end
local function shelfForSlot(slot) return math.floor((slot-1)/8)+1 end
local function slotMetrics(slot)
  local shelf=view=='home' and homeShelves[shelfForSlot(slot)]
  if shelf then return shelf.cardW,shelf.cardH,shelf.imageH end
  return cardW,cardH,imageH
end
local function focusedSlot(slot,id)
  return id==selected and (view~='home' or shelfForSlot(slot)==homeFocusShelf)
end
local function historyTime(id)
  local value=tonumber(history[id])
  if not value or value~=value or value<=0 or value>os.time() or value~=math.floor(value) then return nil end
  local ok,date=pcall(os.date,'*t',value)
  if ok and date then return value end
end
local function countFor(id)
  local value=tonumber(launchCounts[id])
  if value and value==value and value>=0 and value<=2147483647 and value==math.floor(value) then return value end
end
local function calendarDay(t)
  -- Local calendar days, rather than elapsed 24-hour periods (including DST).
  local y=t.year-(t.month<=2 and 1 or 0)
  local era=math.floor(y/400);local year=y-era*400
  local month=t.month+(t.month>2 and -3 or 9)
  return era*146097+year*365+math.floor(year/4)-math.floor(year/100)+math.floor((153*month+2)/5)+t.day-1
end
local function launchAge(id)
  local stamp=historyTime(id)
  if not stamp then return 'No GameHUB launch recorded' end
  local days=math.max(0,calendarDay(os.date('*t'))-calendarDay(os.date('*t',stamp)))
  return days==0 and 'Last launched today' or days==1 and 'Last launched yesterday' or 'Last launched '..days..' days ago'
end
local function homeMetadata(g)
  local count=countFor(g.id)
  return g.platform..'   /   '..launchAge(g.id)..(count and count>0 and
    '   /   '..count..(count==2147483647 and '+' or '')..(count==1 and ' GameHUB launch' or ' GameHUB launches') or '')
end
local function homeMaxStart(shelf)
  return math.max(0,math.floor((#shelf.games-1)/(shelf.columns or 6))*(shelf.columns or 6))
end
local function homeIndex(shelf,id)
  for i,g in ipairs(shelf.games) do if g.id==id then return i end end
end
local function rebuildHome()
  for i=1,3 do
    homeShelves[i]=homeShelves[i] or {start=0}
    homeShelves[i].games={}
  end
  for _,g in ipairs(games) do
    if historyTime(g.id) then table.insert(homeShelves[1].games,g) end
    if favorites[g.id]=='1' then table.insert(homeShelves[2].games,g) end
    table.insert(homeShelves[3].games,g)
  end
  table.sort(homeShelves[1].games,function(a,b)
    local at,bt=tonumber(history[a.id]),tonumber(history[b.id])
    if at~=bt then return at>bt end
    if a.order~=b.order then return a.order<b.order end
    return a.id<b.id
  end)
  for _,shelf in ipairs(homeShelves) do shelf.start=clamp(shelf.start,0,homeMaxStart(shelf)) end
end
local function tint(slot,active)
  local cardW,cardH=slotMetrics(slot)
  local game=active and findGame(slots[slot])
  local accent=game and game.accent or DEFAULT_ACCENT
  local key=tostring(cardW)..':'..tostring(cardH)..':'..tostring(S)..':'..tostring(active)..':'..accent
  if slotTints[slot]==key then return false end
  slotTints[slot]=key
  local fill=active and '38,57,65,245' or '13,24,32,235'
  local stroke=active and accent..',230' or '232,250,255,48'
  opt('Card'..slot,'Shape',string.format('Rectangle 0,0,%.3f,%.3f,%.3f | Fill Color %s | StrokeWidth %.2f | Stroke Color %s',cardW,cardH,14*S,fill,active and 2*S or S,stroke))
  return true
end
local function hasDiscovery() return discover.query~='' or filterMode~='all' or discover.tagFilter~='' end
local function discoveryBusy() return discover.searchEditing or discover.pickerMode~=nil end
local function matches(g)
  return (filterMode=='all' or filterMode=='favorites' and favorites[g.id]=='1' or filterMode==g.store)
    and (discover.tagFilter=='' or g.tagKeys[discover.tagFilter])
    and (discover.queryKey=='' or g.searchKey:find(discover.queryKey,1,true)~=nil)
end
local function indexDiscovery()
  local labels={};discover.platformCounts={}
  for _,g in ipairs(library) do
    g.tags=discovery.tags(g.tags);g.tagKeys={};g.store=discovery.platform(g)
    discover.platformCounts[g.store]=(discover.platformCounts[g.store] or 0)+1
    local parts={g.name}
    for _,tag in ipairs(g.tags) do
      g.tagKeys[tag.key]=true;parts[#parts+1]=tag.label
      if not labels[tag.key] or tag.label<labels[tag.key] then labels[tag.key]=tag.label end
    end
    g.searchKey=discovery.fold(table.concat(parts,'  '))
  end
  discover.tagChoices={}
  for key,label in pairs(labels) do discover.tagChoices[#discover.tagChoices+1]={key=key,label=label} end
  table.sort(discover.tagChoices,function(a,b) return a.key<b.key end)
  if discover.tagFilter~='' and not labels[discover.tagFilter] then discover.tagFilter='' end
end
local function rebuildOrder()
  games={}
  for _,g in ipairs(library) do
    if matches(g) then games[#games+1]=g end
  end
  table.sort(games,function(a,b)
    if view~='home' and sortMode=='az' then
      local an,bn=a.name:lower(),b.name:lower();if an~=bn then return an<bn end
    elseif view~='home' and sortMode=='recent' then
      local at,bt=tonumber(history[a.id]) or 0,tonumber(history[b.id]) or 0
      if at~=bt then return at>bt end
    end
    if a.order~=b.order then return a.order<b.order end
    return a.id<b.id
  end)
  if view=='home' then rebuildHome() end
end
local function loadData()
  local ini=readIni(resources..'Library.ini');library={}
  launchErrors={}
  state=readIni(resources..'State.ini');favorites=state.Favorites or {};history=state.History or {};launchCounts=state.LaunchCounts or {}
  local saved=state.State or {}
  view=saved.View or 'home';if view~='home' and view~='carousel' and view~='grid' and view~='list' then view='home' end
  sortMode=saved.Sort or 'custom';filterMode=saved.Filter or 'all'
  if not ({all=true,favorites=true,steam=true,['local']=true,epic=true,other=true})[filterMode] then filterMode='all' end
  for section,entry in pairs(ini) do
    local id=section:match('^Game:([%w_-]+)$')
    if id and entry.Name and entry.Target then
      library[#library+1]={id=id,name=entry.Name,platform=entry.Platform or 'Local',target=entry.Target,tags=entry.Tags or '',
        launch=entry.Launch or entry.Target,order=tonumber(entry.Order) or 9999,
        cover=asset(entry.Cover),background=asset(entry.Background,'UI\\Backdrop.jpg'),
        blur=asset(entry.Blur,'UI\\Blur.jpg'),accent=readAccent(entry.Accent),
        preview=entry.PreviewVideo or '',previewStart=entry.PreviewStart or '',previewEnd=entry.PreviewEnd or '',logo=entry.Logo or ''}
    end
  end
  indexDiscovery()
  selected=saved.LastId or selected
  rebuildOrder()
  if not findGame(selected) or not matches(findGame(selected)) then
    selected=games[1] and games[1].id
  end
  offset=findIndex(selected)-1;target=offset;pageStart=0
end
local function run()
  if running then return end
  running=true;B('!CommandMeasure','Animator','Execute 1')
end
local function stop()
  B('!CommandMeasure','Animator','Stop 1');running=false
end
-- The optional helper only reads complete event snapshots, never per-frame writes.
local function motionCommand(fields)
  local path=resources..'Motion-command.ini';local temp=path..'.tmp'
  local f=io.open(temp,'wb');if not f then return false end
  local lines={'[Motion]'}
  for key,value in pairs(fields) do
    value=tostring(value)
    if value:find('[\r\n]') then f:close();os.remove(temp);return false end
    lines[#lines+1]=key..'='..value
  end
  local ok=f:write(table.concat(lines,'\r\n')..'\r\n');f:close()
  if not ok then os.remove(temp);return false end
  os.remove(path);return os.rename(temp,path) and true or false
end
local function motionAlpha(mix)
  opt('BackdropA','ImageAlpha',math.floor(255*(1-mix)+.5))
  opt('BackdropB','ImageAlpha',math.floor(255*(fade or 0)*(1-mix)+.5))
  update('BackdropA');update('BackdropB');paint()
end
local function motionIdle(idle)
  for _,name in ipairs({'IdleHeader','IdleShelf'}) do
    opt(name,'SolidColor',idle and '5,12,19,72' or '5,12,19,0');update(name)
  end
  paint()
end
local function motionOpen()
  if not motion then return end
  local has=false
  for _,g in ipairs(library) do if g.preview~='' then has=true;break end end
  motion:open(has)
end
local function showLogo(g)
  B('!ShowMeter','HeroTitle');B('!HideMeter','HeroLogo')
  local path=g and g.logo or ''
  if path=='' then return end
  if not path:match('^%a:[/\\]') then path=resources..path:gsub('/','\\') end
  local w,h=motionLib.pngSize(path)
  if not w then return end
  -- An un-sized hidden Image meter reports zero when Rainmeter cannot decode it.
  -- Reuse Rainmeter's image cache and validate only on focus/resource changes.
  if not motion.logo or motion.logo.path~=path then
    opt('HeroLogoProbe','ImageName',path);update('HeroLogoProbe')
    local probe=meter('HeroLogoProbe')
    motion.logo={path=path,w=probe:GetW(),h=probe:GetH()}
  end
  if motion.logo.w<=0 or motion.logo.h<=0 then return end
  local boundW,boundH=560*S,view=='carousel' and 88*S or 72*S
  local ratio=math.min(boundW/w,boundH/h)
  move('HeroLogo',view=='carousel' and margin+14*S or margin+4*S,view=='carousel' and panelY-160*S or 140*S)
  opt('HeroLogo','ImageName',path);opt('HeroLogo','W',w*ratio);opt('HeroLogo','H',h*ratio)
  update('HeroLogo');B('!ShowMeter','HeroLogo');B('!HideMeter','HeroTitle')
end
local function maxPage()
  return math.max(0,math.ceil((#games-visible)/columns)*columns)
end
local function navigationEnabled(direction)
  if view=='home' or #games<2 then return false end
  if view=='carousel' then
    return #games>=5 or (direction<0 and target>0) or (direction>0 and target<#games-1)
  end
  return direction<0 and pageStart>0 or direction>0 and pageStart<maxPage()
end
local function renderControl(name)
  local c=controls[name];if not c then return end
  local state=c.disabled and 'disabled' or pressedControl==name and 'pressed' or hotControl==name and 'hover' or c.active and 'active' or 'normal'
  if c.style==state and c.accent==focusAccent then return end
  c.style=state;c.accent=focusAccent
  local palette={normal={'24,39,49,230','212,240,241,65','219,234,239,255'},
    active={'32,64,65,245','177,237,220,170','220,255,242,255'},
    hover={'44,67,77,250','209,250,239,195','245,255,251,255'},
    pressed={'18,40,47,255','209,250,239,245','197,240,225,255'},
    disabled={'18,28,35,170','164,184,194,28','137,158,167,145'}}
  local p=palette[state]
  -- Keep labels neutral and glass fills dark. Only engaged controls carry color.
  if focusAccent~=DEFAULT_ACCENT and (state=='active' or state=='pressed' or state=='hover') then
    local amount=state=='pressed' and .10 or state=='hover' and .13 or .16
    p={accentMix(focusAccent,18,31,40,amount,245),focusAccent..(state=='pressed' and ',235' or state=='hover' and ',190' or ',170'),p[3]}
  end
  rect(c.body,c.x,c.y,c.w,c.h,c.r,p[1],p[2]);update(c.body)
  if c.label then opt(c.label,'FontColor',p[3]);update(c.label) end
  if name=='Close' then
    opt(c.body,'Shape2',string.format('Line %.2f,%.2f,%.2f,%.2f | StrokeWidth %.2f | Stroke Color %s',18*S,16*S,34*S,32*S,2*S,p[3]))
    opt(c.body,'Shape3',string.format('Line %.2f,%.2f,%.2f,%.2f | StrokeWidth %.2f | Stroke Color %s',34*S,16*S,18*S,32*S,2*S,p[3]));update(c.body)
  end
  opt(c.hit,'MouseActionCursor',c.disabled and 0 or 1);update(c.hit)
end
local function placeControl(name,body,label,hit,x,y,w,h,r)
  controls[name]={body=body,label=label,hit=hit,x=x,y=y,w=w,h=h,r=r}
  move(hit,x,y);opt(hit,'W',w);opt(hit,'H',h)
end
local function refreshControls()
  for name,c in pairs(controls) do
    c.disabled=managerBusy or discover.searchEditing or (discover.pickerMode~=nil and not name:match('^Picker')) or false;c.active=false
    if name=='Close' then c.disabled=not shown or goal~=1
    elseif name=='Previous' or name=='Next' then c.disabled=c.disabled or not navigationEnabled(name=='Previous' and -1 or 1)
    elseif name:match('^Home[123]') then
      local index,direction=name:match('^Home([123])(%a+)$');local shelf=homeShelves[tonumber(index)]
      c.disabled=c.disabled or view~='home' or not shelf or (direction=='Previous' and shelf.start<=0 or direction=='Next' and shelf.start>=homeMaxStart(shelf))
    elseif name=='Filter' then c.disabled=c.disabled or #library==0;c.active=filterMode~='all'
    elseif name=='Search' then c.disabled=c.disabled or #library==0;c.active=discover.query~=''
    elseif name=='ClearSearch' then c.disabled=c.disabled or discover.query==''
    elseif name=='Tags' then c.disabled=c.disabled or #discover.tagChoices==0;c.active=discover.tagFilter~=''
    elseif name=='ResetDiscovery' then c.disabled=c.disabled or not hasDiscovery()
    elseif name:match('^Picker') then
      c.disabled=managerBusy or discover.pickerMode==nil
      local index=tonumber(name:match('^Picker(%d+)$'))
      if index then
        local item=discover.pickerItems[discover.pickerPage+index]
        c.disabled=c.disabled or not item;c.active=item and item.key==(discover.pickerMode=='filter' and filterMode or discover.tagFilter) or false
      elseif name=='PickerPrevious' then c.disabled=c.disabled or discover.pickerPage==0
      elseif name=='PickerNext' then c.disabled=c.disabled or discover.pickerPage+MAX_PICKER>=#discover.pickerItems end
    elseif name=='Sort' then c.disabled=c.disabled or view=='home' or #games<2;c.active=sortMode~='custom'
    elseif name:match('^View') then c.active=name:sub(5):lower()==view
    elseif name:match('^Hero') then c.disabled=c.disabled or not findGame(selected);c.active=name=='HeroPlay' or name=='HeroFavorite' and favorites[selected]=='1'
    end
    if c.disabled and pressedControl==name then pressedControl=nil;pressedGame=nil end
    renderControl(name)
  end
  opt('HeroFavorite','Text',selected and favorites[selected]=='1' and 'Unfavorite' or 'Favorite');update('HeroFavorite')
end
local function resetControls()
  hotControl=nil;pressedControl=nil;pressedGame=nil
  refreshControls()
end
local function buttonState(method,value)
  B('!CommandMeasure','ButtonScript',method..'('..tostring(value)..')',root..'\\Button')
end
function HideToast()
  B('!CommandMeasure','ToastTimer','Stop 1');B('!HideMeterGroup','Toast');paint()
end
local function toast(message)
  B('!CommandMeasure','ToastTimer','Stop 1')
  opt('ToastText','Text',message);B('!ShowMeterGroup','Toast');B('!UpdateMeterGroup','Toast');paint()
  B('!CommandMeasure','ToastTimer','Execute 1')
end
local function labelControls()
  local names={custom='Your order',az='A - Z',recent='Recently launched'}
  opt('SortText','Text','Sort: '..(names[sortMode] or 'Your order'))
  opt('FilterText','Text',({all='All games',favorites='Favorites',steam='Steam',['local']='Local',epic='Epic',other='Other'})[filterMode]..'  v')
  opt('Count','Text',tostring(#games)..' games')
  drawDiscovery()
  refreshControls()
  if view=='home' then refreshHomeHeaders() end
end

refreshHomeHeaders=function()
  if view~='home' then return end
  for i,shelf in ipairs(homeShelves) do
    local prefix='Home'..i;local count=#shelf.games
    opt(prefix..'Range','Text',count==0 and '0 games' or (shelf.start+1)..' - '..math.min(shelf.start+shelf.columns,count)..' of '..count)
    B(count==0 and '!ShowMeter' or '!HideMeter',prefix..'Empty')
    local empty={'Launch a game through GameHUB to start this shelf.','Middle-click a game or choose Favorite to save it here.','Open Manage games to add your first game.'}
    opt(prefix..'Empty','Text',hasDiscovery() and #library>0 and 'No matching games on this shelf. Try another search or clear filters.' or empty[i]);update(prefix..'Empty')
    if i==3 then opt(prefix..'Caption','Text',hasDiscovery() and 'Matches in your custom order' or 'Your custom library order');update(prefix..'Caption') end
    rect(prefix..'Mark',margin+24*S,shelf.headerY+7*S,3*S,22*S,1.5*S,
      i==homeFocusShelf and selected and focusAccent..',210' or '185,212,222,55','0,0,0,0')
    update(prefix..'Range');update(prefix..'Mark')
  end
end
local function homeGeometry()
  local width=W-2*margin-48*S
  local capacities={4,6,6}
  local function height(cols) return (width-(cols-1)*gap)/cols*9/16+58*S end
  -- Grow the number of columns only when needed to keep all shelves on screen.
  local available=H-panelY-12*S-3*42*S-2*16*S-44*S
  while height(capacities[1])+height(capacities[2])+height(capacities[3])>available do
    local best,saving=nil,0
    for i,cols in ipairs(capacities) do
      local delta=cols<8 and height(cols)-height(cols+1) or 0
      if delta>saving then best=i;saving=delta end
    end
    if not best then break end
    capacities[best]=capacities[best]+1
  end
  local used=height(capacities[1])+height(capacities[2])+height(capacities[3])
  local rowGap=clamp(16*S+(available-used)/2,16*S,34*S)
  local y=panelY+12*S
  local titles={'Continue Playing','Favorites','Your Games'}
  local captions={'Recent GameHUB launches','Saved for quick access','Your custom library order'}
  local empty={'Launch a game through GameHUB to start this shelf.','Middle-click a game or choose Favorite to save it here.','Open Manage games to add your first game.'}
  for i,shelf in ipairs(homeShelves) do
    local prefix='Home'..i;local cols=capacities[i]
    shelf.columns=cols;shelf.cardW=(width-(cols-1)*gap)/cols
    shelf.imageH=shelf.cardW*9/16;shelf.cardH=shelf.imageH+58*S
    shelf.headerY=y;shelf.cardY=y+42*S
    shelf.start=clamp(math.floor(shelf.start/cols)*cols,0,homeMaxStart(shelf))
    textBox(prefix..'Title',margin+38*S,y,250*S,34*S,17*S,titles[i])
    textBox(prefix..'Caption',margin+308*S,y+6*S,width-670*S,28*S,10*S,captions[i],'166,192,203,255')
    textBox(prefix..'Range',W-margin-344*S,y+6*S,210*S,28*S,10*S,nil,'188,208,219,255')
    textBox(prefix..'Empty',margin+38*S,shelf.cardY+28*S,width-36*S,50*S,13*S,empty[i],'186,207,218,255')
    move(prefix..'Hit',margin+24*S,y);opt(prefix..'Hit','W',width);opt(prefix..'Hit','H',42*S+shelf.cardH)
    for j,action in ipairs({'Previous','Next'}) do
      local name=prefix..action;local x=W-margin-(j==1 and 130 or 77)*S
      textBox(name,x+24*S,y+15*S,44*S,30*S,18*S,j==1 and '<' or '>');opt(name,'StringAlign','CenterCenter')
      placeControl(name,name..'Body',name,name..'Hit',x,y,48*S,30*S,10*S)
    end
    y=shelf.cardY+shelf.cardH+rowGap
  end
end

local function geometry()
  margin=64*S;gap=18*S
  local top=36*S
  textBox('Brand',margin,top,250*S,45*S,24*S,'GameHUB 3')
  local navX=W/2-224*S
  for i,v in ipairs({'Home','Carousel','Grid','List'}) do
    textBox('View'..v,navX+(i-.5)*112*S-3*S,top+24*S,106*S,48*S,14*S,v)
    opt('View'..v,'StringAlign','CenterCenter')
    placeControl('View'..v,'View'..v..'Body','View'..v,'View'..v..'Hit',navX+(i-1)*112*S,top,106*S,48*S,17*S)
  end
  rect('ManageBody',W-margin-282*S,top,212*S,48*S,17*S,'24,39,49,230')
  textBox('ManageText',W-margin-176*S,top+24*S,204*S,48*S,14*S,'+  Manage games')
  opt('ManageText','StringAlign','CenterCenter')
  placeControl('Manage','ManageBody','ManageText','ManageHit',W-margin-282*S,top,212*S,48*S,17*S)
  rect('CloseBody',W-margin-52*S,top,52*S,48*S,17*S,'24,39,49,230')
  opt('CloseBody','Shape2',string.format('Line %.2f,%.2f,%.2f,%.2f | StrokeWidth %.2f | Stroke Color 230,245,247,255',18*S,16*S,34*S,32*S,2*S))
  opt('CloseBody','Shape3',string.format('Line %.2f,%.2f,%.2f,%.2f | StrokeWidth %.2f | Stroke Color 230,245,247,255',34*S,16*S,18*S,32*S,2*S))
  move('CloseHit',W-margin-52*S,top);opt('CloseHit','W',52*S);opt('CloseHit','H',48*S)
  placeControl('Close','CloseBody',nil,'CloseHit',W-margin-52*S,top,52*S,48*S,17*S)
  textBox('Notice',margin,84*S,W-2*margin,18*S,9*S,nil,'252,219,166,255')
  if view=='carousel' then
    cardW=(W-2*margin-48*S-3*gap)/4.15;imageH=cardW*9/16;cardH=imageH+58*S
    panelH=cardH+112*S;panelY=H-margin-panelH;visible=7;columns=1;rows=1
    textBox('HeroTitle',margin+14*S,panelY-160*S,W*.77,88*S,43*S,nil)
    textBox('HeroPlatform',margin+18*S,panelY-207*S,W*.65,40*S,12*S,nil,'217,235,239,255')
  elseif view=='home' then
    panelY=270*S;visible=MAX_SLOTS;columns=1;rows=3
    homeGeometry()
    textBox('HeroTitle',margin+4*S,140*S,W-2*margin-470*S,72*S,32*S,nil)
    textBox('HeroPlatform',margin+6*S,216*S,W-2*margin-470*S,30*S,11*S,nil,'217,235,239,255')
  elseif view=='grid' then
    columns=6;cardW=(W-2*margin-48*S-(columns-1)*gap)/columns
    imageH=cardW*9/16;cardH=imageH+58*S
    panelY=270*S;panelH=H-panelY-margin
    rows=math.max(1,math.min(4,math.floor((panelH-110*S+gap)/(cardH+gap))))
    visible=math.min(MAX_SLOTS,columns*rows)
    textBox('HeroTitle',margin+4*S,140*S,W-2*margin-470*S,72*S,32*S,nil)
    textBox('HeroPlatform',margin+6*S,216*S,W-2*margin-470*S,30*S,11*S,nil,'217,235,239,255')
  else
    columns=2;cardW=(W-2*margin-48*S-gap)/columns;imageH=78*S;cardH=98*S
    panelY=270*S;panelH=H-panelY-margin
    rows=math.max(1,math.min(12,math.floor((panelH-110*S+gap)/(cardH+gap))))
    visible=math.min(MAX_SLOTS,columns*rows)
    textBox('HeroTitle',margin+4*S,140*S,W-2*margin-470*S,72*S,32*S,nil)
    textBox('HeroPlatform',margin+6*S,216*S,W-2*margin-470*S,30*S,11*S,nil,'217,235,239,255')
  end
  local actionX=view=='carousel' and margin+14*S or W-margin-432*S
  local actionY=view=='carousel' and panelY-58*S or 174*S
  for i,name in ipairs({'HeroPlay','HeroFavorite','HeroEdit'}) do
    local width=i==2 and 164*S or 120*S
    local x=actionX+(i==1 and 0 or i==2 and 132*S or 308*S)
    textBox(name,x+width/2,actionY+22*S,width-8*S,44*S,13*S,i==1 and 'Play' or i==2 and 'Favorite' or 'Edit')
    opt(name,'StringAlign','CenterCenter')
    placeControl(name,name..'Body',name,name..'Hit',x,actionY,width,44*S,14*S)
  end
  -- Local, feathered support for the Hero text. Global background dim is unchanged.
  local scrimY=view=='carousel' and panelY-314*S or 26*S
  local scrimH=view=='carousel' and 430*S or 360*S
  move('HeroScrim',0,scrimY)
  opt('HeroScrim','Shape',string.format('Rectangle 0,0,%.3f,%.3f | Fill RadialGradient HeroShade | StrokeWidth 0',W,scrimH))
  opt('HeroScrim','HeroShade',string.format('%.3f,0,0,0,%.3f,%.3f | 5,12,19,195 ; 0 | 5,12,19,185 ; 0.58 | 5,12,19,72 ; 0.82 | 5,12,19,0 ; 1',-.12*W,.64*W,scrimH/2))
  rect('ToastBody',W/2-360*S,H-100*S,720*S,52*S,16*S,'24,43,52,250','196,242,226,140')
  textBox('ToastText',W/2,H-74*S,680*S,48*S,12*S,nil,'233,251,242,255');opt('ToastText','StringAlign','CenterCenter')
  -- One container for the complete scene: no nested masks or window-wide live blur.
  panelH=H-panelY
  move('PanelFrostImage',0,panelY);opt('PanelFrostImage','W',W);opt('PanelFrostImage','H',panelH)
  opt('PanelFrostImage','ImageCrop',string.format('0,%.0f,1280,%.0f',panelY/H*720,panelH/H*720))
  rect('Panel',0,panelY,W,panelH,0,'13,24,33,190','214,246,255,55')
  rect('PanelShine',margin+24*S,panelY+S,W-2*margin-48*S,S,0,'232,250,255,105','232,250,255,0')
  textBox('Count',margin+24*S,panelY+22*S,210*S,34*S,14*S,nil)
  textBox('FilterText',W-margin-555*S,panelY+22*S,160*S,34*S,12*S,nil)
  textBox('SortText',W-margin-385*S,panelY+22*S,240*S,34*S,12*S,nil)
  textBox('Previous',W-margin-128*S,panelY+13*S,44*S,43*S,25*S,'<')
  textBox('Next',W-margin-67*S,panelY+13*S,44*S,43*S,25*S,'>')
  placeControl('Filter','FilterBody','FilterText','FilterHit',W-margin-565*S,panelY+15*S,160*S,40*S,12*S)
  placeControl('Sort','SortBody','SortText','SortHit',W-margin-397*S,panelY+15*S,252*S,40*S,12*S)
  placeControl('Previous','PreviousBody','Previous','PreviousHit',W-margin-130*S,panelY+13*S,48*S,43*S,12*S)
  placeControl('Next','NextBody','Next','NextHit',W-margin-69*S,panelY+13*S,48*S,43*S,12*S)
  textBox('FilterText',W-margin-485*S,panelY+35*S,152*S,40*S,12*S,nil);opt('FilterText','StringAlign','CenterCenter')
  textBox('SortText',W-margin-271*S,panelY+35*S,244*S,40*S,12*S,nil);opt('SortText','StringAlign','CenterCenter')
  textBox('Previous',W-margin-106*S,panelY+34.5*S,44*S,43*S,25*S,'<');opt('Previous','StringAlign','CenterCenter')
  textBox('Next',W-margin-45*S,panelY+34.5*S,44*S,43*S,25*S,'>');opt('Next','StringAlign','CenterCenter')
  textBox('Footer',margin+24*S,panelY+panelH-34*S,W-2*margin-48*S,27*S,10*S,
    'Scroll to browse   /   Click to launch   /   Right-click a game to edit   /   Middle-click to favorite','178,200,212,255')
  B(view=='home' and '!ShowMeterGroup' or '!HideMeterGroup','Home')
  B(view=='home' and '!HideMeterGroup' or '!ShowMeterGroup','BrowseControls')
  if view=='home' then opt('Footer','Text','Scroll over a shelf to browse   /   Click to launch   /   Right-click to edit   /   Middle-click to favorite   /   GameHUB activity only; counts since tracking began') end
  -- Discovery occupies one header row without moving Home's shelves or Hero.
  local x,y=margin,104*S
  placeControl('Search','SearchBody','SearchText','SearchHit',x,y,660*S,32*S,10*S)
  textBox('SearchText',x+16*S,y+5*S,594*S,26*S,11*S,nil,'204,222,231,255')
  placeControl('ClearSearch','ClearSearchBody','ClearSearchText','ClearSearchHit',x+618*S,y,42*S,32*S,9*S)
  textBox('ClearSearchText',x+639*S,y+16*S,38*S,32*S,12*S,'x');opt('ClearSearchText','StringAlign','CenterCenter')
  for i,name in ipairs({'Filter','Tags','ResetDiscovery'}) do
    local left=x+({676,864,1132})[i]*S;local width=({176,256,128})[i]*S
    local label=name..'Text'
    placeControl(name,name..'Body',label,name..'Hit',left,y,width,32*S,10*S)
    textBox(label,left+width/2,y+16*S,width-14*S,32*S,11*S,name=='ResetDiscovery' and 'Clear filters' or nil);opt(label,'StringAlign','CenterCenter')
  end
  textBox('DiscoveryCount',x+1280*S,y+6*S,W-2*margin-1280*S,25*S,10*S,nil,'174,198,210,255')
  for _,part in ipairs({'Body','Text','Hit'}) do B('!ShowMeter','Filter'..part) end
  opt('SearchInput','X',x+12*S);opt('SearchInput','Y',y+2*S);opt('SearchInput','W',600*S);opt('SearchInput','H',30*S);opt('SearchInput','FontSize',11*S)
  for i=1,MAX_SLOTS do
    local cardW,cardH,imageH=slotMetrics(i)
    tint(i,false)
    opt('Cover'..i,'W',view=='list' and imageH*16/9 or cardW)
    opt('Cover'..i,'H',imageH)
    textBox('Name'..i,0,0,view=='list' and cardW-imageH*16/9-45*S or cardW-22*S,30*S,13*S,nil)
    textBox('Meta'..i,0,0,view=='list' and cardW-imageH*16/9-45*S or cardW-22*S,23*S,9*S,nil,'177,203,214,255')
    opt('Hit'..i,'W',cardW);opt('Hit'..i,'H',cardH)
    slots[i]=nil
  end
  move('HeroMotionHit',0,138*S);opt('HeroMotionHit','W',W);opt('HeroMotionHit','H',math.max(0,panelY-138*S))
  move('IdleHeader',0,0);opt('IdleHeader','W',W);opt('IdleHeader','H',138*S)
  move('IdleShelf',0,panelY);opt('IdleShelf','W',W);opt('IdleShelf','H',H-panelY)
  labelControls()
end
local function bindSlot(i,g)
  if slots[i]==g.id then return end
  slots[i]=g.id
  opt('Cover'..i,'ImageName',g.cover)
  opt('Name'..i,'Text',g.name)
  opt('Meta'..i,'Text',view=='home' and shelfForSlot(i)==1 and launchAge(g.id) or (favorites[g.id]=='1' and '*  ' or '')..g.platform)
  opt('Hit'..i,'ToolTipText','')
  tint(i,focusedSlot(i,g.id))
  B('!ShowMeterGroup','Slot'..i);activeSlots[i]=true;B('!UpdateMeterGroup','Slot'..i)
end
local function positionSlot(i,x,y)
  local _,_,imageH=slotMetrics(i)
  move('Card'..i,x,y);move('Hit'..i,x,y)
  if view=='list' then
    move('Cover'..i,x+10*S,y+10*S)
    move('Name'..i,x+imageH*16/9+24*S,y+19*S)
    move('Meta'..i,x+imageH*16/9+24*S,y+55*S)
  else
    move('Cover'..i,x,y);move('Name'..i,x+12*S,y+imageH+6*S);move('Meta'..i,x+12*S,y+imageH+34*S)
  end
end
local function drawSlots()
  if #games==0 then
    for i=1,MAX_SLOTS do B('!HideMeterGroup','Slot'..i);slots[i]=nil;activeSlots[i]=false end
    spotlight(nil,true,true)
    return
  end
  local base=math.floor(offset);local fractional=offset-base
  for i=1,MAX_SLOTS do
    local g,x,y
    if i<=visible then
      if view=='home' then
        local row=shelfForSlot(i);local shelf=homeShelves[row];local column=(i-1)%8
        if column<shelf.columns then g=shelf.games[shelf.start+column+1] end
        x=margin+24*S+column*(shelf.cardW+gap)+(homeSlideShelf==row and slide or 0)
        y=shelf.cardY+(not homeSlideShelf and slide or 0)
      elseif view=='carousel' then
        g=games[((base+i-2)%#games)+1]
        x=margin+24*S+(i-2-fractional)*(cardW+gap)
        y=panelY+66*S+slide
        -- Avoid duplicated visible cards in small libraries.
        if #games<5 then
          if i<=#games then g=games[i];x=margin+24*S+(i-1-offset)*(cardW+gap) else g=nil end
        end
      else
        g=games[pageStart+i]
        x=margin+24*S+((i-1)%columns)*(cardW+gap)
        y=panelY+66*S+math.floor((i-1)/columns)*(cardH+gap)+slide
      end
    end
    if g then bindSlot(i,g);positionSlot(i,x,y)
    else if activeSlots[i] then B('!HideMeterGroup','Slot'..i);slots[i]=nil;activeSlots[i]=false end end
  end
end
spotlight=function(id,instant,deferPaint)
  local g=findGame(id)
  selected=g and id or nil
  if motion then motion:focus(g) end
  showLogo(g)
  if not g then
    g={name=hasDiscovery() and #library>0 and 'No matching games' or 'Add your first game',blur=resources..'UI\\Blur.jpg',background=resources..'UI\\Backdrop.jpg'}
    opt('HeroPlatform','Text',hasDiscovery() and #library>0 and 'Try another title or tag, or choose Clear filters' or 'Open Manage games to get started')
  else opt('HeroPlatform','Text',view=='home' and not launchErrors[id] and homeMetadata(g) or g.platform..'   /   '..(launchErrors[id] or 'Ready to launch')) end
  focusAccent=g.accent or DEFAULT_ACCENT
  rect('PanelShine',margin+24*S,panelY+S,W-2*margin-48*S,S,0,
    focusAccent==DEFAULT_ACCENT and '232,250,255,105' or accentMix(focusAccent,232,250,255,.65,105),'232,250,255,0')
  update('PanelShine')
  opt('HeroTitle','Text',g.name)
  opt('PanelFrostImage','ImageName',g.blur);update('PanelFrostImage')
  if instant or settings.ReduceMotion=='1' or (fadePath or backgroundPath)~=g.background then
    if instant or settings.ReduceMotion=='1' then
      opt('BackdropA','ImageName',g.background);opt('BackdropB','ImageAlpha',0)
      backgroundPath=g.background;fade=nil;fadePath=nil
    elseif fade and backgroundPath==g.background then
      -- Reverse the two existing layers without flashing the abandoned target.
      local previous=fadePath;fadePath=backgroundPath;backgroundPath=previous;fade=1-fade
      opt('BackdropA','ImageName',backgroundPath);opt('BackdropB','ImageName',fadePath)
      opt('BackdropB','ImageAlpha',math.floor(fade*255+.5));update('BackdropB');run()
    else
      if fadePath and fade>=.5 then opt('BackdropA','ImageName',fadePath);backgroundPath=fadePath;update('BackdropA') end
      fadePath=g.background;fade=0;opt('BackdropB','ImageName',fadePath);opt('BackdropB','ImageAlpha',0)
      update('BackdropB');run()
    end
  end
  for i,id2 in pairs(slots) do tint(i,focusedSlot(i,id2));update('Card'..i) end
  refreshControls()
  if view=='home' then refreshHomeHeaders() end
  update('HeroTitle');update('HeroPlatform');update('BackdropA');if not deferPaint then paint() end
end

local function alignFocus()
  if view=='home' then
    local row=homeFocusShelf or 3
    local index=homeIndex(homeShelves[row],selected)
    if not index then
      for i=1,3 do
        index=homeIndex(homeShelves[i],selected)
        if index then row=i;break end
      end
    end
    if not index then
      if #homeShelves[row].games==0 then row=3 end
      index=homeShelves[row].start+1
      selected=homeShelves[row].games[index] and homeShelves[row].games[index].id
    end
    local shelf=homeShelves[row]
    if index<=shelf.start or index>shelf.start+shelf.columns then shelf.start=math.floor((index-1)/shelf.columns)*shelf.columns end
    homeFocusShelf=row;homePointerShelf=row;homeSlideShelf=nil
    offset=0;target=0;slide=0;navigating=false;return
  end
  local index=findIndex(selected)
  if not games[index] or games[index].id~=selected then selected=games[1] and games[1].id;index=1 end
  offset=index-1;target=offset;slide=0;navigating=false
  pageStart=clamp(pageStart,0,maxPage())
  if index<=pageStart or index>pageStart+visible then pageStart=clamp(math.floor((index-1)/columns)*columns,0,maxPage()) end
end
local function syncNavigationFocus()
  if not navigating or view~='carousel' or #games==0 then return end
  local id=games[(math.floor(offset+.5)%#games)+1].id
  if selected~=id then spotlight(id,false,true) end
end

function Initialize()
  B=function(...) SKIN:Bang(...) end
  resources=SKIN:GetVariable('@');root=SKIN:GetVariable('ROOTCONFIG');meters={};slots={};activeSlots={}
  controls={};slotTints={};hotControl=nil;pressedControl=nil;pressedGame=nil;navigating=false
  discovery=dofile(resources..'Scripts/Discovery.lua')
  discover.query='';discover.queryKey='';discover.tagFilter='';discover.tagChoices={};discover.platformCounts={}
  discover.pickerMode=nil;discover.pickerItems={};discover.pickerPage=0;discover.searchEditing=false;discover.searchSerial=0;discover.searchBookmarks={}
  release=readIni(resources..'Release.ini').Release or {}
  settings=readIni(resources..'Settings.ini').Settings or {}
  W=tonumber(settings.Width) or 0;H=tonumber(settings.Height) or 0
  if W<=0 then W=tonumber(SKIN:GetVariable('SCREENAREAWIDTH')) or 2560 end
  if H<=0 then H=tonumber(SKIN:GetVariable('SCREENAREAHEIGHT')) or 1440 end
  S=math.min(W/2560,H/1440)*clamp(tonumber(settings.UIScale) or 1,.7,1.5)
  shown=false;ready=false;running=false;progress=0;goal=0;slide=0;offset=0;target=0;pageStart=0
  managerBusy=false;managerToken='';managerChecks=0;managerHid=false;managerSerial=0;hoverSlot=nil;hoverLeaveSlot=nil
  openRequested=nil;homeShelves={};homeFocusShelf=3;homePointerShelf=3;homeSlideShelf=nil
  originX=W*.51;originY=H*.265
  motionLib=dofile(resources..'Scripts/Motion.lua')
  motion=motionLib.new({command=motionCommand,start=function() B('!CommandMeasure','MotionRunner','Run') end,
    alpha=motionAlpha,idle=motionIdle,animate=run,
    eligible=function() return shown and goal==1 and progress==1 and not managerBusy and not navigating and not discoveryBusy() end,
    delay=function(enabled,ms)
      B('!CommandMeasure','MotionDelay','Stop 1')
      if enabled then opt('MotionDelay','ActionList1','Wait '..ms..' | Commit');B('!UpdateMeasure','MotionDelay');B('!CommandMeasure','MotionDelay','Execute 1') end
    end})
  motion:settings(settings)
  loadData()
end

function Boot()
  B('!Hide');B('!Draggable',0);B('!KeepOnScreen',0);B('!ZPos',2)
  B('!Move',tonumber(settings.X) or tonumber(SKIN:GetVariable('SCREENAREAX')) or 0,tonumber(settings.Y) or tonumber(SKIN:GetVariable('SCREENAREAY')) or 0)
  for _,m in ipairs({'BackdropA','BackdropB','Dim','Vignette'}) do opt(m,'W',W);opt(m,'H',H) end
  geometry();alignFocus();drawSlots();spotlight(selected,true);B('!HideMeter','Notice');HideToast()
  buttonState('SetOpen',0);buttonState('SetBusy',0)
  B('!UpdateMeter','*');ready=true
  if openRequested then local request=openRequested;openRequested=nil;Open(request[1],request[2]) end
end
function Open(x,y)
  if not ready then openRequested={x,y};return end
  if tonumber(x) then originX=clamp(tonumber(x)-(tonumber(settings.X) or 0),0,W) end
  if tonumber(y) then originY=clamp(tonumber(y)-(tonumber(settings.Y) or 0),0,H) end
  if shown and goal==1 then return end
  if not shown then
    if view=='home' or sortMode=='recent' then rebuildOrder() end
    alignFocus();slots={};drawSlots();spotlight(selected,true);B('!UpdateMeter','*')
  end
  shown=true;goal=1;homeSlideShelf=nil;slide=settings.ReduceMotion=='1' and 0 or 25*S
  resetControls();buttonState('SetOpen',1);motionOpen()
  if settings.ReduceMotion=='1' then
    progress=1;opt('SceneClip','Shape',string.format('Rectangle 0,0,%.3f,%.3f,0 | Fill Color 255,255,255,255 | StrokeWidth 0',W,H))
    drawSlots();B('!UpdateMeter','*');B('!ClickThrough',0);B('!Show');stop();paint();return
  end
  if progress==0 then
    opt('SceneClip','Shape',string.format('Rectangle %.3f,%.3f,%.3f,%.3f,%.3f | Fill Color 255,255,255,255 | StrokeWidth 0',originX-36*S,originY-36*S,72*S,72*S,24*S))
    update('SceneClip')
  end
  B('!ClickThrough',0);B('!Show');run()
end
function Close(immediate)
  SearchDismiss();HidePicker()
  if motion then motion:close() end
  if not shown then return end
  CancelHover();HideToast();syncNavigationFocus();navigating=false
  if view=='carousel' then target=math.floor(offset+.5) end
  goal=0;resetControls();buttonState('SetOpen',0)
  if selected then writeState('State','LastId',selected) end
  if immediate or settings.ReduceMotion=='1' then
    goal=0;progress=0;shown=false;stop();B('!Hide');return
  end
  goal=0;run()
end
function Tick()
  if not shown then stop();return end
  local dirty=false
  if progress~=goal then
    local duration=goal==1 and (tonumber(settings.OpenMs) or 260) or (tonumber(settings.CloseMs) or 190)
    if settings.ReduceMotion=='1' then duration=1 end
    progress=clamp(progress+(goal==1 and 1 or -1)*16/math.max(1,duration),0,1)
    local p=1-(1-progress)^3
    local sx=(originX-36*S)*(1-p);local sy=(originY-36*S)*(1-p)
    opt('SceneClip','Shape',string.format('Rectangle %.3f,%.3f,%.3f,%.3f,%.3f | Fill Color 255,255,255,255 | StrokeWidth 0',sx,sy,72*S+(W-72*S)*p,72*S+(H-72*S)*p,24*S*(1-p)))
    update('SceneClip');dirty=true
    if progress==0 and goal==0 then shown=false;stop();B('!Hide');return end
  end
  if math.abs(target-offset)>.001 or math.abs(slide)>.1 then
    offset=offset+(target-offset)*.24;slide=slide*.76
    if math.abs(target-offset)<.001 then offset=target end
    if math.abs(slide)<.1 then slide=0 end
    syncNavigationFocus();drawSlots();dirty=true
  end
  if fade then
    fade=math.min(1,fade+16/(tonumber(settings.FadeMs) or 190))
    if settings.ReduceMotion=='1' then fade=1 end
    opt('BackdropB','ImageAlpha',math.floor(fade*255+.5));update('BackdropB');dirty=true
    if fade>=1 then
      opt('BackdropA','ImageName',fadePath);update('BackdropA');backgroundPath=fadePath
      opt('BackdropB','ImageAlpha',0);update('BackdropB');fade=nil;fadePath=nil
    end
  end
  local motionBusy=motion and motion:tick()
  if motion and motion.mix>0 and dirty then motionAlpha(motion.mix) end
  if dirty then paint() end
  if progress==goal and offset==target and slide==0 and not fade and not motionBusy then
    if view=='carousel' and #games>0 then offset=offset%#games;target=offset end
    navigating=false;stop();if motion then motion:arm() end
  end
end
local function setHoverSlot(slot)
  slot=tonumber(slot);if not slot or not slots[slot] then return end
  hoverSlot=slot
  for i in pairs(slots) do if tint(i,i==slot) then update('Card'..i) end end
  paint()
end
function HomeShelfHover(index)
  index=tonumber(index)
  if view=='home' and shown and goal==1 and homeShelves[index] then homePointerShelf=index end
end
function Hover(slot)
  slot=tonumber(slot)
  if view=='home' and slot and slots[slot] then HomeShelfHover(shelfForSlot(slot)) end
  -- Moving cards can generate enter events underneath a stationary pointer.
  -- Navigation owns focus until its movement stops; no delayed hover may win.
  if not shown or goal~=1 or managerBusy or discoveryBusy() or navigating then return end
  slot=tonumber(slot);local id=slots[slot];if not id then return end
  -- A card-to-card move fires MouseLeave before the next MouseOver.  Do not let
  -- that tiny gap repaint the selected card and create a one-frame flash.
  hoverLeaveSlot=nil;B('!CommandMeasure','HoverLeaveTimer','Stop 1')
  setHoverSlot(slot)
  if motion then motion:enter(id) end
  pending=nil;B('!CommandMeasure','HoverTimer','Stop 1')
  if id==selected then
    if view=='home' then homeFocusShelf=shelfForSlot(slot);refreshHomeHeaders();paint() end
    return
  end
  pending=id;B('!CommandMeasure','HoverTimer','Execute 1')
end
function CommitHover()
  local id=pending;pending=nil
  if shown and goal==1 and not managerBusy and not discoveryBusy() and not navigating and id and hoverSlot and slots[hoverSlot]==id and findGame(id) then
    if view=='home' then homeFocusShelf=shelfForSlot(hoverSlot) end
    spotlight(id,false)
  end
end
local function restoreSelectedAfterHover()
  local old=hoverSlot;hoverSlot=nil;hoverLeaveSlot=nil
  for i,id in pairs(slots) do if tint(i,focusedSlot(i,id)) then update('Card'..i) end end
  if old then paint() end
end
function CommitHoverLeave()
  if not shown or goal~=1 or navigating then return end
  local slot=hoverLeaveSlot
  if not slot or hoverSlot~=slot then return end
  restoreSelectedAfterHover()
end
function CancelHover()
  if motion then motion:cancel() end
  pending=nil;B('!CommandMeasure','HoverTimer','Stop 1')
  hoverLeaveSlot=nil;B('!CommandMeasure','HoverLeaveTimer','Stop 1')
  restoreSelectedAfterHover()
end
function Leave(slot)
  slot=tonumber(slot)
  if hoverSlot~=slot then return end
  if motion then motion:leave() end
  pending=nil;B('!CommandMeasure','HoverTimer','Stop 1')
  hoverLeaveSlot=slot
  B('!CommandMeasure','HoverLeaveTimer','Stop 1')
  B('!CommandMeasure','HoverLeaveTimer','Execute 1')
end
function Scroll(direction,shelfIndex)
  if not shown or goal~=1 or managerBusy or discoveryBusy() or #games<2 then return end
  direction=(tonumber(direction) or 1)<0 and -1 or 1
  if view=='home' then
    local row=tonumber(shelfIndex) or homePointerShelf or homeFocusShelf or 3
    local shelf=homeShelves[row];if not shelf then return end
    local nextStart=clamp(shelf.start+direction*shelf.columns,0,homeMaxStart(shelf))
    if nextStart==shelf.start then return end
    CancelHover();shelf.start=nextStart;homeFocusShelf=row;homePointerShelf=row;homeSlideShelf=row
    local index=clamp(homeIndex(shelf,selected) or nextStart+1,nextStart+1,math.min(nextStart+shelf.columns,#shelf.games))
    slide=settings.ReduceMotion=='1' and 0 or 18*S*direction;navigating=slide~=0
    drawSlots();spotlight(shelf.games[index].id,false,true);B('!UpdateMeter','*');paint()
    if slide~=0 then run() end
    return
  end
  if not navigationEnabled(direction) then return end
  CancelHover()
  if view=='carousel' then
    local step=math.max(1,math.floor(tonumber(settings.WheelStep) or 1))
    target=math.floor(target+.5)+direction*step
    if #games<5 then target=clamp(target,0,#games-1) end
    navigating=true
    if settings.ReduceMotion=='1' then offset=target;syncNavigationFocus();navigating=false;drawSlots();B('!UpdateMeter','*');paint()
    else syncNavigationFocus();paint();run() end
  else
    local step=columns
    pageStart=clamp(pageStart+direction*step,0,maxPage())
    local index=clamp(findIndex(selected),pageStart+1,math.min(pageStart+visible,#games))
    slide=settings.ReduceMotion=='1' and 0 or 18*S*direction;navigating=slide~=0
    drawSlots();spotlight(games[index].id,false,true);B('!UpdateMeter','*');paint()
    if slide~=0 then run() end
  end
  refreshControls();paint()
end
function View(name)
  if not shown or goal~=1 or managerBusy or discoveryBusy() or name==view or (name~='home' and name~='carousel' and name~='grid' and name~='list') then return end
  CancelHover()
  if discover.query=='' then discover.searchBookmarks[view]=CaptureBrowse() end
  view=name;writeState('State','View',name);pageStart=0;rebuildOrder()
  geometry();alignFocus();drawSlots();spotlight(selected,false,true);resetControls();B('!UpdateMeter','*');paint()
end
function Sort()
  if view=='home' then return end
  if not shown or goal~=1 or managerBusy or discoveryBusy() or #games<2 then return end
  CancelHover()
  sortMode=sortMode=='custom' and 'az' or sortMode=='az' and 'recent' or 'custom'
  writeState('State','Sort',sortMode);rebuildOrder();alignFocus()
  slots={};drawSlots();spotlight(selected,false,true);labelControls();B('!UpdateMeter','*');paint()
end
function Filter() ShowPicker('filter') end
local function favoriteGame(id)
  if not shown or goal~=1 or managerBusy or discoveryBusy() then return end
  local g=findGame(id);if not g then return end
  CancelHover()
  local oldIndex=findIndex(selected)
  favorites[id]=favorites[id]=='1' and '0' or '1';writeState('Favorites',id,favorites[id])
  if view=='home' then rebuildOrder();alignFocus()
  elseif hasDiscovery() then
    rebuildOrder()
    if filterMode=='favorites' and selected==id and favorites[id]~='1' then selected=games[math.min(oldIndex,#games)] and games[math.min(oldIndex,#games)].id end
    alignFocus()
  end
  slots={};drawSlots();labelControls()
  spotlight(selected,false,true)
  B('!UpdateMeter','*');paint()
  toast((favorites[id]=='1' and 'Added to Favorites: ' or 'Removed from Favorites: ')..g.name)
end
function Favorite(slot) favoriteGame(slots[tonumber(slot)]) end
local function launchGame(id)
  if not shown or goal~=1 or managerBusy or discoveryBusy() then return end
  local g=findGame(id);if not g then return end
  CancelHover();navigating=false
  -- Freeze movement before the action so its focus cannot change mid-dispatch.
  target=offset;slide=0;spotlight(id,true)
  local launch=g.launch
  if launch:match('^Shortcuts[/\\]') then launch=resources..launch:gsub('/','\\') end
  -- A single quoted ShellExecute target. No shell, eval, or concatenated arguments.
  if launch=='' or launch:find('["\r\n]') then
    launchErrors[id]='Invalid launch target - choose Edit';spotlight(id,true)
    toast('Invalid launch target for '..g.name..'. Choose Edit to fix it.')
    B('!Log','GameHUB 3 (Liquid Glass): invalid launch target for '..g.name,'Error');return
  end
  if not launch:match('^[%a][%w+.-]*://') and not exists(launch) then
    launchErrors[id]='Shortcut not found - choose Edit';spotlight(id,true)
    toast('Shortcut not found for '..g.name..'. Choose Edit to update its path.');return
  end
  launchErrors[id]=nil;selected=id;history[id]=tostring(os.time());writeState('History',id,history[id])
  -- Count only validated launch requests dispatched here; never infer old counts.
  launchCounts[id]=tostring(math.min(2147483647,(countFor(id) or 0)+1))
  writeState('LaunchCounts',id,launchCounts[id])
  Close(true);B('["'..launch..'"]')
end
function Launch(slot)
  slot=tonumber(slot)
  if view=='home' and slot and slots[slot] then homeFocusShelf=shelfForSlot(slot) end
  launchGame(slots[slot])
end
function Hero(action)
  if not shown or goal~=1 or managerBusy or discoveryBusy() or not findGame(selected) then return end
  if action=='Play' then launchGame(selected)
  elseif action=='Favorite' then favoriteGame(selected)
  elseif action=='Edit' then Manager(nil,selected) end
end
function Control(name,event)
  local c=controls[name];if not c then return end
  if event=='leave' then
    if hotControl==name then hotControl=nil end
    if pressedControl==name then pressedControl=nil;pressedGame=nil end
  elseif event=='over' then
    local old=hotControl;hotControl=name
    if view=='home' and name:match('^Home[123]') then homePointerShelf=tonumber(name:sub(5,5)) end
    if old and old~=name then renderControl(old) end
    CancelHover()
  elseif event=='down' then
    if c.disabled or not shown or goal~=1 then return end
    local old=pressedControl;pressedControl=name;pressedGame=selected;hotControl=name
    local pick=tonumber(name:match('^Picker(%d+)$'))
    if pick then local item=discover.pickerItems[discover.pickerPage+pick];pressedGame=item and item.key end
    if old and old~=name then renderControl(old) end
  elseif event=='up' then
    local old=pressedControl
    local activate=pressedControl==name and not c.disabled and shown and goal==1
    if name:match('^Hero') and selected~=pressedGame then activate=false end
    local pick=tonumber(name:match('^Picker(%d+)$'))
    if pick then local item=discover.pickerItems[discover.pickerPage+pick];if not item or item.key~=pressedGame then activate=false end end
    pressedControl=nil;pressedGame=nil
    if old and old~=name then renderControl(old) end
    renderControl(name);paint()
    if not activate then return end
    if name:match('^View') then View(name:sub(5):lower())
    elseif name=='Manage' then Manager()
    elseif name=='Close' then Close()
    elseif name=='Search' then BeginSearch()
    elseif name=='ClearSearch' then SetSearch('')
    elseif name=='Tags' then ShowPicker('tags')
    elseif name=='ResetDiscovery' then ResetDiscovery()
    elseif name=='PickerPrevious' then PickerPage(-1)
    elseif name=='PickerNext' then PickerPage(1)
    elseif name:match('^Picker%d+$') then ChoosePicker(tonumber(name:sub(7)))
    elseif name=='Filter' then Filter()
    elseif name=='Sort' then Sort()
    elseif name:match('^Home[123]') then
      local row,action=name:match('^Home([123])(%a+)$');Scroll(action=='Previous' and -1 or 1,tonumber(row))
    elseif name=='Previous' then Scroll(-1)
    elseif name=='Next' then Scroll(1)
    elseif name:match('^Hero') then Hero(name:sub(5)) end
    return
  end
  renderControl(name);paint()
end
drawDiscovery=function()
  -- InputText's measure supplies the accepted string; it is never parsed as code.
  opt('SearchText','Text',discover.query~='' and '%1' or 'Search games or tags...  (Enter to search)')
  local tagLabel='All tags'
  for _,tag in ipairs(discover.tagChoices) do if tag.key==discover.tagFilter then tagLabel=tag.label;break end end
  opt('TagsText','Text',tagLabel..'  v')
  opt('DiscoveryCount','Text',#games..' of '..#library..' games')
  update('SearchText');update('TagsText');update('DiscoveryCount')
end
function CaptureBrowse()
  local saved={selected=selected,pageStart=pageStart,homeFocus=homeFocusShelf,starts={}}
  for i,shelf in ipairs(homeShelves) do saved.starts[i]=shelf.start end
  return saved
end
restoreBrowse=function(saved)
  if not saved then return end
  selected=saved.selected;pageStart=saved.pageStart;homeFocusShelf=saved.homeFocus
  for i,shelf in ipairs(homeShelves) do shelf.start=clamp(saved.starts[i] or 0,0,homeMaxStart(shelf)) end
end
local function applyDiscovery(saved)
  CancelHover();rebuildOrder();restoreBrowse(saved);alignFocus();slots={}
  drawSlots();labelControls();spotlight(selected,false,true);resetControls();B('!UpdateMeter','*');paint()
end
function SearchDismiss(serial)
  if serial and tonumber(serial)~=discover.searchSerial then return end
  if not discover.searchEditing then return end
  discover.searchEditing=false;discover.searchSerial=discover.searchSerial+1
  B('!ZPos',2);refreshControls();paint()
end
function BeginSearch()
  if not shown or goal~=1 or managerBusy or discover.searchEditing or #library==0 then return end
  HidePicker();CancelHover();alignFocus();drawSlots();spotlight(selected,true)
  progress=1;slide=0;stop()
  opt('SceneClip','Shape',string.format('Rectangle 0,0,%.3f,%.3f,0 | Fill Color 255,255,255,255 | StrokeWidth 0',W,H))
  B('!UpdateMeter','*')
  discover.searchSerial=discover.searchSerial+1;discover.searchEditing=true
  -- Start a replacement query blank: InputText reparses DefaultValue as an option.
  opt('SearchInput','DefaultValue','')
  -- InputText needs the macro to prompt. Read LastInput via GetStringValue instead
  -- of inserting text into a Lua call/bang argument. The unmatched bracket tail
  -- is discarded by Rainmeter's multibang scanner. It exceeds every possible
  -- closing bracket at InputLimit 128, including skin scaling up to 8x.
  opt('SearchInput','Command1','[!CommandMeasure Hub "SearchCommit('..discover.searchSerial..')"]'..string.rep('[',MAX_QUERY*8+1)..'$UserInput$')
  opt('SearchInput','InputLimit',MAX_QUERY)
  opt('SearchInput','OnDismissAction','[!CommandMeasure Hub "SearchDismiss('..discover.searchSerial..')"]')
  -- InputText cannot take focus below Stay Topmost. Restore 2 on every exit.
  B('!ZPos',1);refreshControls();paint();B('!CommandMeasure','SearchInput','ExecuteBatch 1')
end
function SearchCommit(serial)
  if not discover.searchEditing or tonumber(serial)~=discover.searchSerial then return end
  local input=SKIN:GetMeasure('SearchInput');local value=input and input:GetStringValue() or ''
  SearchDismiss(serial)
  if shown and goal==1 and not managerBusy then SetSearch(value) end
end
function SetSearch(value)
  if not shown or goal~=1 or managerBusy then return end
  SearchDismiss();HidePicker()
  local text=trim(tostring(value or ''):gsub('%c',' '):gsub('%s+',' '))
  if text==discover.query then return end
  if discover.query=='' and text~='' then discover.searchBookmarks[view]=CaptureBrowse() end
  local clearing=text=='';discover.query=text;discover.queryKey=discovery.fold(text)
  applyDiscovery(clearing and discover.searchBookmarks[view] or nil)
end
function ResetDiscovery()
  if not shown or goal~=1 or managerBusy then return end
  SearchDismiss();HidePicker()
  local saved=discover.query~='' and discover.searchBookmarks[view] or nil
  discover.query='';discover.queryKey='';discover.tagFilter=''
  if filterMode~='all' then filterMode='all';writeState('State','Filter',filterMode) end
  applyDiscovery(saved)
end
function HidePicker()
  if not discover.pickerMode then return end
  discover.pickerMode=nil;B('!HideMeterGroup','Picker');refreshControls();paint()
end
drawPicker=function()
  if not discover.pickerMode then return end
  local anchor=controls[discover.pickerMode=='filter' and 'Filter' or 'Tags'];local x,y=anchor.x,anchor.y+anchor.h+8*S
  local w=350*S;local count=math.min(MAX_PICKER,#discover.pickerItems-discover.pickerPage);local h=(42+count*38+40)*S
  rect('PickerPanel',x,y,w,h,14*S,'15,29,39,255','198,231,229,115')
  textBox('PickerTitle',x+14*S,y+9*S,w-28*S,27*S,12*S,discover.pickerMode=='filter' and 'Filter games' or 'Collections / tags')
  move('PickerDismiss',0,0);opt('PickerDismiss','W',W);opt('PickerDismiss','H',H)
  B('!ShowMeterGroup','Picker')
  for i=1,MAX_PICKER do
    local name='Picker'..i;local item=discover.pickerItems[discover.pickerPage+i];local cy=y+(38+(i-1)*38)*S
    placeControl(name,name..'Body',name..'Text',name..'Hit',x+8*S,cy,w-16*S,34*S,9*S)
    textBox(name..'Text',x+w/2,cy+17*S,w-40*S,34*S,11*S,item and item.label or '');opt(name..'Text','StringAlign','CenterCenter')
    for _,part in ipairs({'Body','Text','Hit'}) do B(item and '!ShowMeter' or '!HideMeter',name..part) end
  end
  for i,action in ipairs({'Previous','Next'}) do
    local name='Picker'..action;local left=x+(i==1 and 8 or 182)*S
    placeControl(name,name..'Body',name..'Text',name..'Hit',left,y+h-36*S,160*S,28*S,9*S)
    textBox(name..'Text',left+80*S,y+h-22*S,150*S,28*S,10*S,i==1 and '< Previous' or 'Next >');opt(name..'Text','StringAlign','CenterCenter')
  end
  refreshControls();B('!UpdateMeterGroup','Picker');paint()
end
function ShowPicker(kind)
  if not shown or goal~=1 or managerBusy or discover.searchEditing then return end
  if discover.pickerMode==kind then HidePicker();return end
  if kind~='filter' and kind~='tags' then return end
  CancelHover();alignFocus();drawSlots();spotlight(selected,true);B('!UpdateMeter','*')
  discover.pickerMode=kind;discover.pickerPage=0;discover.pickerItems={}
  if kind=='tags' then
    discover.pickerItems[1]={key='',label='All tags'}
    for _,tag in ipairs(discover.tagChoices) do discover.pickerItems[#discover.pickerItems+1]=tag end
  else
    discover.pickerItems={{key='all',label='All games'},{key='favorites',label='Favorites'},{key='steam',label='Steam'},{key='local',label='Local'}}
    for _,key in ipairs({'epic','other'}) do
      if discover.platformCounts[key] or filterMode==key then discover.pickerItems[#discover.pickerItems+1]={key=key,label=key=='epic' and 'Epic' or 'Other'} end
    end
  end
  drawPicker()
end
function PickerPage(direction)
  if not discover.pickerMode then return end
  discover.pickerPage=clamp(discover.pickerPage+((tonumber(direction) or 1)<0 and -1 or 1)*MAX_PICKER,0,math.floor((#discover.pickerItems-1)/MAX_PICKER)*MAX_PICKER)
  drawPicker()
end
function ChoosePicker(index)
  if not discover.pickerMode or managerBusy then return end
  local item=discover.pickerItems[discover.pickerPage+(tonumber(index) or 0)];if not item then return end
  local kind=discover.pickerMode;HidePicker()
  if kind=='filter' then
    if filterMode~=item.key then filterMode=item.key;writeState('State','Filter',filterMode) end
  else discover.tagFilter=item.key end
  applyDiscovery()
end

local function quoted(x) return '"'..tostring(x):gsub('"','')..'"' end
local function notice(message)
  opt('Notice','Text',message);opt('Notice','ToolTipText',message)
  B('!ShowMeter','Notice');update('Notice');paint()
end
local function diagnostic(message,output)
  local f=io.open(resources..'Manager-diagnostics.txt','wb')
  if f then
    f:write('GameHUB 3 (Liquid Glass) '..(release.Version or 'unknown')..' (build '..(release.Build or 'unknown')..')\r\n',os.date('%Y-%m-%d %H:%M:%S'),'\r\n',message,'\r\n\r\n',output or '')
    f:close()
  end
end
local function managerFail(message,output)
  B('!CommandMeasure','ManagerWatch','Stop 1')
  managerBusy=false;managerHid=false
  buttonState('SetBusy',0);refreshControls();HideToast()
  opt('ManageText','Text','+  Manage games');update('ManageText')
  diagnostic(message,output)
  notice(message..'  Click here for diagnostics.')
end
function OpenManagerLog()
  local path=resources..'Manager-diagnostics.txt'
  if exists(path) then B('["'..path..'"]') end
end
function Manager(slot,focusedId)
  if not shown or goal~=1 or discoveryBusy() then return end
  if managerBusy then toast('The game manager is already opening or open.');return end
  local runner=SKIN:GetMeasure('ManagerRunner')
  B('!UpdateMeasure','ManagerRunner')
  if runner and runner:GetValue()==0 then
    toast('A previous manager process is still running. Close it before trying again.');return
  end
  if not exists(resources..'Scripts\\Manager.ps1') then managerFail('The manager script is missing. Reapply the update.');return end
  local id=focusedId or (slot and slots[tonumber(slot)]) or ''
  CancelHover();navigating=false;target=offset;slide=0;managerSerial=managerSerial+1
  managerToken=tostring(os.time())..'_'..tostring(managerSerial)
  local status=io.open(resources..'Manager-status.ini','wb')
  if not status then managerFail('Cannot write manager status. Check the skin folder permissions.');return end
  status:write('[Manager]\nRequestId='..managerToken..'\nStatus=starting\n');status:close()
  managerBusy=true;managerHid=false;managerChecks=0
  buttonState('SetBusy',1);resetControls()
  local args='-ExecutionPolicy Bypass -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File '..quoted(resources..'Scripts\\Manager.ps1')..' -Resources '..quoted(resources:gsub('[\\/]+$',''))..' -RequestId '..quoted(managerToken)
  if id and id~='' then args=args..' -SelectId '..quoted(id) end
  opt('ManagerRunner','Parameter',args);B('!UpdateMeasure','ManagerRunner')
  opt('ManageText','Text','Opening manager...');update('ManageText')
  B('!HideMeter','Notice');toast('Opening manager...')
  B('!CommandMeasure','ManagerRunner','Run')
  B('!CommandMeasure','ManagerWatch','Execute 1')
end
function ManagerCheck()
  if not managerBusy then B('!CommandMeasure','ManagerWatch','Stop 1');return end
  managerChecks=managerChecks+1
  B('!UpdateMeasure','ManagerRunner')
  local runner=SKIN:GetMeasure('ManagerRunner')
  local code=runner and runner:GetValue() or -1
  if code>=100 then managerFail('Rainmeter could not start the manager (code '..tostring(code)..').',runner:GetStringValue());return end
  local status=readIni(resources..'Manager-status.ini').Manager or {}
  if status.RequestId==managerToken and status.Status=='ready' then
    B('!CommandMeasure','ManagerWatch','Stop 1')
    managerHid=true;B('!HideMeter','Notice');Close(true);return
  end
  if managerChecks>=120 then
    local output=runner and runner:GetStringValue() or ''
    managerFail('The manager did not report a visible window within 30 seconds.',output)
  end
end
function ManagerFinished()
  if not managerBusy then return end
  B('!CommandMeasure','ManagerWatch','Stop 1')
  B('!UpdateMeasure','ManagerRunner')
  local runner=SKIN:GetMeasure('ManagerRunner')
  local output=runner and runner:GetStringValue() or ''
  if output:find('GH_OK',1,true) then
    managerBusy=false;managerHid=false;buttonState('SetBusy',0)
    opt('ManageText','Text','+  Manage games');B('!HideMeter','Notice');ReloadAndOpen()
  else
    if managerHid then Open() end
    local lower=output:lower()
    local message='The game manager could not open.'
    if lower:find('execution',1,true) or lower:find('running scripts is disabled',1,true) or lower:find('digitally signed',1,true) then
      message='Windows blocked the manager script. The diagnostic file contains the exact message.'
    end
    managerFail(message,output)
  end
end
function ReloadAndOpen()
  SearchDismiss();HidePicker();stop();CancelHover()
  -- Apply the manager's exposed settings; monitor placement stays resident.
  local savedSettings=readIni(resources..'Settings.ini').Settings or {}
  for _,key in ipairs({'UIScale','OpenMs','CloseMs','FadeMs','WheelStep','ReduceMotion','HeroVideo','PreviewDelay','PreviewAudio','PreviewLoop','HeroCinematic','CinematicDelay'}) do settings[key]=savedSettings[key] end
  S=math.min(W/2560,H/1440)*clamp(tonumber(settings.UIScale) or 1,.7,1.5)
  if motion then motion.logo=nil;motion:close() end
  loadData();geometry();slide=0;fade=nil;fadePath=nil
  alignFocus();drawSlots();spotlight(selected,true);B('!UpdateMeter','*');shown=false;progress=0;Open()
end

-- Fixed callbacks; media filenames and titles are never executable Lua input.
function MotionCommit() if motion then motion:commit() end end
function MotionEvent(session,token,event) if motion then motion:event(session,token,event) end end
function MotionFinished() if motion then motion:finished() end end
function MotionShutdown() if motion then motion:shutdown() end end
function MotionHover(enter)
  if not motion then return end
  if enter==1 and shown and goal==1 and not managerBusy and not discoveryBusy() and not navigating then motion:enter(selected)
  else motion:leave() end
end
