#!/usr/bin/env python3
"""Simulated-host interaction regression checks; native Rainmeter is still required.

Usage: python Maintenance/Test-Interactions.py --lua /path/to/lua5.1
No writes are made to the installed library/state/settings.
"""
from pathlib import Path
import argparse, configparser, json, re, subprocess, tempfile
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lua',required=True,help='Lua 5.1 interpreter executable')
args=parser.parse_args()
BASE=Path(__file__).resolve().parents[1]
RES=BASE/'@Resources'
def ini(path):
    p=configparser.RawConfigParser(strict=True,interpolation=None);p.optionxform=str
    with path.open(encoding='utf-8-sig') as f:p.read_file(f)
    return p
main=ini(BASE/'Main/Main.ini');button=ini(BASE/'Button/Button.ini')
sections={s:dict(main[s]) for s in main.sections()}
for path in [BASE/'Main/Main.ini',BASE/'Button/Button.ini',RES/'Release.ini',RES/'Library.ini',RES/'State.ini',RES/'Settings.ini']:ini(path)
assert main['Rainmeter']['Update']==button['Rainmeter']['Update']=='-1'
assert len([s for s in main if re.fullmatch('Hit[0-9]+',s)])==24
assert {v.get('Plugin') for v in sections.values() if v.get('Measure')=='Plugin'}=={'ActionTimer','RunCommand','InputText'}
for s,v in sections.items():
    if 'Container' in v:assert v['Container'] in sections
for name in ['Search','ClearSearch','Tags','ResetDiscovery','ViewHome','ViewCarousel','ViewGrid','ViewList','Manage','Close','Filter','Sort','Previous','Next','HeroPlay','HeroFavorite','HeroEdit']+[f'Home{i}{action}' for i in range(1,4) for action in ['Previous','Next']]:
    hit=main[name+'Hit']
    for event in ['MouseOverAction','MouseLeaveAction','LeftMouseDownAction','LeftMouseUpAction','LeftMouseDoubleClickAction']:assert event in hit,(name,event)
assert 'LeftMouseDownAction' not in button['ButtonHit'], 'Controller lost native drag-to-position'
assert button['ButtonFeedback']['ActionList1']=='Wait 100 | Release'
assert main['HoverTimer']['ActionList1']=='Wait 55 | Commit'
assert main['HoverLeaveTimer']['ActionList1']=='Wait 80 | Commit'
assert main['Dim']['SolidColor']=='5,12,19,55', 'Artwork phase changed global dim'
assert main['HeroScrim']['Container']=='SceneClip' and main['HeroScrim']['UpdateDivider']=='-1'
assert main['HeroTitle']['StringEffect']==main['HeroPlatform']['StringEffect']=='Shadow'

def literal(o):
    if isinstance(o,dict):return '{'+','.join('['+literal(k)+']='+literal(v) for k,v in o.items())+'}'
    if isinstance(o,str):return json.dumps(o,ensure_ascii=False)
    return str(o)

def run(source):
    with tempfile.TemporaryDirectory() as d:
        p=Path(d)/'test.lua';p.write_text(source,encoding='utf-8')
        result=subprocess.run([args.lua,str(p)],capture_output=True,text=True)
        if result.returncode:
            match=re.search(r':(\d+):',result.stderr)
            if match:
                n=int(match[1]);print('\n'.join(f'{i+1}: {s}' for i,s in enumerate(source.splitlines()) if n-3<=i<=n+1))
            raise AssertionError(result.stderr)
        print(result.stdout,end='')

stub=r'''
local nativeopen=io.open
local fixtureState,fixtureLibrary,fixtureSettings,missingScript,persistFixtureState,inputValue
inputValue=''
local clock=0
local deadlines={}
local updates=0
local managerFiles={}
io.open=function(path,mode)
 -- Mock distinct artwork identities using one bundled valid JPEG.
 if path:match('FixtureArt[/\\]background%d+%.jpg$') then return nativeopen(RESOURCE..'UI/Backdrop.jpg',mode) end
 if missingScript and path:match('Scripts[/\\]Manager.ps1$') then return nil end
 if path:match('Library.ini$') and fixtureLibrary then return {read=function() return fixtureLibrary end,close=function() end} end
 if path:match('Settings.ini$') and fixtureSettings then return {read=function() return fixtureSettings end,close=function() end} end
 if path:match('State.ini$') then return {read=function() return fixtureState or '[State]\nView=carousel\nSort=custom\nFilter=all\nLastId=game001\n' end,close=function() end} end
 if path:match('Manager%-status.ini$') or path:match('Manager%-diagnostics.txt$') then
  local name=path:match('([^/\\]+)$')
  if mode=='wb' then
   local data=''
   return {write=function(self,...) for _,part in ipairs({...}) do data=data..part end end,close=function() managerFiles[name]=data end}
  end
  if managerFiles[name] then return {read=function() return managerFiles[name] end,close=function() end} end
  return nil
 end
 return nativeopen(path:gsub('\\','/'),mode)
end
local options=OPTIONS
local objects,hidden={},{}
local timer=false
local writes,commands,refreshes=0,{},0
local hostVisible=false
local runnerValue,runnerOutput,managerRuns,watch=-1,'GH_OK',0,false
local vars={['@']=RESOURCE,ROOTCONFIG='GameHUBGlass',CURRENTCONFIG='GameHUBGlass\\Main',SCREENAREAWIDTH='2560',SCREENAREAHEIGHT='1440',SCREENAREAX='0',SCREENAREAY='0'}
for name,opts in pairs(options) do
 if opts.Meter then
  objects[name]={x=tonumber(opts.X) or 0,y=tonumber(opts.Y) or 0}
  function objects[name]:SetX(x) assert(type(x)=='number' and x==x,'Invalid X');self.x=x end
  function objects[name]:SetY(y) assert(type(y)=='number' and y==y,'Invalid Y');self.y=y end
  hidden[name]=opts.Hidden=='1'
 end
end
SKIN={}
function SKIN:GetVariable(key,default) return vars[key] or default end
function SKIN:GetMeter(name) assert(objects[name],'Unknown meter '..name);return objects[name] end
function SKIN:GetMeasure(name)
 if name=='SearchInput' then return {GetStringValue=function() return inputValue end,GetValue=function() return 0 end} end
 return {GetStringValue=function() return runnerOutput end,GetValue=function() return runnerValue end} end
function SKIN:Bang(command,a,b,c,d)
 commands[#commands+1]={command,a,b,c,d}
 if command=='!SetOption' then assert(options[a],'Unknown section '..tostring(a));options[a][b]=c
 elseif command=='!UpdateMeter' then updates=updates+1;assert(a=='*' or objects[a],'Unknown update '..tostring(a))
 elseif command=='!Show' then hostVisible=true
 elseif command=='!Hide' then hostVisible=false
 elseif command=='!ShowMeter' or command=='!HideMeter' then hidden[a]=command=='!HideMeter'
 elseif command=='!HideMeterGroup' or command=='!ShowMeterGroup' then
  for name,opts in pairs(options) do if opts.Group==a then hidden[name]=command=='!HideMeterGroup' end end
 elseif command=='!CommandMeasure' and a=='Animator' then timer=b=='Execute 1'
 elseif command=='!CommandMeasure' and (a=='HoverTimer' or a=='HoverLeaveTimer' or a=='ToastTimer' or a=='MotionDelay') then
  deadlines[a]=b=='Execute 1' and clock+(a=='MotionDelay' and tonumber(options.MotionDelay.ActionList1:match('Wait (%d+)')) or a=='HoverTimer' and 55 or a=='HoverLeaveTimer' and 80 or 2600) or nil
 elseif command=='!CommandMeasure' and a=='ManagerWatch' then watch=b=='Execute 1'
 elseif command=='!CommandMeasure' and a=='ManagerRunner' and b=='Run' then runnerValue=0;managerRuns=managerRuns+1
 elseif command=='!WriteKeyValue' then
  writes=writes+1
  if persistFixtureState and d:match('State.ini$') then persistFixtureState(a,b,c) end
 elseif command=='!Refresh' or command=='!ActivateConfig' then refreshes=refreshes+1
 end
end
function settle()
 local count=0
 while timer and count<400 do Tick();count=count+1 end
 assert(not timer,'Animation failed to stop')
 return count
end
'''.replace('OPTIONS',literal(sections)).replace('RESOURCE',literal(str(RES)+'/'))
# Lua disallows a function statement indexed as function objects[name]:foo.
stub=stub.replace("function objects[name]:SetX(x) assert(type(x)=='number' and x==x,'Invalid X');self.x=x end","objects[name].SetX=function(self,x) assert(type(x)=='number' and x==x,'Invalid X');self.x=x end")
stub=stub.replace("function objects[name]:SetY(y) assert(type(y)=='number' and y==y,'Invalid Y');self.y=y end","objects[name].SetY=function(self,y) assert(type(y)=='number' and y==y,'Invalid Y');self.y=y end")
helpers=r'''
-- A real skin refresh recreates meter visibility from INI before Initialize.
local initializeSkin=Initialize
function Initialize()
 for name,opts in pairs(options) do if opts.Meter then hidden[name]=opts.Hidden=='1' end end
 initializeSkin()
end
function advance(ms)
 local untilTime=clock+ms
 while clock<untilTime do
  clock=clock+1
  if timer and clock%16==0 then Tick() end
  if deadlines.HoverTimer and deadlines.HoverTimer<=clock then deadlines.HoverTimer=nil;CommitHover() end
  if deadlines.HoverLeaveTimer and deadlines.HoverLeaveTimer<=clock then deadlines.HoverLeaveTimer=nil;CommitHoverLeave() end
  if deadlines.MotionDelay and deadlines.MotionDelay<=clock then deadlines.MotionDelay=nil;MotionCommit() end
  if deadlines.ToastTimer and deadlines.ToastTimer<=clock then deadlines.ToastTimer=nil;HideToast() end
 end
end
function selectFilter(key)
 ShowPicker('filter')
 for i,item in ipairs(discover.pickerItems) do if item.key==key then ChoosePicker(i);return end end
 error('Missing filter '..key)
end
function click(name)
 Control(name,'over');Control(name,'down');Control(name,'up')
end
function fresh(count,mode,reduce)
 local defaultFixture=count==nil
 count=count or 15
 fixtureLibrary=nil;fixtureSettings='[Settings]\nReduceMotion='..(reduce and '1' or '0')..'\n'
 fixtureState='[State]\nView='..(mode or 'carousel')..'\nSort=custom\nFilter=all\nLastId=game001\n'
 if count then
  fixtureLibrary='[Library]\nVersion=1\n'
  for i=1,count do
   fixtureLibrary=fixtureLibrary..string.format('[Game:game%03d]\nName=Test game %03d\nPlatform=Steam\nTarget=steam://rungameid/%d\nOrder=%d\n',i,i,1000+i,i)
   if defaultFixture then fixtureLibrary=fixtureLibrary..string.format('Background=FixtureArt/background%03d.jpg\n',i) end
  end
 end
 runnerValue=-1;runnerOutput='GH_OK';managerFiles={};deadlines={};timer=false;watch=false
 Initialize();Boot();Open();settle()
end
function focusCoherent()
 if #games==0 then
  assert(selected==nil and controls.HeroPlay.disabled and controls.HeroEdit.disabled and controls.HeroFavorite.disabled,'Empty library left live Hero actions')
  return
 end
 local game=findGame(selected);assert(game,'Focus does not identify a library game')
 assert(options.HeroTitle.Text==game.name,'Hero title differs from focus')
 assert(options.HeroPlatform.Text:sub(1,#game.platform)==game.platform,'Platform differs from focus')
 assert(options.PanelFrostImage.ImageName==game.blur,'Frost differs from focus')
 assert((fadePath or backgroundPath)==game.background,'Background target differs from focus')
 assert(options.HeroFavorite.Text==(favorites[selected]=='1' and 'Unfavorite' or 'Favorite'),'Favorite action differs from focus')
 local seen=false
 for i,id in pairs(slots) do if id==selected then seen=true end end
 assert(seen,'Focus not bound to a visible-page slot')
end
function primaryCoherent()
 focusCoherent()
 local nearest=math.huge;local focused=math.huge;local anchor=88*S
 for i,id in pairs(slots) do
  local distance=math.abs(objects['Card'..i].x-anchor)
  nearest=math.min(nearest,distance)
  if id==selected then focused=math.min(focused,distance) end
 end
 assert(focused<=nearest+.01,'Focus is not the nearest primary-position game')
end
function stepNavigation()
 local n=0
 while timer and n<400 do Tick();primaryCoherent();n=n+1 end
 assert(not timer,'Navigation did not return to idle')
end
function launches()
 local result={}
 for _,c in ipairs(commands) do if c[1]:sub(1,2)=='["' then result[#result+1]=c[1] end end
 return result
end
'''
tests=r'''
fresh();primaryCoherent()
local baselineWrites=writes;local baselineRefreshes=refreshes
for i=1,36 do
 Scroll(i%4==0 and -1 or 1);Tick();primaryCoherent()
 -- Native hover events from sliding cards cannot override wheel focus.
 Hover(4);CommitHover();primaryCoherent()
end
stepNavigation();assert(writes==baselineWrites and refreshes==baselineRefreshes,'Navigation wrote state or refreshed the skin')
for i=1,21 do click(i%3==0 and 'Previous' or 'Next');Tick();primaryCoherent() end
stepNavigation()
local focused=selected;local targetGame=findGame(focused).launch
click('HeroPlay');assert(not hostVisible and launches()[#launches()]=='["'..targetGame..'"]','Hero Play launched a stale target')
Open();settle();primaryCoherent()
-- An interrupted press is cancelled, including a focus change while held.
local before=#launches();Control('HeroPlay','down');Scroll(1);stepNavigation();Control('HeroPlay','up')
assert(#launches()==before,'A held Hero action launched a newly focused game')
Control('HeroPlay','down');Control('HeroPlay','leave');Control('HeroPlay','up');assert(#launches()==before)
-- Rapid click / Windows double-click Down/Up pairs both navigate once.
local previousTarget=target
for i=1,2 do Control('Next','down');Control('Next','up') end
assert(target==previousTarget+2,'Rapid Next clicks were dropped or doubled');stepNavigation()
-- Fast sweeps retain immediate feedback, with no leave flash or stale commit.
View('grid');settle()
for i=1,10 do
 Hover(i);assert(options['Card'..i].Shape:find('209,250,239,230',1,true),'Hover outline lagged')
 Leave(i);Hover(i+1);CommitHoverLeave()
 assert(options['Card'..(i+1)].Shape:find('209,250,239,230',1,true),'Rapid hover flash returned')
 advance(12)
end
advance(55);settle();focusCoherent();assert(selected==slots[11])
Hover(12);Leave(12);advance(80);focusCoherent()
for i,id in pairs(slots) do assert((options['Card'..i].Shape:find('209,250,239,230',1,true)~=nil)==(id==selected),'Hover leave restored an incorrect outline') end
-- Reversal retains the same two-layer mixture, then finishes on current focus.
Hover(3);CommitHover();settle();local first=backgroundPath
Hover(4);CommitHover();Tick();local second=fadePath;local amount=fade
Hover(3);CommitHover()
assert(backgroundPath==second and fadePath==first and math.abs(fade-(1-amount))<.00001,'Crossfade reversal flashed a different mixture')
settle();focusCoherent()
-- Rebinding a view cancels a pending hover, and sort retains valid focus.
Hover(2);View('list');advance(100);settle();focusCoherent()
local keep=selected;Sort();assert(selected==keep);focusCoherent();View('carousel');settle();primaryCoherent()
-- Close/open can reverse during movement. Hidden late callbacks are inert.
Scroll(1);Tick();Close();Tick();Open();settle();focusCoherent()
Hover(3);Close(true);local saved=selected;CommitHover();CommitHoverLeave();Tick();assert(not hostVisible and selected==saved)
Open();settle();primaryCoherent()
-- Favorites actions and empty favorites; feedback expires without animation polling.
fresh();click('HeroFavorite');assert(favorites[selected]=='1' and options.HeroFavorite.Text=='Unfavorite')
assert(options.ToastText.Text:find('Added to Favorites',1,true) and not hidden.ToastText)
assert(not timer,'A static toast kept the animation loop running')
advance(2600);assert(hidden.ToastText and not timer)
selectFilter('favorites');focusCoherent();click('HeroFavorite');focusCoherent()
assert(options.ToastText.Text:find('Removed from Favorites',1,true) and #games==0)
local emptyLaunches=#launches();click('HeroPlay');click('HeroEdit');assert(#launches()==emptyLaunches and not managerBusy)
selectFilter('all');focusCoherent()
-- Card shortcuts remain direct and address the clicked game, regardless of focus.
View('grid');local id=slots[4];Favorite(4);assert(favorites[id]=='1')
local clicked=findGame(slots[5]).launch;Launch(5);assert(launches()[#launches()]=='["'..clicked..'"]')
Open();settle()
-- Missing/invalid targets surface transient feedback without a false launch/history.
local g=findGame(selected);g.launch='Z:\\missing-game\\missing.lnk';before=#launches();baselineWrites=writes
click('HeroPlay');assert(hostVisible and #launches()==before and writes==baselineWrites)
assert(options.ToastText.Text:find('Shortcut not found',1,true));focusCoherent()
g.launch='bad"target';click('HeroPlay');assert(#launches()==before and options.ToastText.Text:find('Invalid launch target',1,true));focusCoherent()
g.launch='steam://rungameid/1085660';click('HeroPlay');assert(#launches()==before+1 and not hostVisible)
-- Manager handoff, targeted Edit, duplicate/stale requests, failure/timeout/return.
fresh();Scroll(1);stepNavigation();local editId=selected;click('HeroEdit')
assert(hostVisible and watch and controls.Manage.disabled and controls.HeroPlay.disabled)
assert(options.ManagerRunner.Parameter:find('-SelectId "'..editId..'"',1,true))
assert(options.ManagerRunner.Parameter:find('-ExecutionPolicy Bypass',1,true))
assert(options.ToastText.Text=='Opening manager...')
local requested=options.ManagerRunner.Parameter:match('%-RequestId "([^"]+)"')
local runsBefore=managerRuns;Manager();click('Manage');assert(managerRuns==runsBefore)
managerFiles['Manager-status.ini']='[Manager]\nRequestId=old\nStatus=ready\n';ManagerCheck();assert(hostVisible)
managerFiles['Manager-status.ini']='[Manager]\nRequestId='..requested..'\nStatus=ready\n';ManagerCheck();assert(not hostVisible and not watch)
runnerValue=1;runnerOutput='GH_OK';ManagerFinished();settle();assert(hostVisible and not controls.Manage.disabled);focusCoherent()
assert(options.ManageText.Text=='+  Manage games')
Manager(3);assert(options.ManagerRunner.Parameter:find('-SelectId "'..slots[3]..'"',1,true))
runnerValue=103;runnerOutput='Cannot start process';ManagerCheck();assert(hostVisible and not watch and not hidden.Notice and not controls.Manage.disabled)
assert(managerFiles['Manager-diagnostics.txt']:find('GameHUB 3 (Liquid Glass) '..release.Version,1,true))
runnerValue=1;Manager();runnerValue=1;runnerOutput='running scripts is disabled';ManagerFinished();assert(hostVisible and options.Notice.Text:find('Windows blocked',1,true))
Manager();for i=1,120 do ManagerCheck() end;assert(hostVisible and not watch and not controls.Manage.disabled)
assert(options.Notice.Text:find('30 seconds',1,true));runnerValue=1
-- Real hit rectangles are centered on their text; drag-away cancels pressed state.
fresh()
for _,name in ipairs({'ViewCarousel','ViewGrid','ViewList','Manage','Close','Filter','Sort','Previous','Next','HeroPlay','HeroFavorite','HeroEdit'}) do
 local c=controls[name]
 assert(objects[c.hit].x==c.x and objects[c.hit].y==c.y)
 if c.label then assert(math.abs(objects[c.label].x-c.x-c.w/2)<.01,name..' text is not centered') end
 if not c.disabled then
  Control(name,'over');assert(c.style=='hover');Control(name,'down');assert(c.style=='pressed')
  Control(name,'leave');assert(c.style~='pressed' and c.style~='hover')
 end
end
print('PASS: focus/hero synchronization per animation frame, rapid navigation/hover, launch identity, control states, toast expiry, favorites, transitions, failures and manager handshake')
'''
source=(RES/'Scripts/Hub.lua').read_text(encoding='utf-8')
for width,height in [(2560,1440),(3840,2160)]:
    resized=stub.replace("SCREENAREAWIDTH='2560',SCREENAREAHEIGHT='1440'",f"SCREENAREAWIDTH='{width}',SCREENAREAHEIGHT='{height}'")
    run(resized+'\n'+source+'\n'+helpers+'\n'+tests)

artwork=r'''
-- RGB is stored metadata; no image decoding/sampling in the launcher.
for _,bad in ipairs({'','0,0,0','255,255,255','120,120,120','255,0,0','999,50,50','-1,20,30','1,2','red','90,100,110,200','1;2;3'}) do
 assert(readAccent(bad)==DEFAULT_ACCENT,'Unsafe/malformed accent did not fall back: '..bad)
end
assert(readAccent(nil)==DEFAULT_ACCENT and readAccent(' 98, 168, 218 ')=='98,168,218')
for _,mode in ipairs({'carousel','grid','list'}) do
 for _,reduce in ipairs({false,true}) do
  fresh(8,mode,reduce)
  fixtureLibrary=fixtureLibrary:gsub('Version=1','Version=2'):gsub('Order=1\n','Order=1\nAccent=98,168,218\nCoverFocalX=1\nCoverZoom=3\n')
  fixtureLibrary=fixtureLibrary:gsub('Order=2\n','Order=2\nAccent=218,118,98\nBackgroundFocalY=0\nBackgroundZoom=3\n')
  Initialize();Boot();Open();settle()
  assert(focusAccent=='98,168,218')
  assert(options.HeroPlayBody.Shape:find('98,168,218,170',1,true),'Play accent differs from focus')
  local first,second
  for i,id in pairs(slots) do if id=='game001' then first=i elseif id=='game002' then second=i end end
  assert(first and second)
  assert(options['Card'..first].Shape:find('98,168,218,230',1,true))
  local writesBefore=writes
  Hover(second)
  assert(options['Card'..second].Shape:find('218,118,98,230',1,true),'Hover accent not immediate')
  assert(focusAccent=='98,168,218','Hover committed before existing delay')
  Leave(second);Hover(first);advance(55)
  assert(focusAccent=='98,168,218','Rapid sweep committed an abandoned accent')
  Hover(second);advance(55);settle()
  assert(selected=='game002' and focusAccent=='218,118,98')
  assert(options.HeroPlayBody.Shape:find('218,118,98,170',1,true),'Cached control style retained old accent')
  assert(options.HeroPlay.FontColor=='220,255,242,255','Accent recolored readable action text')
  if mode=='carousel' then Scroll(1);stepNavigation();assert(focusAccent==findGame(selected).accent) end
  assert(writes==writesBefore,'Artwork focus caused file writes')
  assert(not timer,'Static artwork kept the animation timer running')
  spotlight(nil,true);assert(focusAccent==DEFAULT_ACCENT and controls.HeroPlay.disabled)
  -- The scrim is positioned around the Hero, while the cached art paths stay fixed.
  assert(objects.HeroScrim.y<objects.HeroTitle.y)
  assert(options.HeroScrim.Shape:find('Fill RadialGradient HeroShade',1,true))
 end
end
print('PASS: legacy/default and malformed accents, game-aware focus/hover/controls, static Hero scrim, all views, 4K coordinates and ReduceMotion')
'''
for width,height in [(2560,1440),(3840,2160)]:
    resized=stub.replace("SCREENAREAWIDTH='2560',SCREENAREAHEIGHT='1440'",f"SCREENAREAWIDTH='{width}',SCREENAREAHEIGHT='{height}'")
    run(resized+'\n'+source+'\n'+helpers+'\n'+artwork)

paging=r'''
for _,mode in ipairs({'grid','list'}) do
 fresh(80,mode)
 local stableWrites=writes
 for i=1,45 do
  Scroll(1);settle();focusCoherent()
  assert(findIndex(selected)>pageStart and findIndex(selected)<=pageStart+visible)
 end
 assert(controls.Next.disabled and options.NextHit.MouseActionCursor=='0')
 local endPage=pageStart;click('Next');assert(pageStart==endPage)
 for i=1,45 do Scroll(-1);settle();focusCoherent() end
 assert(pageStart==0 and controls.Previous.disabled and writes==stableWrites)
 -- View changes reveal a far-away focus instead of leaving stale invisible focus.
 local last=games[80].id;spotlight(last,true);View('carousel');settle();primaryCoherent()
 View(mode);settle();focusCoherent();assert(findIndex(selected)>pageStart and findIndex(selected)<=pageStart+visible)
end
for _,count in ipairs({0,1,2,3,4,5}) do
 fresh(count);focusCoherent()
 if count>1 then
  for i=1,12 do Scroll(1);stepNavigation() end
  for i=1,12 do Scroll(-1);stepNavigation() end
  if count<5 then assert(controls.Previous.disabled and not controls.Next.disabled) end
  for i=1,count do Hover(i);Leave(i) end;advance(80);settle();focusCoherent()
 else assert(controls.Previous.disabled and controls.Next.disabled) end
end
for _,mode in ipairs({'carousel','grid','list'}) do
 fresh(50,mode,true)
 assert(progress==1 and not timer and slide==0 and not fade,'ReduceMotion opening animated')
 for i=1,12 do Scroll(1);assert(not timer and offset==target and slide==0 and not fade);focusCoherent() end
 Hover(3);advance(55);assert(not timer and not fade);focusCoherent()
 click('HeroFavorite');assert(not timer);advance(2600);assert(hidden.ToastText)
 Close();assert(not hostVisible and not timer);Open();assert(hostVisible and not timer)
 View(mode=='grid' and 'list' or 'grid');assert(not timer);focusCoherent()
end

-- First-open commands can arrive before Boot; a close cancels both hover timers.
fresh();Close(true);Initialize();Open(540,330);Boot();settle();assert(hostVisible and goal==1);focusCoherent()
for i=1,12 do
 Scroll(1);Tick();Close();Tick();Open();Tick()
end
settle();focusCoherent();assert(not timer)
-- Hero buttons occupy their own area above the shelf / beside the Grid/List title.
for _,scale in ipairs({'.7','1','1.5'}) do
 fresh();Close(true);fixtureSettings='[Settings]\nUIScale='..scale..'\n'
 Initialize();Boot();Open();settle()
 for _,mode in ipairs({'carousel','grid','list'}) do
  View(mode);settle();focusCoherent()
  local play=controls.HeroPlay;local edit=controls.HeroEdit
  assert(play.y+play.h<panelY and edit.x+edit.w<=W-margin,'Hero actions overlap the shelf or screen edge')
  if mode~='carousel' then
   assert(objects.HeroTitle.x+tonumber(options.HeroTitle.W)<play.x,'Hero title overlaps the action area')
  else assert(objects.HeroTitle.y+tonumber(options.HeroTitle.H)<play.y,'Carousel title overlaps Hero actions') end
 end
end
print('PASS: 80-game Grid/List paging, boundaries, view/sort focus retention, 0-5-game collections, and ReduceMotion')
'''
run(stub+'\n'+source+'\n'+helpers+'\n'+paging)
settings_reload=r'''
for _,mode in ipairs({'carousel','grid','list'}) do
 fresh(50,mode)
 local baselineW,baselineH,baselineS=W,H,S
 local stableWrites,stableRefreshes=writes,refreshes
 local nextSettings='[Settings]\nUIScale=1.25\nOpenMs=100\nCloseMs=50\nFadeMs=75\nWheelStep=3\nReduceMotion=1\nWidth=12\nHeight=12\nX=900\n'
 -- The successful manager callback must apply settings without refreshing a skin.
 Manager(nil,selected);fixtureSettings=nextSettings;runnerValue=1;runnerOutput='GH_OK';ManagerFinished()
 assert(W==baselineW and H==baselineH and S==baselineS*1.25,'Manager did not apply scale or changed monitor geometry')
 assert(settings.OpenMs=='100' and settings.CloseMs=='50' and settings.FadeMs=='75' and settings.WheelStep=='3' and settings.ReduceMotion=='1')
 assert(shown and progress==1 and not timer and not fade,'ReduceMotion was not applied on return from manager')
 focusCoherent()
 local before=offset;Scroll(1)
 if mode=='carousel' then assert(target-before==3 and offset==target,'New wheel step did not apply') end
 assert(not timer);focusCoherent()
 assert(refreshes==stableRefreshes and writes==stableWrites,'Manager settings required a refresh or wrote state during navigation')
 Close();assert(not timer and not shown);Open();assert(not timer and shown)
 fixtureSettings='[Settings]\nUIScale=0.7\nOpenMs=0\nCloseMs=0\nFadeMs=0\nWheelStep=1\nReduceMotion=0\n'
 ReloadAndOpen();settle();assert(S==baselineS*.7 and progress==1);Hover(3);advance(55);settle();focusCoherent()
 Close();settle();assert(not shown and not timer,'Zero-duration transition failed')
 fixtureSettings='[Settings]\n'
 ReloadAndOpen();settle();assert(S==baselineS and settings.ReduceMotion==nil,'Removed settings did not use launcher defaults')
 focusCoherent()
end
print('PASS: manager return applies six settings, scale, timing, wheel step and ReduceMotion without skin refreshes, navigation writes, or monitor relocation')
'''
for width,height in [(2560,1440),(3840,2160)]:
    resized=stub.replace("SCREENAREAWIDTH='2560',SCREENAREAHEIGHT='1440'",f"SCREENAREAWIDTH='{width}',SCREENAREAHEIGHT='{height}'")
    run(resized+'\n'+source+'\n'+helpers+'\n'+settings_reload)

home_tests=r'''
-- Home's collection rules are deliberately independent of saved browse filters.
local function homeFresh(count,reduce,withHistory,withFavorites)
 fresh(count,'home',reduce)
 fixtureState=fixtureState..'[History]\n'
 if withHistory then
  for i=1,count do fixtureState=fixtureState..string.format('game%03d=%d\n',i,os.time()-i*86400) end
 end
 fixtureState=fixtureState..'[Favorites]\n'
 if withFavorites then
  for i=1,count do if i%2==1 then fixtureState=fixtureState..string.format('game%03d=1\n',i) end end
 end
 fixtureState=fixtureState..'[Custom]\nKeep=untouched\n'
 Initialize();Boot();Open();settle()
end
local function homeCoherent()
 focusCoherent()
 assert(view=='home' and not hidden.FilterHit and hidden.SortHit and hidden.PreviousHit and hidden.NextHit and hidden.Count)
 assert(not hidden.ViewHomeHit and controls.ViewHome.active)
 local visibleCount,focusedCount=0,0
 for i=1,24 do
  if slots[i] then
   visibleCount=visibleCount+1
   local shelf=homeShelves[shelfForSlot(i)]
   assert((i-1)%8<shelf.columns and slots[i]==shelf.games[shelf.start+(i-1)%8+1].id)
   assert(not hidden['Hit'..i] and math.abs(tonumber(options['Hit'..i].W)-shelf.cardW)<.001)
   local x,y=objects['Hit'..i].x,objects['Hit'..i].y
   assert(x>=margin and x+shelf.cardW<=W-margin+20*S,'Home card out of horizontal bounds')
   assert(y>=panelY and y+shelf.cardH<=objects.Footer.y-6*S,'Home card overlaps footer')
   if focusedSlot(i,slots[i]) then focusedCount=focusedCount+1 end
  else assert(hidden['Hit'..i],'Empty Home slot still clickable') end
 end
 assert(visibleCount<=24 and focusedCount==(#games>0 and 1 or 0),'Home duplicated or lost focused selection')
 for i,shelf in ipairs(homeShelves) do
  assert(hidden['Home'..i..'Empty']==(#shelf.games>0),'Shelf empty state stale')
  assert(controls['Home'..i..'Previous'].disabled==(shelf.start==0))
  assert(controls['Home'..i..'Next'].disabled==(shelf.start==homeMaxStart(shelf)))
 end
end
local function homeSlot(id,row)
 for i,value in pairs(slots) do if value==id and (not row or shelfForSlot(i)==row) then return i end end
end

do
-- Missing state selects Home; existing choices are retained without on-read writes.
fresh(1);fixtureState='[State]\n';local startWrites=writes
Initialize();Boot();Open();settle();assert(view=='home' and writes==startWrites);homeCoherent()
for _,mode in ipairs({'carousel','grid','list'}) do fresh(1,mode);assert(view==mode) end

end
do
-- Empty/no-history/no-favorites, small and regular libraries, with either motion mode.
for _,reduce in ipairs({false,true}) do
 for _,count in ipairs({0,1,2,3,4,5,15}) do
  for _,populated in ipairs({false,true}) do
   homeFresh(count,reduce,populated,populated);homeCoherent()
   assert(#homeShelves[1].games==(populated and count or 0))
   assert(#homeShelves[2].games==(populated and math.ceil(count/2) or 0))
   assert(#homeShelves[3].games==count)
   for i,g in ipairs(homeShelves[3].games) do assert(g.order==i) end
   local before=writes
   for row=1,3 do
    for i=1,8 do Scroll(1,row);settle();homeCoherent() end
    for i=1,8 do Scroll(-1,row);settle();homeCoherent() end
   end
   assert(writes==before and not timer,'Home browsing wrote data or polled at idle')
   if reduce then assert(progress==1 and slide==0 and not fade) end
  end
 end
end

end
do
-- Large local data uses the same fixed meters, independent row pages and one focus.
homeFresh(1000,false,true,true)
local before,refreshBefore=writes,refreshes
for row=1,3 do
 local otherStarts={homeShelves[1].start,homeShelves[2].start,homeShelves[3].start}
 for i=1,18 do click('Home'..row..'Next');Tick();homeCoherent() end
 settle();homeCoherent()
 for other=1,3 do if other~=row then assert(homeShelves[other].start==otherStarts[other]) end end
 for i=1,18 do click('Home'..row..'Previous');Tick();homeCoherent() end
 settle();assert(homeShelves[row].start==0);homeCoherent()
 HomeShelfHover(row);Scroll(1);settle();assert(homeFocusShelf==row and homeShelves[row].start>0)
 Scroll(-1,row);settle()
end
assert(writes==before and refreshes==refreshBefore)
-- First/last pages clamp without wrapping; disabled controls cannot change focus.
for row=1,3 do
 homeShelves[row].start=homeMaxStart(homeShelves[row]);homeFocusShelf=row
 selected=homeShelves[row].games[homeShelves[row].start+1].id
 alignFocus();slots={};drawSlots();spotlight(selected,true);homeCoherent()
 local old=selected;click('Home'..row..'Next');Scroll(1,row);assert(selected==old);homeCoherent()
end

end
do
-- Home applies discovery filters and retains its custom shelf ordering.
homeFresh(15,false,true,true)
fixtureState=fixtureState:gsub('Sort=custom','Sort=az'):gsub('Filter=all','Filter=favorites')
Initialize();Boot();Open();settle();homeCoherent();assert(#games==8 and sortMode=='az' and filterMode=='favorites')
local before=writes;Sort();assert(writes==before)
selected='game004';alignFocus();slots={};drawSlots();spotlight(selected,true);homeCoherent()
View('grid');settle();focusCoherent();assert(filterMode=='favorites' and sortMode=='az' and #games==8)
assert(not hidden.FilterHit and not hidden.SortHit and hidden.Home1Title and hidden.Home3NextHit)
View('home');settle();homeCoherent();assert(#games==8)
for _,mode in ipairs({'carousel','grid','list','home'}) do View(mode);settle();focusCoherent() end

end
do
-- Duplicate copies share an ID but only the current shelf owns the selected border.
homeFresh(15,false,true,true)
local first=homeSlot('game001',1);local favorite=homeSlot('game001',2)
Hover(first);advance(55);settle();homeCoherent();assert(homeFocusShelf==1)
Hover(favorite);assert(homeFocusShelf==2);Leave(favorite);advance(80);homeCoherent()
local active=0
for i in pairs(slots) do if options['Card'..i].Shape:find(string.format('StrokeWidth %.2f',2*S),1,true) then active=active+1 end end
assert(active==1,'Multiple Home copies received selected borders')
-- Rapid hover preserves immediate outline + the established 55/80 ms protection.
local focused=selected
for i=17,22 do
 Hover(i);assert(hoverSlot==i);Leave(i);advance(4)
 assert(selected==focused,'Fast sweep changed Hero before debounce')
end
Hover(20);advance(55);settle();homeCoherent();assert(selected==slots[20] and homeFocusShelf==3)
local focused=selected;Scroll(1,3);Hover(17);advance(55);settle();homeCoherent()
assert(not pending and selected~=focused,'Pointer event over moving cards stole navigation focus')

end
do
-- Favoriting rebuilds shelves in memory, including focused removal and empty state.
homeFresh(15,true,false,false)
Favorite(17);homeCoherent();assert(#homeShelves[2].games==1 and favorites.game001=='1')
Hover(9);advance(55);assert(homeFocusShelf==2)
click('HeroFavorite');homeCoherent();assert(#homeShelves[2].games==0 and selected=='game001' and homeFocusShelf==3)
for i=17,22 do Favorite(i);homeCoherent() end
Hover(9);advance(55);Favorite(9);homeCoherent();assert(favorites.game001=='0')

end
do
-- Round-trip the host's per-key State writes. Other sections survive unchanged.
persistFixtureState=function(section,key,value)
 local data=readIni(resources..'State.ini');data[section]=data[section] or {};data[section][key]=value
 local chunks={}
 for name,values in pairs(data) do
  chunks[#chunks+1]='['..name..']\n'
  for k,v in pairs(values) do chunks[#chunks+1]=k..'='..v..'\n' end
 end
 fixtureState=table.concat(chunks)
end
homeFresh(15,true,true,true)
assert(countFor('game001')==nil and not options.HeroPlatform.Text:find('GameHUB launches',1,true))
local nativeTime=os.time;local fixedNow=nativeTime()
os.time=function(t) if t then return nativeTime(t) end return fixedNow end
local before=writes;local beforeLaunches=#launches()
Launch(homeSlot('game005',3));assert(#launches()==beforeLaunches+1 and launchCounts.game005=='1' and not shown)
Launch(17);assert(launchCounts.game005=='1','Closed launcher accepted duplicate dispatch')
assert(writes==before+3,'Launch must only update timestamp, count and last focus')
assert(readIni(resources..'State.ini').Custom.Keep=='untouched')
Open();assert(homeShelves[1].games[1].id=='game005' and selected=='game005');homeCoherent()
assert(options.HeroPlatform.Text:find('1 GameHUB launch',1,true) and options.HeroPlatform.Text:find('Last launched today',1,true))
Hero('Play');Open();assert(launchCounts.game005=='2');homeCoherent()
fixedNow=fixedNow+1
Launch(homeSlot('game002',3));Open();assert(homeShelves[1].games[1].id=='game002' and homeShelves[1].games[2].id=='game005');homeCoherent()
Initialize();Boot();Open();settle();homeCoherent();assert(launchCounts.game005=='2' and launchCounts.game002=='1')
-- Invalid/missing targets neither close the launcher nor record a launch/count.
local g=findGame(selected);local before=writes;local count=launchCounts[selected]
g.launch='Shortcuts/phase4-missing.lnk';Hero('Play');assert(shown and writes==before and launchCounts[selected]==count)
g.launch='bad"target';Hero('Play');assert(shown and writes==before and launchCounts[selected]==count)
-- Manager return preserves Home, selection, counts and the original handshake.
Manager(nil,selected);managerFiles['Manager-status.ini']='[Manager]\nRequestId='..managerToken..'\nStatus=ready\n'
ManagerCheck();assert(managerHid and not shown)
runnerValue=1;runnerOutput='GH_OK';ManagerFinished();settle();homeCoherent();assert(launchCounts.game005=='2' and not managerBusy)
-- If the manager removes focused data, rebuild must choose a real visible game.
fixtureLibrary=fixtureLibrary:gsub('%[Game:game002%]\n.-Order=2\n','')
ReloadAndOpen();settle();homeCoherent();assert(selected~='game002')
os.time=nativeTime;persistFixtureState=nil

end
do
-- Dates use local calendar boundaries; malformed/future data never fabricates history.
homeFresh(15,true,false,false)
local now=os.time();local today=os.date('*t',now)
local yesterday={year=today.year,month=today.month,day=today.day-1,hour=12}
history.game001=tostring(now);history.game002=tostring(os.time(yesterday))
history.game003=tostring(os.time{year=today.year,month=today.month,day=today.day-4,hour=12})
assert(launchAge('game001')=='Last launched today' and launchAge('game002')=='Last launched yesterday' and launchAge('game003')=='Last launched 4 days ago')
assert(calendarDay{year=2024,month=3,day=1}-calendarDay{year=2024,month=2,day=28}==2)
assert(calendarDay{year=2025,month=1,day=1}-calendarDay{year=2024,month=12,day=31}==1)
for _,bad in ipairs({'-1','0','nope','1.5','1e999',tostring(now+86400)}) do
 history.game004=bad;assert(historyTime('game004')==nil);rebuildOrder();assert(#homeShelves[1].games==3)
end
for _,bad in ipairs({'-1','nope','1.5','1e999','2147483648'}) do launchCounts.game001=bad;assert(countFor('game001')==nil) end
launchCounts.game001='2147483647';selected='game001';Hero('Play');assert(launchCounts.game001=='2147483647')
Open();homeCoherent();assert(options.HeroPlatform.Text:find('2147483647+ GameHUB launches',1,true))
-- Timestamp ties remain deterministic, independent of Lua table iteration order.
history.game002=history.game001;rebuildOrder();assert(homeShelves[1].games[1].id=='game001')

end
do
-- Geometry at all supported UI scale limits, interruption and ReduceMotion.
for _,scale in ipairs({'.7','1','1.5'}) do
 for _,reduce in ipairs({false,true}) do
  homeFresh(15,reduce,true,true)
  fixtureSettings='[Settings]\nUIScale='..scale..'\nReduceMotion='..(reduce and '1' or '0')..'\n'
  ReloadAndOpen();settle();homeCoherent()
  assert(controls.HeroPlay.y+controls.HeroPlay.h<panelY)
  assert(objects.HeroTitle.x+tonumber(options.HeroTitle.W)<controls.HeroPlay.x)
  for name,c in pairs(controls) do if c.label and name~='Search' then
   assert(math.abs(objects[c.label].x-c.x-c.w/2)<.01 and math.abs(objects[c.label].y-c.y-c.h/2)<.01,'Control text not centered')
  end end
  for i=1,12 do Scroll(i%2==1 and 1 or -1,3);Tick();Close();Tick();Open();Tick() end
  settle();homeCoherent();assert(not timer)
  local before=writes;Hover(17);advance(55);settle();homeCoherent();assert(writes==before)
  if reduce then assert(not fade and slide==0 and progress==1) end
 end
end
print('PASS: Home empty/1-5/15/1000-game shelves, bounded slots, independent paging, all-view focus, rapid hover/clicks, favorites, counts/history persistence, bad targets/data, manager return, scale extremes and ReduceMotion')
end
'''
for width,height in [(2560,1440),(3840,2160)]:
    resized=stub.replace("SCREENAREAWIDTH='2560',SCREENAREAHEIGHT='1440'",f"SCREENAREAWIDTH='{width}',SCREENAREAHEIGHT='{height}'")
    run(resized+'\n'+source+'\n'+helpers+'\n'+home_tests)

discovery_tests=r'''
-- Search and collection fixtures use only in-memory local data.
function discoveryFresh(mode,reduce,count)
 fresh(0,mode,reduce)
 fixtureLibrary='[Library]\nVersion=2\n'
 fixtureState='[State]\nView='..mode..'\nSort=custom\nFilter=all\nLastId=game001\n[Favorites]\n'
 for i=1,count do
  local platform=({'Epic','Steam','Local'})[i%3+1]
  local target=platform=='Steam' and 'steam://rungameid/'..i or platform=='Epic' and 'com.epicgames.launcher://apps/'..i or 'Z:\\Games\\game'..i..'.exe'
  local name=string.format('Game %03d',i)
  if i==1 then name='Tom Clancy\'s "Ghost": 100% [Gold]' elseif i==2 then name='Pokémon Édition' elseif i==3 then name='Straße Racer' elseif i==5 then name='[&Hub:Close()] #CURRENTCONFIG#' end
  fixtureLibrary=fixtureLibrary..string.format('[Game:game%03d]\nName=%s\nPlatform=%s\nTarget=%s\nOrder=%d\nTags=Tag %03d, %s\n',i,name,platform,target,i,i,i%2==0 and 'Co-op, Picks, co-op' or 'Solo')
  if i%2==0 then fixtureState=fixtureState..string.format('game%03d=1\n',i) end
 end
 fixtureState=fixtureState..'[History]\n'
 for i=1,count do fixtureState=fixtureState..string.format('game%03d=%d\n',i,os.time()-i) end
 inputValue='';Initialize();Boot();Open();settle()
end
function chooseTag(key)
 ShowPicker('tags')
 for i,item in ipairs(discover.pickerItems) do
  if item.key==key then discover.pickerPage=math.floor((i-1)/8)*8;drawPicker();ChoosePicker((i-1)%8+1);return end
 end
 error('Tag not found '..key)
end
function discoveryCoherent()
 focusCoherent()
 local count=0
 for i=1,24 do if slots[i] then count=count+1;assert(not hidden['Hit'..i] and matches(findGame(slots[i]))) else assert(hidden['Hit'..i]) end end
 assert(count<=24)
 if #games==0 then
  assert(selected==nil and options.HeroTitle.Text=='No matching games')
  assert(controls.HeroPlay.disabled and controls.HeroEdit.disabled and controls.HeroFavorite.disabled)
 end
 if settings.ReduceMotion=='1' then assert(not timer and not fade and slide==0) end
end
for _,reduce in ipairs({false,true}) do
 for _,mode in ipairs({'home','carousel','grid','list'}) do
  discoveryFresh(mode,reduce,200)
  local before,refreshBefore=writes,refreshes
  assert(#games==200 and #discover.tagChoices==203)
  for _,query in ipairs({'clancy\'s','"GHOST":','100%','[Gold]','pokémon édition','POKÉMON ÉDITION','STRASSE','[&Hub:Close()]','#CURRENTCONFIG#'}) do
   inputValue=query;SetSearch(query);settle();assert(#games==1,query);discoveryCoherent();assert(shown)
  end
  SetSearch('Game 01');settle();assert(#games==10);discoveryCoherent()
  SetSearch('not a game at all');settle();discoveryCoherent()
  SetSearch('');settle();assert(#games==200);discoveryCoherent()
  assert(writes==before and refreshes==refreshBefore,'Search wrote state/library or refreshed')
  -- Query AND favorites AND a collection; the platform picker remains applicable.
  selectFilter('favorites');SetSearch('Game 01');settle();assert(#games==5);discoveryCoherent()
  chooseTag('co-op');settle();assert(#games==5);discoveryCoherent()
  chooseTag('solo');settle();assert(#games==0);discoveryCoherent()
  ResetDiscovery();SetSearch('Game 01');selectFilter('steam');settle();assert(#games==4);discoveryCoherent()
  selectFilter('local');settle();assert(#games==3);discoveryCoherent()
  selectFilter('epic');settle();assert(#games==3);discoveryCoherent()
  ResetDiscovery();settle()
  -- Restore the prior visible focus/page in this view after a temporary query.
  if mode=='home' then Scroll(1,3);settle() else for i=1,3 do Scroll(1);settle() end end
  local id,page,row=selected,pageStart,homeFocusShelf
  local starts={};for i,shelf in ipairs(homeShelves) do starts[i]=shelf.start end
  SetSearch('Pokémon');settle();assert(#games==1);SetSearch('');settle()
  assert(selected==id and pageStart==page and view==mode and homeFocusShelf==row)
  for i,shelf in ipairs(homeShelves) do assert(shelf.start==starts[i]) end
  SetSearch('Game 01');settle()
  for _,other in ipairs({'home','carousel','grid','list'}) do View(other);settle();assert(#games==10);discoveryCoherent() end
  SetSearch('');settle();assert(view=='list' and #games==200);discoveryCoherent()
  -- Many tags use only eight fixed visible options, including the last page.
  ShowPicker('tags');assert(#discover.pickerItems==204)
  local id=selected;local before=writes
  Scroll(1);Favorite(1);Launch(1);Manager();Hover(1);advance(55)
  assert(selected==id and writes==before and not managerBusy and not pending and shown)
  for page=1,30 do
   local visibleOptions=0
   for i=1,8 do if not hidden['Picker'..i..'Hit'] then visibleOptions=visibleOptions+1 end end
   assert(visibleOptions<=8)
   Control('Picker1','down');local old=discover.pickerItems[discover.pickerPage+1].key
   PickerPage(1);Control('Picker1','up')
   if discover.pickerMode and discover.pickerItems[discover.pickerPage+1].key~=old then assert(discover.tagFilter=='') end
   if not discover.pickerMode then ShowPicker('tags');break end
  end
  HidePicker();ResetDiscovery();settle();discoveryCoherent()
  -- Native InputText lifetime: focus transfer, serial guard, no competing actions.
  BeginSearch();local serial=discover.searchSerial;assert(discover.searchEditing and not timer)
  assert(options.SearchInput.FocusDismiss=='1' and options.SearchInput.DefaultValue=='')
  assert(options.SearchInput.Command1:find(string.rep('[',1025)..'$UserInput$',1,true))
  local before=writes;Scroll(1);Launch(1);Favorite(1);Hero('Play');Manager();assert(writes==before and not managerBusy)
  inputValue='CLANCY\'S';SearchCommit(serial);settle();assert(#games==1 and not discover.searchEditing);discoveryCoherent()
  BeginSearch();serial=discover.searchSerial;SearchDismiss(serial);SearchCommit(serial);assert(discover.query=='CLANCY\'S')
  BeginSearch();local newer=discover.searchSerial;SearchCommit(serial);assert(discover.searchEditing)
  Close(true);SearchCommit(newer);assert(not shown and not discover.searchEditing)
  Open();settle();SetSearch('');settle();discoveryCoherent()
  BeginSearch();ReloadAndOpen();settle();assert(not discover.searchEditing)
  local lastZ;for _,command in ipairs(commands) do if command[1]=='!ZPos' then lastZ=command[2] end end;assert(lastZ==2)
  assert(refreshes==refreshBefore)
 end
end
do
 for _,schema in ipairs({'1','2','3','4'}) do
  fresh(15,'home',true);fixtureLibrary=fixtureLibrary:gsub('Version=1','Version='..schema)
  local before=writes;Initialize();Boot();Open();assert(writes==before and #games==15 and #discover.tagChoices==0)
  assert(controls.Tags.disabled);SetSearch('game 00');assert(#games==9);ResetDiscovery();assert(#games==15)
 end
 discoveryFresh('home',true,15);SetSearch('new collection');assert(#games==0)
 fixtureLibrary=fixtureLibrary:gsub('Tags=Tag 001, Solo','Tags=New collection')
 ReloadAndOpen();settle();assert(#games==1 and selected=='game001');discoveryCoherent()
 chooseTag('new collection');fixtureLibrary=fixtureLibrary:gsub('Tags=New collection','Tags=')
 ReloadAndOpen();settle();assert(discover.tagFilter=='' and #games==0);discoveryCoherent()
 SetSearch('');settle();selectFilter('favorites');SetSearch('Pokémon');assert(#games==1)
 Hero('Favorite');settle();assert(#games==0);discoveryCoherent()
end
do
 for _,scale in ipairs({'.7','1','1.5'}) do
  discoveryFresh('home',true,200);fixtureSettings='[Settings]\nUIScale='..scale..'\nReduceMotion=1\n';ReloadAndOpen()
  local c=controls.Search;assert(c.y+c.h<=objects.HeroTitle.y and c.x>=0)
  assert(controls.ResetDiscovery.x+controls.ResetDiscovery.w<W-margin)
  assert(objects.DiscoveryCount.x+tonumber(options.DiscoveryCount.W)<=W-margin+.01)
  ShowPicker('tags');assert(objects.PickerPanel.x+350*S<W and controls.PickerNext.y+controls.PickerNext.h<H)
  HidePicker();assert(not timer);discoveryCoherent()
 end
end
print('PASS: literal/Unicode search, AND filters/tags, 200-game pool, eight-choice picker, bookmarks, all views, old schemas, input callbacks and ReduceMotion')
'''
for width,height in [(2560,1440),(3840,2160)]:
    resized=stub.replace("SCREENAREAWIDTH='2560',SCREENAREAHEIGHT='1440'",f"SCREENAREAWIDTH='{width}',SCREENAREAHEIGHT='{height}'")
    run(resized+'\n'+source+'\n'+helpers+'\n'+discovery_tests)

motion_tests=r'''
local packets={}
for _,mode in ipairs({'carousel','home','grid','list'})do
 fresh(15,mode,false)
 motion.api.command=function(data)packets[#packets+1]=data;return true end
 fixtureLibrary=fixtureLibrary:gsub('Order=1\n',"Order=1\nPreviewVideo=Art/Previews/Tester's [clip].mp4\nPreviewStart=1.5\nPreviewEnd=8\nLogo=missing-logo.png\n")
 ReloadAndOpen();settle();assert(findGame('game001').previewStart=='1.5')
 local slot;for i,id in pairs(slots)do if id=='game001' then slot=i;break end end
 Hover(slot);advance(899);assert(motion.mix==0 and motion.armed)
 advance(1);assert(packets[#packets].Action=='play' and packets[#packets].Opened==1)
 MotionEvent(motion.session,tostring(motion.token),'playing');settle();assert(motion.mix==1 and not timer)
 assert(tonumber(options.BackdropA.ImageAlpha)==0 and not hidden.HeroTitle and hidden.HeroLogo)
 local old=motion.token;Leave(slot);assert(packets[#packets].Action=='pause');settle()
 assert(tonumber(options.BackdropA.ImageAlpha)==255 and motion.mix==0)
 MotionEvent(motion.session,tostring(old),'playing');assert(motion.mix==0)
 Hover(slot);advance(900);MotionEvent(motion.session,tostring(motion.token),'playing');settle()
 View(mode=='grid' and 'list' or 'grid');settle();assert(motion.mix==0 and not motion.armed);focusCoherent()
 MotionHover(1);advance(900);MotionEvent(motion.session,tostring(motion.token),'playing');settle()
 Manager();assert(motion.mix==0 and not motion.armed and managerBusy)
 Close(true);assert(not shown and not motion.opened)
 fresh(1,mode,true);motion.api.command=function(data)packets[#packets+1]=data;return true end
 findGame(selected).preview='local.mp4';motion:focus(findGame(selected));Hover(1);advance(2000);assert(not motion.armed and not timer and motion.mix==0)
end
fresh(1,'carousel',false);motion.api.command=function(data)packets[#packets+1]=data;return true end
findGame(selected).preview='local.mp4';motion:focus(findGame(selected));motionOpen();Hover(1);advance(900)
MotionEvent(motion.session,tostring(motion.token),'playing');settle();Launch(1)
assert(not shown and motion.mix==0 and not motion.opened)
fresh(1,'carousel',false)
local g=findGame(selected);g.logo='UI/Controller.png'
objects.HeroLogoProbe.GetW=function()return 320 end
objects.HeroLogoProbe.GetH=function()return 128 end
spotlight(selected,true);assert(hidden.HeroTitle and not hidden.HeroLogo)
assert(tonumber(options.HeroLogo.W)<=560*S and tonumber(options.HeroLogo.H)<=88*S)
g.preview='Art/Previews/game.mp4';spotlight(selected,true);assert(hidden.HeroTitle and motion.game.preview==g.preview)
motion.logo=nil;objects.HeroLogoProbe.GetW=function()return 0 end;objects.HeroLogoProbe.GetH=function()return 0 end
spotlight(selected,true);assert(not hidden.HeroTitle and hidden.HeroLogo,'Undecodable logo hid original text')
g.logo='missing.png';spotlight(selected,true);assert(not hidden.HeroTitle and hidden.HeroLogo)
settings.HeroCinematic='1';motion.opened=true;MotionEvent(motion.session,tostring(motion.token),'idle')
assert(options.IdleHeader.SolidColor=='5,12,19,72' and not hidden.HeroTitle)
MotionHover(1);assert(options.IdleHeader.SolidColor=='5,12,19,0')
print('PASS: actual Hub hooks, 900ms delay, metadata load, all-view fades, leave/view/Manager/launch cancellation, missing logo fallback and ReduceMotion')
'''
run(stub+'\n'+source+'\n'+helpers+'\n'+motion_tests)

button_stub=r'''
local calls={};local buttonOptions={}
local v={ROOTCONFIG='GameHUBGlass',CURRENTCONFIGX='100',CURRENTCONFIGY='200',CURRENTCONFIGWIDTH='126',CURRENTCONFIGHEIGHT='126',SCREENAREAWIDTH='3840',SCREENAREAHEIGHT='2160'}
SKIN={GetVariable=function(self,k) return v[k] end,Bang=function(self,...) local c={...};calls[#calls+1]=c;if c[1]=='!SetOption' then buttonOptions[c[2]..'.'..c[3]]=c[4] end end}
function openings() local n=0;for _,c in ipairs(calls) do if c[1]=='!ActivateConfig' then n=n+1 end end;return n end
'''
run(button_stub+'\n'+(RES/'Scripts/Button.lua').read_text(encoding='utf-8')+r'''
Control('over');assert(buttonOptions['Controller.ImageTint']=='245,255,251,255')
Control('leave');assert(openings()==0)
Click();assert(openings()==1 and buttonOptions['Controller.ImageTint']=='197,240,225,255')
assert(calls[#calls][3]=='Open(163.000,263.000)')
ReleasePress();assert(buttonOptions['Controller.ImageTint']=='220,255,242,255')
SetBusy(1);Click();Open();assert(openings()==1 and buttonOptions['ButtonHit.MouseActionCursor']=='0')
SetBusy(0);SetOpen(0);v.CURRENTCONFIGX='1500';v.CURRENTCONFIGY='600';Open()
assert(calls[#calls][3]=='Open(1563.000,663.000)' and calls[#calls][4]=='GameHUBGlass\\Main')
SetOpen(0);Control('leave');assert(buttonOptions['Controller.ImageTint']=='222,249,244,255')
print('PASS: controller hover/active/click feedback/disabled, native drag binding, and current dragged position')
''')
print('All checks used a simulated Rainmeter host. Native Windows/Rainmeter verification is still required.')
