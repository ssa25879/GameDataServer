param([string]$Configuration = 'Debug')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$projectRoot = Split-Path $PSScriptRoot -Parent
$output = Join-Path $projectRoot "bin/$Configuration/net10.0"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ranking-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$testRoot/Data" -Force | Out-Null
Get-ChildItem -LiteralPath $output | Where-Object Name -ne 'Data' | Copy-Item -Destination $testRoot -Recurse
Copy-Item -LiteralPath "$projectRoot/Data/monsters.json" -Destination "$testRoot/Data/monsters.json"
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$client = [Net.Http.HttpClient]::new()
$client.BaseAddress = [Uri]"http://localhost:$port"
$client.Timeout = [TimeSpan]::FromSeconds(15)
$script:server = $null
$script:checks = 0

function Assert-That($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Request([string]$Method, [string]$Path, [string]$Body) {
    $message = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Path)
    try {
        if ($null -ne $Body -and $Method -ne 'GET') {
            $message.Content = [Net.Http.StringContent]::new($Body, [Text.Encoding]::UTF8, 'application/json')
        }
        $response = $client.SendAsync($message).GetAwaiter().GetResult()
        try {
            $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return @{ Status = [int]$response.StatusCode; Text = $text }
        } finally { $response.Dispose() }
    } finally { $message.Dispose() }
}

function Start-TestServer {
    $previousPort = $env:PORT
    try {
        $env:PORT = "$port"
        $runId = [guid]::NewGuid().ToString('N')
        $script:server = Start-Process -FilePath (Get-Command dotnet).Source -ArgumentList @(
            ('"' + "$testRoot/GameDataServer.dll" + '"'), '--contentRoot', ('"' + $testRoot + '"')
        ) -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput "$testRoot/$runId.stdout.log" -RedirectStandardError "$testRoot/$runId.stderr.log"
    } finally { $env:PORT = $previousPort }
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($script:server.HasExited) { throw "서버 시작 실패. 로그: $testRoot" }
        try { if ((Request GET '/hello').Status -eq 200) { return } } catch { }
        Start-Sleep -Milliseconds 200
    }
    throw "서버 시작 대기 시간 초과. 로그: $testRoot"
}

function Stop-TestServer {
    if ($script:server -and -not $script:server.HasExited) {
        $script:server.Kill()
        $script:server.WaitForExit()
    }
}

try {
    Start-TestServer
    Assert-That ((Request GET '/hello').Status -eq 200) '기존 /hello 조회 실패'
    $monsters = Request GET '/monsters'
    Assert-That ($monsters.Status -eq 200 -and ($monsters.Text | ConvertFrom-Json).monsters.Count -gt 0) '기존 /monsters 조회 실패'
    $empty = Request GET '/scores'
    Assert-That ($empty.Status -eq 200) "빈 랭킹 조회는 200이어야 함. 실제: $($empty.Status)"
    Assert-That (($empty.Text | ConvertFrom-Json).scores.Count -eq 0) '빈 DB는 빈 목록이어야 함'

    $invalidBodies = @(
        '{"name":"","score":1}', '{"name":"   ","score":1}', '{"name":null,"score":1}',
        '{"score":1}', '{"name":"bad","score":-1}', '{"name":"bad"}',
        '{"name":"bad","score":null}', '{"name":"bad","score":1.5}',
        '{"name":"bad","score":"abc"}', '{"name":"bad","score":2147483648}',
        '{"name":123,"score":1}', 'null', '[]', '{'
    )
    foreach ($body in $invalidBodies) {
        $rejected = Request POST '/scores' $body
        Assert-That ($rejected.Status -eq 400) "입력 거절 상태 오류: $body -> $($rejected.Status)"
        Assert-That (-not [string]::IsNullOrWhiteSpace(($rejected.Text | ConvertFrom-Json).error)) "오류 이유 누락: $body"
    }
    Assert-That (((Request GET '/scores').Text | ConvertFrom-Json).scores.Count -eq 0) '잘못된 입력이 저장됨'

    $first = Request POST '/scores' '{"name":"  플레이어1  ","score":1200}'
    $player = $first.Text | ConvertFrom-Json
    Assert-That ($first.Status -eq 201 -and $player.id -gt 0 -and $player.name -eq '플레이어1' -and $player.score -eq 1200) '신규 등록·이름 공백 제거 실패'
    foreach ($sample in @(@{ Input = 900; Expected = 1200 }, @{ Input = 1200; Expected = 1200 }, @{ Input = 1500; Expected = 1500 })) {
        $result = Request POST '/scores' ('{"name":"플레이어1","score":' + $sample.Input + '}')
        $saved = $result.Text | ConvertFrom-Json
        Assert-That ($result.Status -eq 201 -and $saved.id -eq $player.id -and $saved.score -eq $sample.Expected) '최고 점수 또는 최초 id 유지 실패'
    }
    $second = (Request POST '/scores' '{"name":"플레이어2","score":1500}').Text | ConvertFrom-Json
    $zero = Request POST '/scores' '{"name":"zero","score":0}'
    Assert-That ($zero.Status -eq 201 -and ($zero.Text | ConvertFrom-Json).score -eq 0) '0점 등록 실패'
    $short = (Request GET '/scores').Text | ConvertFrom-Json
    Assert-That ($short.scores.Count -eq 3 -and $short.scores[0].id -eq $player.id -and $short.scores[1].id -eq $second.id) '중복 제거·동점 최초 등록 순서 실패'

    # 최고 점수 갱신 뒤에도 최초 등록 순서로 동점을 정해야 한다.
    Request POST '/scores' '{"name":"플레이어1","score":1600}' | Out-Null
    Request POST '/scores' '{"name":"플레이어2","score":1600}' | Out-Null
    for ($i = 1; $i -le 12; $i++) {
        Request POST '/scores' ('{"name":"entry' + $i + '","score":' + (100 + $i) + '}') | Out-Null
    }
    $ranking = (Request GET '/scores').Text | ConvertFrom-Json
    Assert-That ($ranking.scores.Count -eq 10) '상위 10명 제한 실패'
    Assert-That ($ranking.scores[0].name -eq '플레이어1' -and $ranking.scores[1].name -eq '플레이어2') '점수 갱신 후 동점 순서 실패'
    Assert-That ($ranking.scores[2].name -eq 'entry12' -and $ranking.scores[9].name -eq 'entry5') '점수 내림차순 정렬 실패'
    for ($i = 0; $i -lt 10; $i++) { Assert-That ($ranking.scores[$i].rank -eq $i + 1) '순위 번호 오류' }

    $tasks = @()
    $contents = @()
    foreach ($score in @(4100, 5000, 4200, 4800, 0, 4500)) {
        $content = [Net.Http.StringContent]::new(('{"name":"parallel","score":' + $score + '}'), [Text.Encoding]::UTF8, 'application/json')
        $contents += $content
        $tasks += $client.PostAsync('/scores', $content)
    }
    try {
        foreach ($task in $tasks) {
            $response = $task.GetAwaiter().GetResult()
            try { Assert-That ([int]$response.StatusCode -eq 201) '동시 등록 응답 실패' } finally { $response.Dispose() }
        }
    } finally { foreach ($content in $contents) { $content.Dispose() } }
    $parallel = @(((Request GET '/scores').Text | ConvertFrom-Json).scores | Where-Object name -eq 'parallel')
    Assert-That ($parallel.Count -eq 1 -and $parallel[0].score -eq 5000) '동시 등록 시 최고 점수 유지 실패'

    $beforeRestart = (Request GET '/scores').Text
    Stop-TestServer
    Start-TestServer
    Assert-That ((Request GET '/scores').Text -eq $beforeRestart) '재시작 후 랭킹·id 유지 실패'
    Assert-That ((Request GET '/monsters').Text -eq $monsters.Text) '기존 몬스터 데이터 변경됨'
    Write-Output "PASS: $script:checks checks (HTTP, validation, highest score, top 10, concurrency, restart, existing API)"
    Write-Output "임시 DB·서버 로그: $testRoot"
} finally {
    Stop-TestServer
    $client.Dispose()
}
