# 랭킹 API와 Unity 실행 안내

## 서버 실행

```powershell
dotnet run --project GameDataServer.csproj
```

기본 주소는 `http://localhost:5000`이다. `PORT` 환경변수가 있으면 해당 포트를 사용한다. 기존 몬스터 API는 유지했다.

## 점수 등록

`POST /scores`, `Content-Type: application/json`

```json
{"name":"플레이어1","score":1200}
```

성공 시 201과 최종 저장된 최고 점수를 반환한다.

```json
{"id":1,"name":"플레이어1","score":1200}
```

- 이름 앞뒤 공백을 제거한다. 빈 이름·공백만 있는 이름은 거절한다.
- 이름은 공백 제거 후 정확히 비교한다. 대소문자를 구분하며 별도 유니코드 정규화는 하지 않는다. 이름 길이·허용 문자 제한은 추가하지 않았다.
- 점수는 0~2,147,483,647 정수다. 이름·점수 누락, null, 잘못된 타입·JSON은 거절한다.
- 처음 보는 이름은 추가한다. 같은 이름의 높은 점수는 갱신하고, 같거나 낮은 점수는 기존 최고 점수를 유지한다.
- 모든 유효한 등록 요청은 명세에 맞춰 201을 반환한다. 기존 이름의 경우에도 id를 유지하고 저장된 최고 점수를 반환한다.
- `Location`은 조회 가능한 목록 주소 `/scores`다. 개별 점수 조회 API는 추가하지 않았다.

잘못된 입력은 400과 이유를 반환하며 저장하지 않는다.

```json
{"error":"이름을 입력하세요."}
```

```json
{"error":"점수는 0 이상이어야 합니다."}
```

PowerShell 예시:

```powershell
$body = @{ name = '플레이어1'; score = 1200 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:5000/scores `
    -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
```

## 랭킹 조회

`GET /scores`, 성공 시 200.

```json
{"scores":[{"rank":1,"id":1,"name":"플레이어1","score":1200},{"rank":2,"id":2,"name":"플레이어2","score":1200}]}
```

점수 내림차순으로 최대 10명을 반환한다. 동점은 최초 등록 id 오름차순이며 순위는 1부터 연속으로 부여한다. 최고 점수를 갱신해도 최초 등록 순서는 유지한다. 빈 DB는 `{"scores":[]}`를 반환한다.

```powershell
Invoke-RestMethod http://localhost:5000/scores
```

## Unity 사용 순서

Unity 프로젝트는 `D:\lecture\MonsterDex`다. 기존 SampleScene과 MonsterClientAsync 수정은 보존하고 다음 파일만 새로 추가했다.

- `Assets/Scripts/RankingClient.cs`: 등록·조회, JSON 모델, 오류 표시, 중복 클릭 방지.
- `Assets/Editor/RankingSceneSetup.cs`: 기존 uGUI·TextMeshPro와 한국어 폰트를 사용해 독립 랭킹 씬을 만드는 메뉴.
- 각 스크립트의 `.meta`, 새 `Editor` 폴더의 `.meta`.

1. Unity가 스크립트를 임포트한 뒤 Play 모드가 아닌 상태에서 `Tools > Ranking > Create Ranking Scene`을 선택한다.
2. 기본 파일명 `RankingScene`으로 새 씬을 저장한다. 기존 경로는 덮어쓰지 않는다.
3. 생성한 씬을 단독으로 연다. 생성 과정에서는 기존 씬을 보존하기 위해 Additive로 열기 때문에 그대로 Play하면 EventSystem이 중복될 수 있다.
4. `RankingCanvas`의 `RankingClient > Server Base Url`을 서버 기본 주소로 설정한다. `/scores`는 자동으로 붙인다.
5. 서버 실행 후 Play하여 이름·점수 입력 → 점수 전송 → 상위 10명 조회를 확인한다.

화면에는 이름·점수 입력, 전송·조회 버튼, 요청 상태, 순위·이름·점수가 표시된다. 등록 성공 뒤 조회만 실패하면 저장 성공과 목록 조회 실패를 구분한다. 네트워크 요청 제한 시간은 15초다.

폰에서 `localhost`는 폰 자신을 뜻한다. 외부 기기에서는 접속 가능한 서버 주소를 사용해야 한다. 배포 주소에는 이번 서버 변경이 아직 배포되지 않았다.

생성된 씬과 Inspector 연결을 확인했고, Full HD Game 뷰에서 제목·Placeholder·버튼·안내 문구가 표시되는 것을 확인했다. Play 모드의 등록·조회 동작은 아직 확인하지 않았다. Build
Settings는 변경하지 않았으므로 빌드에 포함할 씬은 실제 검증 후 별도로 결정한다.

가로 화면에서 글자가 사라졌던 문제는 Canvas Scaler의 Match를 높이 기준 1로 바꾸고 제목의 Preferred Height를 56에서 72로 늘려 해결했다. 화면 세로 공간이 부족해 글자 영역이
줄어들면서 Ellipsis 처리로 숨겨지는 현상이었다. 폰트와 색상은 유지했으며 현재 씬과 새 씬 생성 코드에 반영했다.

## 검증 명령과 범위

```powershell
dotnet build GameDataServer.csproj --no-restore
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Ranking.Smoke.ps1
```

회귀 스크립트는 빌드 결과를 임시 폴더로 복사하고 새 SQLite DB와 별도 포트로 서버를 실행한다. 원본 DB를 수정하지 않는다. 임시 DB와 로그 위치를 출력하며, 종료 시 스크립트가 시작한 서버만 정지한다.

확인한 결과: 빌드 경고·오류 0개, HTTP 회귀 검사 61개 통과. 입력 거절, 최고 점수, 동점, 상위 10명, 동시 등록, 재시작 및 기존 조회 API를 검사했다.

Unity 신규 두 스크립트는 기존 프로젝트의 DLL 참조를 사용한 C# 컴파일을 통과했다. 이는 Unity Editor 임포트·씬 실행 검증을 대신하지 않는다.

남은 확인: 실제 Unity 연동 (A1·A3), 배포 환경의 SQLite 영속 저장 경로, 외부 네트워크 등록·조회 (A5), 배포 재시작·재배포 시 데이터 보존. 삭제·개별 수정·내 순위 API는 구현하지
않았다.
