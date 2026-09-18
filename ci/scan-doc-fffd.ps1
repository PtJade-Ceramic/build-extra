<#
.SYNOPSIS
Scans documentation trees for U+FFFD replacement characters.

.DESCRIPTION
U+FFFD, the byte sequence EF BF BD, is what a text decoder emits when it
cannot make sense of its input. Finding it in generated documentation
therefore means that some step of the pipeline (the po4a translation, the
asciidoctor conversion, or the installation of the result) produced garbage
instead of failing, which is what this check is meant to catch.

Without arguments, every git-doc directory of the installed Git for Windows is
scanned. A localized build passes the directories that were just filled in:

    scan-doc-fffd.ps1 -Root /clangarm64/share/doc/git-doc,/clangarm64/share/man

Exit codes: 0 = no U+FFFD found, 1 = U+FFFD found, 2 = nothing was checked.

.PARAMETER Root
Directories to scan recursively. When omitted, every `git-doc` directory below
the Git for Windows installation in %ProgramFiles% is scanned; scanning the
whole installation would also look at binaries, where the byte sequence can
occur by chance.

.PARAMETER Dump
Do not scan; instead report details about a single file: its size, whether it
is valid UTF-8, how many U+FFFD it contains, which charset it declares, and
the code points around the first occurrence of -Around.

.PARAMETER Around
Text to look for with -Dump. Defaults to --version.
#>

param(
	[string[]]$Root,

	[string]$Dump,

	[string]$Around = '--version'
)

# When invoked with -File, a comma-separated value arrives as a single string
# instead of an array, so split it here rather than relying on PowerShell's
# command line parsing.
if ($Root) {
	$Root = @($Root -split ',' | Where-Object { $_ -ne '' })
}

function Get-ReplacementCount {
	param([byte[]]$Bytes)

	$count = 0
	for ($i = 0; $i -lt $Bytes.Length - 2; $i++) {
		if ($Bytes[$i] -eq 0xEF -and $Bytes[$i + 1] -eq 0xBF -and $Bytes[$i + 2] -eq 0xBD) {
			$count++
		}
	}

	return $count
}

if ($Dump) {
	if (-not (Test-Path -LiteralPath $Dump)) {
		Write-Error "No such file: $Dump"
		exit 2
	}

	$bytes = [IO.File]::ReadAllBytes($Dump)
	$text = [Text.Encoding]::UTF8.GetString($bytes)
	$found = Get-ReplacementCount -Bytes $bytes

	Write-Host "path: $Dump"
	Write-Host "bytes: $($bytes.Length)"

	$strict = [Text.UTF8Encoding]::new($false, $true)
	try {
		$null = $strict.GetString($bytes)
		Write-Host 'strict-utf8: OK'
	}
	catch {
		Write-Host "strict-utf8: FAIL -> $($_.Exception.Message)"
	}

	Write-Host "U+FFFD count: $found"
	Write-Host ('meta charset: ' + [regex]::Match($text, '<meta[^>]*charset[^>]*>').Value)

	$at = $text.IndexOf($Around)
	Write-Host "index of '$Around': $at"
	if ($at -ge 0) {
		$from = [Math]::Max(0, $at - 120)
		$segment = $text.Substring($from, [Math]::Min(400, $text.Length - $from))

		Write-Host '--- raw segment ---'
		Write-Host $segment
		Write-Host '--- non-ASCII code points ---'
		foreach ($c in $segment.ToCharArray()) {
			if ([int]$c -gt 127) {
				Write-Host ('U+{0:X4}  {1}' -f [int]$c, $c)
			}
		}
	}

	if ($found -gt 0) { exit 1 }
	exit 0
}

if (-not $Root -or $Root.Count -eq 0) {
	$install = Join-Path $env:ProgramFiles 'Git'
	$Root = @(Get-ChildItem -LiteralPath $install -Recurse -Directory -Filter 'git-doc' -ErrorAction SilentlyContinue |
		Select-Object -ExpandProperty FullName)

	if ($Root.Count -eq 0) {
		Write-Warning "no git-doc directory found below $install; pass -Root to scan somewhere else"
		exit 2
	}
}

$scanned = 0
$hits = [Collections.Generic.List[string]]::new()

foreach ($dir in $Root) {
	if (-not (Test-Path -LiteralPath $dir)) {
		Write-Warning "skipping non-existent directory: $dir"
		continue
	}

	foreach ($file in (Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)) {
		$scanned++
		$found = Get-ReplacementCount -Bytes ([IO.File]::ReadAllBytes($file.FullName))
		if ($found -gt 0) {
			$hits.Add(('{0,7}  {1}' -f $found, $file.FullName))
		}
	}
}

Write-Host "scanned $scanned file(s) in: $($Root -join ', ')"

if ($scanned -eq 0) {
	Write-Warning 'nothing was scanned, so nothing was checked'
	exit 2
}

if ($hits.Count -eq 0) {
	Write-Host 'no U+FFFD replacement characters found'
	exit 0
}

Write-Host "U+FFFD replacement characters found in $($hits.Count) file(s):"
$hits | Sort-Object | ForEach-Object { Write-Host $_ }
exit 1
