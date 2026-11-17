# Native cmd.exe startup checks. Stand-ins exercise WinGet and the Deno launch
# without modifying any installed packages or downloading media.
$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot '..\YouTube-Max-Windows-Trial\YouTube-Max.cmd'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('ytmax-' + [guid]::NewGuid())
$binDir = Join-Path $tempDir 'bin'
$oldPath = $env:Path
$oldLocal = $env:LOCALAPPDATA
$oldProgram = $env:ProgramFiles
$oldRoot = $env:SystemRoot
$cmdExe = $env:ComSpec
try {
    New-Item $binDir -ItemType Directory -Force | Out-Null
    $shim = Join-Path $binDir 'winget.exe'
    Add-Type -OutputAssembly $shim -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
public class Tool {
    public static int Main(string[] args) {
        string self = Assembly.GetExecutingAssembly().Location;
        string dir = Path.GetDirectoryName(self);
        string name = Path.GetFileName(self).ToLowerInvariant();
        File.AppendAllText(Path.Combine(dir, "calls"), name + " " + String.Join(" ", args)
            + " aria=" + Environment.GetEnvironmentVariable("YTMAX_ARIA2") + Environment.NewLine);
        if (name != "winget.exe") return 0;
        if (Environment.GetEnvironmentVariable("YTMAX_WINGET_FAIL") == "1") return 37;
        int id = Array.IndexOf(args, "--id");
        if (id < 0 || id + 1 >= args.Length) return 2;
        string[] files;
        switch (args[id+1]) {
            case "DenoLand.Deno": files = new[] {"deno.exe"}; break;
            case "yt-dlp.yt-dlp": files = new[] {"yt-dlp.exe"}; break;
            case "Gyan.FFmpeg": files = new[] {"ffmpeg.exe", "ffprobe.exe"}; break;
            default: return 3;
        }
        foreach (string file in files) File.Copy(self, Path.Combine(dir, file), true);
        return 0;
    }
}
'@
    # Isolate registered and portable search paths from the runner's tools.
    $env:Path = $binDir
    $env:LOCALAPPDATA = $tempDir
    $env:ProgramFiles = $tempDir
    $env:SystemRoot = $tempDir
    # A quiet stand-in keeps refresh_path from importing real machine/user PATH.
    $psDir = Join-Path $tempDir 'System32\WindowsPowerShell\v1.0'
    New-Item $psDir -ItemType Directory -Force | Out-Null
    Copy-Item $shim (Join-Path $psDir 'powershell.exe')
    function Launch([bool]$ShouldPass) {
        $output = & $cmdExe /d /c "call `"$launcher`" <nul" 2>&1
        if (($LASTEXITCODE -eq 0) -ne $ShouldPass) { throw "Unexpected launcher result: $output" }
        return @(Get-Content (Join-Path $binDir 'calls'))
    }
    $calls = Launch $true
    $installs = @($calls -like 'winget.exe install*')
    if ($installs.Count -ne 3) { throw "Expected three required installs: $installs" }
    if ($calls[-1] -notlike 'deno.exe run*aria=0' -or $calls[-1] -match 'aria2c.exe') {
        throw "Absent optional executable passed to Deno: $($calls[-1])"
    }
    $calls = Launch $true
    if (@($calls -like 'winget.exe install*').Count -ne 3) { throw 'Reinstalled available tools' }
    Copy-Item $shim (Join-Path $binDir 'aria2c.exe')
    $calls = Launch $true
    if ($calls[-1] -notlike 'deno.exe run*aria=1') { throw 'Existing aria2c was not detected' }
    Remove-Item (Join-Path $binDir 'ffprobe.exe')
    $env:YTMAX_WINGET_FAIL = '1'
    $calls = Launch $false
    if ($calls[-1] -notlike 'winget.exe install*Gyan.FFmpeg*') { throw 'Unexpected setup failure path' }
    Write-Output 'Passed: clean install, repeat launch, optional aria2c and failed FFmpeg setup.'
} finally {
    $env:Path = $oldPath
    $env:LOCALAPPDATA = $oldLocal
    $env:ProgramFiles = $oldProgram
    $env:SystemRoot = $oldRoot
    Remove-Item Env:YTMAX_WINGET_FAIL -ErrorAction SilentlyContinue
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
}
