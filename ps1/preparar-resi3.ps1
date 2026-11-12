$ErrorActionPreference = 'Stop'
try {
    $base = $PSScriptRoot
    $source = Join-Path $base 'resi3.bin'
    $dest = Join-Path $base 'resi3-partes'
    $manifestPath = Join-Path $base 'resi3-manifest.json'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Pon resi3.bin en la misma carpeta que este programa y vuelve a ejecutarlo.' }
    if ((Test-Path -LiteralPath $dest) -or (Test-Path -LiteralPath $manifestPath)) { throw 'Ya existen resi3-partes o resi3-manifest.json. Conserva esos archivos si ya terminaste. Para preparar otra copia, mueve ambos fuera de esta carpeta primero.' }
    $size = (Get-Item -LiteralPath $source).Length
    if ($size -eq 0) { throw 'resi3.bin esta vacio.' }
    if ($size -gt 900MB) { throw 'El archivo supera 900 MiB. Esta opcion esta pensada para un disco de PS1 y un sitio de menos de 1 GB.' }
    $temp = Join-Path $base ('resi3-preparando-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    $parts = [System.Collections.Generic.List[object]]::new()
    $buffer = New-Object byte[] (4MB)
    $inputStream = [System.IO.File]::OpenRead($source)
    try {
        $partIndex = 0
        while ($inputStream.Position -lt $inputStream.Length) {
            $fileName = 'resi3.{0:D3}.part' -f $partIndex
            $path = Join-Path $temp $fileName
            $remaining = [long][Math]::Min(50MB, $inputStream.Length - $inputStream.Position)
            $partBytes = $remaining
            $outputStream = [System.IO.File]::Create($path)
            try {
                while ($remaining -gt 0) {
                    $request = [int][Math]::Min($buffer.Length, $remaining)
                    $count = $inputStream.Read($buffer, 0, $request)
                    if ($count -eq 0) { throw 'La lectura se interrumpio. No se completo el disco.' }
                    $outputStream.Write($buffer, 0, $count)
                    $remaining -= $count
                }
            } finally { $outputStream.Dispose() }
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            $parts.Add([ordered]@{file=$fileName; bytes=$partBytes; sha256=$hash})
            $partIndex++
            Write-Host ('Parte {0} lista - {1:N1} MiB' -f $partIndex, ($partBytes / 1MB))
        }
    } finally { $inputStream.Dispose() }
    $manifest = [ordered]@{version=1; originalName='resi3.bin'; bytes=$size; parts=$parts.ToArray()}
    $json = ConvertTo-Json -InputObject $manifest -Depth 5
    Move-Item -LiteralPath $temp -Destination $dest
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($manifestPath, $json, $utf8)
    $ignorePath = Join-Path $base '.gitignore'
    $ignore = if (Test-Path -LiteralPath $ignorePath) { [System.IO.File]::ReadAllText($ignorePath) } else { '' }
    if (($ignore -split '\r?\n') -notcontains '/resi3.bin') {
        [System.IO.File]::WriteAllText($ignorePath, ($ignore.TrimEnd() + "`r`n/resi3.bin`r`n/resi3-preparando-*/`r`n"), $utf8)
    }
    Write-Host ''
    Write-Host 'LISTO. El BIN original se conserva y queda excluido de Git.' -ForegroundColor Green
    Write-Host 'Sube resident-evil-3.html, resi3-manifest.json, resi3-partes y .gitignore.'
    Write-Host 'Tambien necesitas tu BIOS scph5501.bin (si el juego es de America).'
    Write-Host 'No subas resi3.bin. No se ha cambiado su contenido.'
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
    exit 1
}
