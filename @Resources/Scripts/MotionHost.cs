// Windows-only optional backend. One decoder, event-driven IPC/input, no network or frame polling.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using System.Windows.Forms.Integration;
using System.Windows.Media;
using System.Windows.Controls;

namespace GameHUBMotion {
public sealed class Host : Form {
    readonly string resources, exe, skin, config;
    readonly Timer readTimer = new Timer(), readyTimer = new Timer(), endTimer = new Timer(), idleTimer = new Timer();
    readonly Stopwatch clock = Stopwatch.StartNew();
    FileSystemWatcher watcher;
    ElementHost surface;
    MediaElement player;
    Process rainmeter;
    IntPtr main, hook;
    WinEventProc hookProc;
    string session = "", token = "", action = "", lastError = "", currentVideo = "";
    long sequence, lastActivity;
    int generation, retries, idleDelay = 10000;
    bool opened, idle, cinematic, inputRegistered, disposing, looping;
    double segmentStart, segmentEnd;

    Host(string r, string e, string s, string c) {
        resources=r;exe=e;skin=Path.GetFullPath(s);config=c;
        FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;BackColor=System.Drawing.Color.Black;
        StartPosition=FormStartPosition.Manual;
        readTimer.Interval=45;readTimer.Tick+=delegate { readTimer.Stop(); ReadCommand(); };
        readyTimer.Tick+=delegate { readyTimer.Stop(); Fail("Windows did not open this video within 8 seconds. Try the supplied 1080p test clip."); };
        endTimer.Tick+=delegate { endTimer.Stop(); Ended(generation); };
        idleTimer.Tick+=delegate { CheckIdle(); };
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { var p=base.CreateParams;p.ExStyle|=0x08000000|0x80|0x20;return p; }
    }
    public static void Run(string r,string e,string s,string c) {
        if(!File.Exists(e))throw new FileNotFoundException("Rainmeter executable was not found.",e);
        if(String.IsNullOrEmpty(c) || c.IndexOfAny(new char[]{'"','\r','\n'})>=0)throw new ArgumentException("The Rainmeter config is invalid.");
        // Per-monitor physical pixels; this is a separate process, never changes Rainmeter DPI.
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { try { SetProcessDPIAware(); } catch {} }
        using(var host=new Host(r,e,s,c)) {
            var handle=host.Handle;
            var initial=Parse(Path.Combine(r,"Motion-command.ini"));
            host.session=Value(initial,"Session");host.token=Value(initial,"Token");
            if(!host.Attach())throw new InvalidOperationException("The matching Rainmeter Main window could not be attached. Open GameHUB and reload both skins.");
            host.Status("listening","Attached to Rainmeter; waiting for a hover preview request.");
            host.watcher=new FileSystemWatcher(r,"Motion-command.ini");
            host.watcher.NotifyFilter=NotifyFilters.FileName|NotifyFilters.LastWrite|NotifyFilters.Size;
            host.watcher.SynchronizingObject=host;
            host.watcher.Changed+=delegate { host.ScheduleRead(); };
            host.watcher.Created+=delegate { host.ScheduleRead(); };
            host.watcher.Renamed+=delegate { host.ScheduleRead(); };
            host.watcher.EnableRaisingEvents=true;
            host.ScheduleRead();
            Application.Run();
        }
    }
    bool Attach() {
        EnumWindows(delegate(IntPtr h,IntPtr unused) {
            var title=new StringBuilder(32768);GetWindowText(h,title,title.Capacity);
            var cls=new StringBuilder(128);GetClassName(h,cls,cls.Capacity);
            if(cls.ToString()=="RainmeterMeterWindow" && String.Equals(title.ToString(),skin,StringComparison.OrdinalIgnoreCase)) { main=h;return false; }
            return true;
        },IntPtr.Zero);
        if(main==IntPtr.Zero) return false;
        uint pid;GetWindowThreadProcessId(main,out pid);
        rainmeter=Process.GetProcessById((int)pid);
        if(!String.Equals(Path.GetFullPath(rainmeter.MainModule.FileName),Path.GetFullPath(exe),StringComparison.OrdinalIgnoreCase)) return false;
        rainmeter.EnableRaisingEvents=true;
        rainmeter.Exited+=delegate { SafeExit(); };
        hookProc=delegate(IntPtr h,uint ev,IntPtr window,int obj,int child,uint thread,uint time) {
            if(window!=main || obj!=0) return;
            if(ev==0x8001) { SafeExit();return; }
            if(ev==0x8003) { opened=false;StopMedia();SetInput(false);idleTimer.Stop();Status("hidden","Rainmeter hid the launcher; playback stopped."); }
        };
        hook=SetWinEventHook(0x8001,0x8003,IntPtr.Zero,hookProc,pid,0,0);
        return hook!=IntPtr.Zero;
    }
    static string OneLine(string value) { return (value ?? "").Replace("\r"," ").Replace("\n"," "); }
    void Status(string phase,string detail) {
        try {
            string path=Path.Combine(resources,"Motion-status.ini"), temp=path+".new";
            var lines=new string[]{"[Motion]","Utc="+DateTime.UtcNow.ToString("o"),"Session="+session,"Token="+token,
                "Sequence="+sequence,"Phase="+phase,"Detail="+OneLine(detail),"LastError="+OneLine(lastError),"Video="+OneLine(currentVideo)};
            File.WriteAllLines(temp,lines,new UTF8Encoding(false));
            if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);
        } catch {} // No per-frame writes; a diagnostic failure must never break fallback.
    }
    void ScheduleRead() { if(disposing)return;retries=0;readTimer.Stop();readTimer.Start(); }
    static Dictionary<string,string> Parse(string path) {
        var d=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(string line in File.ReadAllLines(path,Encoding.UTF8)) {
            int i=line.IndexOf('=');if(i>0)d[line.Substring(0,i)]=line.Substring(i+1);
        }
        return d;
    }
    static string Value(Dictionary<string,string> d,string key) { string v;return d.TryGetValue(key,out v)?v:""; }
    static double Number(Dictionary<string,string> d,string key,double fallback) {
        double n;return Double.TryParse(Value(d,key),NumberStyles.Float,CultureInfo.InvariantCulture,out n) && !Double.IsNaN(n) && !Double.IsInfinity(n)?n:fallback;
    }
    void ReadCommand() {
        bool accepted=false;
        try {
            var d=Parse(Path.Combine(resources,"Motion-command.ini"));
            string nextSession=Value(d,"Session"), nextToken=Value(d,"Token");
            long seq;
            if(!Regex.IsMatch(nextSession,@"^\d{1,40}$") || !Regex.IsMatch(nextToken,@"^\d{1,20}$") ||
                !Int64.TryParse(Value(d,"Sequence"),out seq) || Value(d,"Complete")!=Value(d,"Sequence")) return;
            if(nextSession!=session) { StopMedia();session=nextSession;sequence=0;lastError=""; }
            if(seq<=sequence)return;
            sequence=seq;token=nextToken;action=Value(d,"Action");accepted=true;
            opened=Value(d,"Opened")=="1";
            cinematic=Value(d,"Cinematic")=="1";
            idleDelay=(int)Math.Max(5000,Math.Min(60000,Number(d,"IdleDelay",10000)));
            SetInput(opened && cinematic);
            if(action=="quit") { SafeExit();return; }
            if(action=="close") { opened=false;StopMedia();SetInput(false);idleTimer.Stop();idle=false;Status("closed","Launcher closed; no decoder is active.");return; }
            if(action=="open") { opened=true;Activity();SetInput(cinematic);Status("ready","Waiting for uninterrupted hover focus.");return; }
            if(action=="hide") { StopMedia();Activity();Status("stopped","Preview stopped or cancelled by the launcher.");return; }
            if(action=="pause") { readyTimer.Stop();endTimer.Stop();if(player!=null)player.Pause();Activity();Status("paused","Pointer left the selection; returning to static artwork.");return; }
            if(action=="play" && opened && IsWindowVisible(main)) Play(d);
        } catch(Exception error) { if(!accepted && ++retries<5) { readTimer.Interval=60;readTimer.Start(); } else Fail(error.ToString()); }
    }
    void Notify(string ev) {
        if(disposing || rainmeter==null || rainmeter.HasExited || !IsWindow(main) || !Regex.IsMatch(session,@"^\d{1,40}$") || !Regex.IsMatch(token,@"^\d{1,20}$")) return;
        try {
            string bang="[!CommandMeasure Hub \"MotionEvent('"+session+"','"+token+"','"+ev+"')\" \""+config+"\"]";
            // Only internal tokens/event names enter this command. Media paths stay in the INI data channel.
            var p=Process.Start(new ProcessStartInfo(exe,bang){UseShellExecute=false,CreateNoWindow=true});
            if(p!=null)p.Dispose();
        } catch { SafeExit(); }
    }
    void Play(Dictionary<string,string> d) {
        StopMedia();Activity();lastError="";currentVideo=Value(d,"Video");Status("opening","Opening the local clip in Windows MediaElement.");
        string path=currentVideo;
        if(!Path.IsPathRooted(path))path=Path.Combine(resources,path);
        path=Path.GetFullPath(path);
        string ext=Path.GetExtension(path).ToLowerInvariant();
        if(path.StartsWith(@"\\",StringComparison.Ordinal) || (ext!=".mp4" && ext!=".m4v" && ext!=".wmv") || !File.Exists(path)) { Fail("The local video is missing, inaccessible or has an unsupported file extension: "+path);return; }
        segmentStart=Math.Max(0,Number(d,"Start",0));segmentEnd=Number(d,"End",0);looping=Value(d,"Loop")=="1";
        if(segmentEnd>0 && segmentEnd<=segmentStart) { Fail("PreviewEnd must be greater than PreviewStart.");return; }
        var p=new MediaElement { LoadedBehavior=MediaState.Manual,UnloadedBehavior=MediaState.Manual,
            Stretch=Stretch.UniformToFill,IsMuted=Value(d,"Audio")!="1",Volume=Value(d,"Audio")=="1"?0.35:0,
            ScrubbingEnabled=true,Focusable=false,IsHitTestVisible=false };
        player=p;int gen=++generation;
        surface=new ElementHost { Dock=DockStyle.Fill,Child=p,Enabled=false,TabStop=false };
        Controls.Add(surface);
        p.MediaFailed+=delegate(object sender,System.Windows.ExceptionRoutedEventArgs error) { if(gen==generation)Fail(error.ErrorException==null?"Windows could not decode this clip.":error.ErrorException.ToString()); };
        p.MediaEnded+=delegate { Ended(gen); };
        p.MediaOpened+=delegate {
            if(gen!=generation || action!="play" || !opened) return;
            try {
                if(p.NaturalVideoWidth==0 || !p.NaturalDuration.HasTimeSpan || segmentStart>=p.NaturalDuration.TimeSpan.TotalSeconds) { Fail("No playable video stream/duration, or PreviewStart is past the end.");return; }
                segmentEnd=segmentEnd>0?Math.Min(segmentEnd,p.NaturalDuration.TimeSpan.TotalSeconds):p.NaturalDuration.TimeSpan.TotalSeconds;
                p.Position=TimeSpan.FromSeconds(segmentStart);p.Play();
                readyTimer.Stop();
                // Allow decoding a first frame while Rainmeter still displays opaque static artwork.
                var warm=new Timer { Interval=220 };
                warm.Tick+=delegate {
                    warm.Stop();warm.Dispose();
                    if(gen!=generation || action!="play" || !opened)return;
                    if(!PositionBehindMain()) { Fail("The visible Rainmeter Main window could not be positioned above the player.");return; }
                    Status("playing","Windows opened the clip; notifying Rainmeter to reveal it.");Notify("playing");ScheduleEnd();
                };
                warm.Start();
            } catch(Exception error) { Fail(error.ToString()); }
        };
        if(!PositionBehindMain()) { Fail("The visible Rainmeter Main window could not be positioned above the player.");return; }
        readyTimer.Interval=8000;readyTimer.Start();
        p.Source=new Uri(path,UriKind.Absolute);p.Play();
    }
    bool PositionBehindMain() {
        RECT r;
        if(!IsWindowVisible(main) || !GetWindowRect(main,out r) || r.Right<=r.Left || r.Bottom<=r.Top)return false;
        Bounds=new System.Drawing.Rectangle(r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top);
        if(!Visible) {
            if(!SetWindowPos(Handle,main,r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top,0x0010))return false;
            Show();
        }
        return SetWindowPos(Handle,main,r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top,0x0010|0x0040);
    }
    void ScheduleEnd() {
        if(player==null)return;
        double remaining=segmentEnd-player.Position.TotalSeconds;
        endTimer.Interval=(int)Math.Max(1,Math.Min(Int32.MaxValue,remaining*1000));endTimer.Start();
    }
    void Ended(int gen) {
        if(gen!=generation || player==null || action!="play")return;
        endTimer.Stop();
        if(looping) { player.Position=TimeSpan.FromSeconds(segmentStart);player.Play();ScheduleEnd(); }
        else { player.Pause();action="ended";Status("ended","Clip ended; returning to static artwork.");Notify("ended"); }
    }
    void Fail(string message) {
        lastError=message;Status("error","Playback failed; the launcher will retain static artwork.");
        try { Console.Error.WriteLine(message); } catch {}
        ++generation;readyTimer.Stop();endTimer.Stop();action="failed";
        // Keep the last frame covered until Lua restores opaque artwork and sends hide.
        try { if(player!=null)player.Pause(); } catch {}
        Notify("failed");
    }
    void StopMedia() {
        ++generation;readyTimer.Stop();endTimer.Stop();
        if(player!=null) { try { player.Close();player.Source=null; } catch {} player=null; }
        if(surface!=null) { surface.Child=null;Controls.Remove(surface);surface.Dispose();surface=null; }
        Hide();
    }
    void Activity() {
        lastActivity=clock.ElapsedMilliseconds;
        if(idle) { idle=false;Notify("activity"); }
        if(opened && cinematic && !idleTimer.Enabled) { idleTimer.Interval=idleDelay;idleTimer.Start(); }
    }
    void CheckIdle() {
        idleTimer.Stop();if(!opened || !cinematic)return;
        long remaining=idleDelay-(clock.ElapsedMilliseconds-lastActivity);
        if(remaining>0) { idleTimer.Interval=(int)Math.Max(1,remaining);idleTimer.Start(); }
        else { idle=true;Notify("idle"); }
    }
    void SetInput(bool enabled) {
        if(enabled==inputRegistered)return;
        var devices=new RAWINPUTDEVICE[2];
        for(int i=0;i<2;i++) { devices[i].Page=1;devices[i].Usage=(ushort)(i==0?2:6);devices[i].Flags=enabled?0x100u:1u;devices[i].Target=enabled?Handle:IntPtr.Zero; }
        if(RegisterRawInputDevices(devices,2,(uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))inputRegistered=enabled;
    }
    protected override void WndProc(ref Message message) {
        // WinForms Show() can request a top Z-order even with ShowWithoutActivation.
        // Keep every positioning request below Main, so showing a player cannot steal hover.
        if(message.Msg==0x0046 && message.LParam!=IntPtr.Zero && main!=IntPtr.Zero && IsWindow(main)) {
            var position=(WINDOWPOS)Marshal.PtrToStructure(message.LParam,typeof(WINDOWPOS));
            position.After=main;position.Flags=(position.Flags|0x0010u)&~0x0004u;
            Marshal.StructureToPtr(position,message.LParam,false);
        }
        if(message.Msg==0x84) { message.Result=new IntPtr(-1);return; } // HTTRANSPARENT
        if(message.Msg==0x00FF && opened)Activity(); // Notification only; never read key codes or input payloads.
        base.WndProc(ref message);
    }
    void SafeExit() {
        if(disposing)return;
        if(InvokeRequired) { try { BeginInvoke(new Action(SafeExit)); } catch {} return; }
        StopMedia();SetInput(false);Status("exited","Main unloaded or Rainmeter exited; helper is stopping.");disposing=true;
        if(hook!=IntPtr.Zero) { UnhookWinEvent(hook);hook=IntPtr.Zero; }
        Application.ExitThread();
    }
    protected override void Dispose(bool disposingManaged) {
        if(disposingManaged) {
            StopMedia();SetInput(false);disposing=true;
            if(hook!=IntPtr.Zero)UnhookWinEvent(hook);
            if(watcher!=null)watcher.Dispose();
            readTimer.Dispose();readyTimer.Dispose();endTimer.Dispose();idleTimer.Dispose();
            if(rainmeter!=null)rainmeter.Dispose();
        }
        base.Dispose(disposingManaged);
    }
    [StructLayout(LayoutKind.Sequential)] struct WINDOWPOS { public IntPtr Window,After;public int X,Y,Width,Height;public uint Flags; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort Page,Usage;public uint Flags;public IntPtr Target; }
    delegate bool EnumProc(IntPtr h,IntPtr l);
    delegate void WinEventProc(IntPtr hook,uint ev,IntPtr hwnd,int obj,int child,uint thread,uint time);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p,IntPtr l);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder b,int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint from,uint to,IntPtr module,WinEventProc proc,uint process,uint thread,uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr h);
    [DllImport("user32.dll")] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices,uint n,uint size);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
}
}
