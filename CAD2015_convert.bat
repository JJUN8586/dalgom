<# : batch portion
@echo off
chcp 65001 >nul
set "TARGET=%~1"
set "BATDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8))"
goto :eof
#>

# ===== 설정 =====
$BACKUP = $false          # $true: 덮어쓰기 전 원본을 대상폴더\_백업_변환전 에 보관
$OUT_VERSION = 'ACAD2013' # AutoCAD 2013~2017 공용 포맷 (2015에서 열림)
$OK = 'AC1027','AC1024','AC1021','AC1018','AC1015','AC1014','AC1012','AC1009'  # 2015에서 이미 열리는 포맷
# ================

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$work = $null

function Get-Hdr($p) {
    $fs = [IO.File]::OpenRead($p)
    try { $b = New-Object byte[] 6; [void]$fs.Read($b, 0, 6); [Text.Encoding]::ASCII.GetString($b) }
    finally { $fs.Close() }
}

function Find-Oda {
    $c = @()
    $c += Join-Path $env:BATDIR 'ODA\ODAFileConverter.exe'
    $c += Join-Path $env:BATDIR 'ODAFileConverter.exe'
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($pf) { $c += @(Get-ChildItem "$pf\ODA\ODAFileConverter*\ODAFileConverter.exe" -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object FullName) }
    }
    foreach ($x in $c) { if (Test-Path -LiteralPath $x) { return $x } }
    throw 'ODA File Converter를 찾을 수 없습니다. .bat 옆 ODA 폴더에 넣거나 설치하세요.'
}

try {
    $src = if ($env:TARGET) { $env:TARGET } else { $env:BATDIR }
    $src = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
    Write-Host "대상 폴더: $src"
    $oda = Find-Oda
    $work = Join-Path ([IO.Path]::GetPathRoot($src)) '_CAD2015_tmp'
    $in = Join-Path $work 'in'; $out = Join-Path $work 'out'
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $in, $out | Out-Null

    $targets = @(); $skipped = 0
    $files = Get-ChildItem -LiteralPath $src -Recurse -File -Filter *.dwg |
             Where-Object { $_.FullName -notlike '*\_백업_변환전\*' }
    foreach ($f in $files) {
        $h = Get-Hdr $f.FullName
        if ($h -notmatch '^AC\d{4}$' -or $OK -contains $h) { $skipped++; continue }
        $targets += [pscustomobject]@{ File = $f; Rel = $f.FullName.Substring($src.Length).TrimStart('\'); Hdr = $h }
    }
    Write-Host "변환 대상(2015 미호환): $($targets.Count)개 / 이미 호환: $skipped개"
    if ($targets.Count -eq 0) { return }

    foreach ($t in $targets) {
        $dst = Join-Path $in $t.Rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $t.File.FullName -Destination $dst -Force
        Write-Host "  복사 [$($t.Hdr)] $($t.Rel)"
    }

    $arg = '"{0}" "{1}" {2} DWG 1 1 "*.DWG"' -f $in, $out, $OUT_VERSION
    Write-Host '변환 중... (수 분 소요)'
    $pr = Start-Process -FilePath $oda -ArgumentList $arg -Wait -PassThru
    Write-Host "ODA 종료코드: $($pr.ExitCode)"

    $ok = 0; $fail = 0
    foreach ($t in $targets) {
        $conv = Join-Path $out $t.Rel
        try {
            if (-not (Test-Path -LiteralPath $conv) -or (Get-Hdr $conv) -ne 'AC1027') { throw 'not converted' }
            if ($BACKUP) {
                $bak = Join-Path (Join-Path $src '_백업_변환전') $t.Rel
                New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
                Copy-Item -LiteralPath $t.File.FullName -Destination $bak -Force
            }
            Copy-Item -LiteralPath $conv -Destination $t.File.FullName -Force
            $ok++
        } catch {
            Write-Host "  [실패-원본유지] $($t.Rel)"
            $fail++
        }
    }
    Write-Host "덮어쓰기: 성공 $ok개 / 실패(원본 유지) $fail개"
}
catch { Write-Host "오류: $($_.Exception.Message)" }
finally {
    if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Read-Host '종료하려면 Enter를 누르세요'
}
