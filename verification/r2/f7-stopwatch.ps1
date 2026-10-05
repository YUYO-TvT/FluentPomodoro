# f7-stopwatch.ps1 -- F7: countdown must use a monotonic Stopwatch; no DateTime-based deadline in the timer path
. (Join-Path $PSScriptRoot 'lib2.ps1')
$dll = Join-Path $script:ProjRoot 'bin\Release\net8.0-windows\win-x64\FluentPomodoro.dll'
Write-Host "scanning IL of $dll"
Write-Host "dll mtime = $((Get-Item $dll).LastWriteTime)  sha256=$((Get-FileHash $dll -Algorithm SHA256).Hash.Substring(0,16))"

Write-Host "`n=== 1. source grep: every DateTime / Stopwatch reference in the app sources ==="
Get-ChildItem -Path $script:ProjRoot -Recurse -Include *.cs |
  Where-Object { $_.FullName -notmatch '\\(bin|obj|verify-dist|verify-dist-r2|dist|artifacts)\\' } |
  Select-String -Pattern 'DateTime|Stopwatch|Environment\.TickCount|GetTickCount' |
  ForEach-Object { "{0}:{1}: {2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host "`n=== 2. IL-level scan of the built assembly ==="
if (-not ('R2.IlScan' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO; using System.Linq;
using System.Reflection.Metadata; using System.Reflection.Metadata.Ecma335; using System.Reflection.PortableExecutable;
public class R2Il {
  public static List<string> Scan(string path) {
    var outLines = new List<string>();
    using var fs = File.OpenRead(path);
    using var pe = new PEReader(fs);
    var md = pe.GetMetadataReader();
    var memberNames = new Dictionary<int,string>();
    var dateTokens = new List<int>(); var stopwatchTokens = new List<int>();
    foreach (var h in md.MemberReferences) {
      var mr = md.GetMemberReference(h);
      string parent = "?";
      if (mr.Parent.Kind == HandleKind.TypeReference) {
        var tr = md.GetTypeReference((TypeReferenceHandle)mr.Parent);
        parent = md.GetString(tr.Namespace) + "." + md.GetString(tr.Name);
      } else if (mr.Parent.Kind == HandleKind.TypeSpecification) parent = "<typespec>";
      var full = parent + "::" + md.GetString(mr.Name);
      int tok = MetadataTokens.GetToken(h);
      memberNames[tok] = full;
      if (parent == "System.DateTime") dateTokens.Add(tok);
      if (parent == "System.Diagnostics.Stopwatch") stopwatchTokens.Add(tok);
    }
    outLines.Add("MEMBERREFS to System.DateTime   : " + dateTokens.Count);
    foreach (var t in dateTokens) outLines.Add("   0x" + t.ToString("X8") + " " + memberNames[t]);
    outLines.Add("MEMBERREFS to Stopwatch         : " + stopwatchTokens.Count);
    foreach (var t in stopwatchTokens) outLines.Add("   0x" + t.ToString("X8") + " " + memberNames[t]);
    outLines.Add("");
    outLines.Add("methods whose IL mentions a DateTime member-ref token:");
    bool anyDate = false;
    foreach (var th in md.TypeDefinitions) {
      var td = md.GetTypeDefinition(th);
      var tname = md.GetString(td.Namespace) + "." + md.GetString(td.Name);
      foreach (var mh in td.GetMethods()) {
        var m = md.GetMethodDefinition(mh);
        if (m.RelativeVirtualAddress == 0) continue;
        var mname = md.GetString(m.Name);
        var il = pe.GetMethodBody(m.RelativeVirtualAddress).GetILBytes();
        var hits = new List<string>();
        foreach (var t in dateTokens) if (ContainsToken(il, t)) hits.Add(memberNames[t]);
        var shits = new List<string>();
        foreach (var t in stopwatchTokens) if (ContainsToken(il, t)) shits.Add(memberNames[t]);
        if (hits.Count > 0) { anyDate = true; outLines.Add("  [DateTime] " + tname + "::" + mname + "  -> " + string.Join(", ", hits.Distinct())); }
        if (shits.Count > 0) outLines.Add("  [Stopwatch] " + tname + "::" + mname + "  -> " + string.Join(", ", shits.Distinct()));
      }
    }
    if (!anyDate) outLines.Add("  (none)");
    return outLines;
  }
  static bool ContainsToken(byte[] il, int token) {
    var p = BitConverter.GetBytes(token);
    for (int i = 0; i + 4 <= il.Length; i++) {
      if (il[i] == p[0] && il[i+1] == p[1] && il[i+2] == p[2] && il[i+3] == p[3]) return true;
    }
    return false;
  }
}
'@ -ErrorAction Stop
}
$lines = [R2Il]::Scan($dll)
$lines | ForEach-Object { Write-Host $_ }

$dateLines = @($lines | Where-Object { $_ -match '^\s*\[DateTime\]' })
$stopLines = @($lines | Where-Object { $_ -match '^\s*\[Stopwatch\]' })
Check 'no MainWindow method references System.DateTime in IL' (@($dateLines | Where-Object { $_ -match 'FluentPomodoro.MainWindow' }).Count -eq 0) ("MainWindow DateTime refs: " + (@($dateLines | Where-Object { $_ -match 'FluentPomodoro.MainWindow' }).Count))
foreach ($l in $dateLines) { Write-Host "   DateTime user: $l" }
Check 'timer methods reference Stopwatch (positive control)' (@($stopLines | Where-Object { $_ -match 'OnTick|StartTimer|PauseTimer|ResetPhaseTimers' }).Count -ge 3) ("stopwatch methods: " + (($stopLines | ForEach-Object { ($_ -split '::')[-1].Split(' ')[0] }) -join ','))

Write-Host "`n=== 3. behavioural: displayed countdown vs an independent monotonic stopwatch ==="
$today = (Get-Date).ToString('yyyy-MM-dd')
Write-Settings (@{
  FocusMinutes = 25; ShortBreakMinutes = 5; LongBreakMinutes = 15; LongBreakInterval = 4
  AutoStartNext = $false; SoundEnabled = $false; KeepScreenAwake = $false; AlwaysOnTop = $false
  NotifyOnPhaseEnd = $false; FocusLock = $false; AutoBigScreenOnFocus = $false
  Theme = 'Light'; UseMicaBackdrop = $false
  BigScreen = 'Mega'; BigScreenTopmost = $true
  HasWindowBounds = $false; WindowLeft = 0; WindowTop = 0; WindowWidth = 640; WindowHeight = 780
  StatsDate = $today; CompletedToday = 0; FocusMinutesToday = 0; TotalCompleted = 0; StreakDays = 0
  LastCompletedDate = ''
} | ConvertTo-Json)
$r = Start-App -CliArgs @('--start')
Start-Sleep -Seconds 4
$sw = [Diagnostics.Stopwatch]::StartNew()
$samples = @()
while ($sw.Elapsed.TotalSeconds -lt 40) {
  $t = Get-Title $r.Hwnd
  if ($t -match '^(\d+):(\d\d)') {
    $secs = [int]$Matches[1]*60 + [int]$Matches[2]
    $samples += [pscustomobject]@{ Mono = [math]::Round($sw.Elapsed.TotalSeconds,1); App = $secs }
  }
  Start-Sleep -Milliseconds 1500
}
Write-Host "monotonic-elapsed vs app-remaining:"
$samples | ForEach-Object { Write-Host ("   t={0,5}s  app={1,5}s" -f $_.Mono, $_.App) }
$first = $samples[0]; $last = $samples[-1]
$appDelta = $first.App - $last.App
$monoDelta = $last.Mono - $first.Mono
Check 'countdown decrements 1:1 with the monotonic clock (no drift, no jump)' ([math]::Abs($appDelta - $monoDelta) -le 1.5) "app elapsed=$appDelta s, monotonic elapsed=$([math]::Round($monoDelta,1)) s, diff=$([math]::Round($appDelta-$monoDelta,2)) s"
$monotone = $true
for ($i = 1; $i -lt $samples.Count; $i++) { if ($samples[$i].App -gt $samples[$i-1].App) { $monotone = $false } }
Check 'displayed remaining never increases' $monotone (($samples | ForEach-Object { $_.App }) -join ',')
Send-ForceQuit -Hwnd $r.Hwnd
[void](Wait-Exit -Pid2 $r.Proc.Id -Sec 8)
Write-Host "note: the system clock was NOT modified (prohibited); wall-clock-jump immunity is established by the IL/source evidence above, not by moving the clock."

Summary | Out-Null
Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
