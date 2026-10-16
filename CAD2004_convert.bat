<# : batch portion
@echo off
chcp 65001 >nul
set "TARGET=%~1"
set "BATDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8))"
goto :eof
#>

# ===== 설정 =====
$BACKUP = $true           # $true: 덮어쓰기 전 원본을 대상폴더\_백업_변환전 에 보관 (2004 다운그레이드는 정보 손실 가능 → 기본 true)
$OUT_VERSION = 'ACAD2004' # AutoCAD 2004~2006 공용 포맷 (2004에서 열림)
$OUT_HDR = 'AC1018'       # 변환 결과 파일 헤더 확인용 (ACAD2004)
$OK_MAX = 1018           # 헤더 AC1018(2004) 이하(AC1009/1012/1014/1015/1018)는 2004에서 이미 열림. AC1021(2007) 이상은 변환
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
    $work = Join-Path ([IO.Path]::GetPathRoot($src)) '_CAD2004_tmp'
    $in = Join-Path $work 'in'; $out = Join-Path $work 'out'
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $in, $out | Out-Null

    $targets = @(); $skipped = 0
    $files = Get-ChildItem -LiteralPath $src -Recurse -File -Filter *.dwg |
             Where-Object { $_.FullName -notlike '*\_백업_변환전\*' }
    foreach ($f in $files) {
        $h = Get-Hdr $f.FullName
        if ($h -notmatch '^AC\d{4}$' -or ([int]$h.Substring(2)) -le $OK_MAX) { $skipped++; continue }
        $targets += [pscustomobject]@{ File = $f; Rel = $f.FullName.Substring($src.Length).TrimStart('\'); Hdr = $h }
    }
    Write-Host "변환 대상(2004 이후 버전): $($targets.Count)개 / 이미 호환: $skipped개"
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
            if (-not (Test-Path -LiteralPath $conv) -or (Get-Hdr $conv) -ne $OUT_HDR) { throw 'not converted' }
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
