# GameDataServer

Unity 클라이언트와 HTTP·JSON 통신을 연습하기 위한 ASP.NET Core Minimal API 서버입니다.
몬스터 데이터를 SQLite에 저장하고 조회·추가·수정·삭제합니다.

서버를 독립적으로 배포하기 위해 [ServerDataLearn 저장소](https://github.com/ssa25879/ServerDataLearn.git)에서 분리했습니다.
연동하는 Unity 클라이언트와 관련 실습 자료는 기존 ServerDataLearn 저장소에서 관리합니다.

## 개발 환경과 실행

- .NET 10 SDK
- Microsoft.Data.Sqlite 10.0.13 (프로젝트 복원 시 설치)

이 폴더를 기준으로 실행합니다.

```powershell
dotnet restore
dotnet build --configuration Release
dotnet run --project GameDataServer.csproj
```

현재 실행 주소는 `Program.cs`에 지정된 `http://localhost:5000`입니다.
`launchSettings.json`이나 `--urls`로 다른 주소를 전달해도 코드에 지정된 주소가 우선합니다.

```powershell
Invoke-RestMethod http://localhost:5000/hello
Invoke-RestMethod http://localhost:5000/monsters
```

## 파일 구성

| 파일 | 용도 |
| --- | --- |
| `Program.cs` | 서버 시작, SQLite 초기화, HTTP API |
| `GameDataServer.csproj` | .NET 대상 버전과 패키지 참조 |
| `Data/monsters.json` | 초기 몬스터 데이터 |
| `Data/game.db` | 실행 중 생성·변경되는 로컬 DB |
| `appsettings.json` | 기본 로깅과 호스트 설정 |

첫 실행 시 `Data/game.db`와 테이블을 만들고, 테이블이 비어 있으면 JSON 데이터를 넣습니다.
`Data` 폴더와 `monsters.json`을 유지해야 하며, 실행 계정에 해당 폴더의 쓰기 권한이 필요합니다.
독립 저장소에서는 DB 파일을 제외하고 JSON 초기 데이터만 관리합니다.

## API

| 메서드 | 경로 | 동작 |
| --- | --- | --- |
| GET | `/hello` | 서버 확인 메시지 |
| GET | `/monsters` | 전체 목록 (`monsters` 배열을 포함한 객체) |
| GET | `/monsters/{id}` | 단일 몬스터, 없으면 404 |
| GET | `/monsters/slow?ms=3000` | 지연 응답 실습 |
| GET | `/monsters/big?count=20000` | 대용량 응답 실습 |
| POST | `/monsters` | 몬스터 추가 |
| PUT | `/monsters/{id}` | 몬스터 전체 수정 |
| PATCH | `/monsters/{id}` | 전달한 필드만 수정 |
| DELETE | `/monsters/{id}` | 몬스터 삭제 |

POST·PUT의 JSON 본문 예시입니다. PATCH는 수정할 필드만 보냅니다.

```json
{
  "name": "연습 몬스터",
  "hp": 100,
  "attack": 20,
  "speed": 2.0
}
```

## 별도 GitHub 저장소로 옮기는 순서

현재 상위 저장소 안에서 `git init`을 실행하지 않고, 필요한 파일을 새 폴더로 복사합니다.
아래 명령은 이 README가 있는 `GameDataServer` 폴더에서 실행합니다.
복사 대상 폴더가 이미 있으면 중단하므로, 필요하면 새 이름을 지정합니다.

```powershell
$destination = Join-Path (Split-Path (Get-Location).Path -Parent) 'GameDataServer-standalone'
if (Test-Path -LiteralPath $destination) { throw "대상 폴더가 이미 있습니다: $destination" }
New-Item -ItemType Directory -Path $destination | Out-Null
$files = @('.gitignore', 'README.md', 'Program.cs', 'GameDataServer.csproj',
    'GameDataServer.slnx', 'appsettings.json', 'appsettings.Development.json')
Copy-Item -LiteralPath $files -Destination $destination
New-Item -ItemType Directory -Path (Join-Path $destination 'Data') | Out-Null
Copy-Item -LiteralPath 'Data/monsters.json' -Destination (Join-Path $destination 'Data')
Copy-Item -LiteralPath 'Properties' -Destination $destination -Recurse
Set-Location -LiteralPath $destination
git init -b main
git status --short
```

이 복사는 기존 소스·DB·상위 저장소의 Git 이력을 변경하지 않습니다.
새 저장소는 기존 커밋 이력을 가져오지 않는 독립 저장소입니다.
복사 후 빌드와 실행을 확인하고, 업로드할 파일을 검토한 다음 커밋·원격 연결·푸시를 진행합니다.
GitHub 저장소 생성 시 README·라이선스·gitignore 자동 생성은 생략하면 초기 이력 충돌을 피할 수 있습니다.

상위 저장소가 이미 추적하는 `Data/game.db`는 이 `.gitignore`를 추가해도 계속 추적됩니다.
위 복사 절차에서는 DB를 복사하지 않으므로 새 저장소에는 포함되지 않습니다.

## 호스팅 배포 전 남은 작업

이 준비는 소스 저장소 분리용이며, 인터넷에서 접속 가능한 서버 배포는 별도입니다.
현재 서버는 localhost로 바인딩하고, 인증 없이 데이터 변경 API를 제공합니다.
호스팅할 때는 서비스의 포트·바인딩 설정, 접근 제어, SQLite 영구 저장소를 결정해야 합니다.
GitHub Pages는 이 ASP.NET Core 서버를 실행하는 용도로 사용할 수 없습니다.
