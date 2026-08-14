# API 서버 (C 담당)

FastAPI + pg8000. DB 는 이미 다 돼 있으니 SQL 을 짤 필요가 없다 — 함수만 부른다.

```powershell
docker start flood-db
pip install -r requirements.txt
uvicorn main:app --reload
```

http://127.0.0.1:8000/docs 에서 바로 눌러볼 수 있다.

## 엔드포인트

### `POST /v1/routes`

```json
{ "start": [127.0466, 37.7382], "goal": [127.0468, 37.7183], "alert": "warning" }
```

| alert | 특보 | 넘어가는 값 |
|---|---|---|
| `none` | 평상시 | 0 |
| `advisory` | 호우주의보 | 50 |
| `warning` | 호우경보 | 100 |
| `extreme` | 극한호우 | 9999 |

응답의 `path` 는 GeoJSON LineString 이라 지도에 그대로 올린다.

### `GET /v1/warning-manholes`

진동 키링용 위험 맨홀 전체 목록. 5,975개 · 약 140KB. **앱이 한 번 받아 폰에 저장한다.**
매번 부르는 엔드포인트가 아니다 — 비 오는 날 골목에서 신호가 끊겨도 경고는 계속 돌아야 한다.

## 비밀번호

```powershell
$env:FLOODNAV_DB_PASSWORD = "..."
```

저장소가 공개라 코드에 안 박아둔다. 안 넘기면 로컬 개발용 기본값을 쓴다.

## 알아둘 것

- `route_summary()` 는 경로가 없어도 **한 행을 준다.** 집계 함수라 값이 전부 NULL 이다.
  그래서 행 개수가 아니라 `row[0] is None` 으로 404 를 판정한다.
- 응답의 `length_m` 은 **침수 길이가 아니라 위험 길이**다. 가중치가 붙은 구간을 다 센다 —
  침수는 없고 맨홀만 있는 구간도 들어간다. 그래서 이름표가 `위험구간(침수+맨홀)` 이다.
- 가중치 파라미터(`w30`, `m_warn` …)는 전부 기본값이 있다. 5개만 넘기면 된다.
  튜닝하고 싶으면 `route_summary(..., w100 := 3.5)` 처럼 이름을 붙여 넘긴다.
- 침수 빈도가 100년뿐인 지역에서는 `advisory`(50) 로는 침수 회피가 안 걸린다. 알려진 한계다.
