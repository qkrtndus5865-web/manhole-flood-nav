# 맨홀·침수길 회피 보행 네비

럭키신드롬 · 전남대 알엔씨 자율 프로젝트
**대상: 경기도 의정부시 전역**

비가 올 때 침수 위험 구간과 맨홀을 피해서 걷는 길을 안내한다.

```
cost = length_m × (1 + w_flood + w_manhole)
```

위험한 길이 실제보다 길어 보이게 만들면, 최단 경로 알고리즘이 스스로 피해 간다.
위험을 경로 탐색 이후에 보정하는 게 아니라 **탐색의 입력 조건으로 넣는 것**이 핵심이다.

## 문서

| | |
|---|---|
| 동작 원리 | 이 앱이 어떻게 돌아가는가 · 설계 결정과 근거 |
| 제작 가이드 | 환경 구축부터 API까지 단계별 절차 |
| `작업계획_A.md` | 데이터 담당 작업 기록 |

(문서 링크는 팀 채널 참고)

## 현재 상태

| 단계 | 상태 |
|---|---|
| 0 환경 · 1 스키마 · 2 보행 그래프 | 완료 |
| 3 침수구역 적재 | **대기 — 의정부시 침수 SHP 3종 필요** |
| 4 맨홀 적재 | 완료 — 20,873개, 스냅률 94.9% |
| 5 위험도 계산 | 맨홀만 완료 |
| 6 경로 탐색 함수 | 완료 |
| 7 API 서버 | 시작 가능 |

실측: 엣지 39,490 / 노드 29,744 / 2,760km · 경로 탐색 37ms

## 시작하기

### 1. 데이터베이스 띄우기

```powershell
docker run --name flood-db -e POSTGRES_PASSWORD=flood1234 -e POSTGRES_DB=floodnav `
  -p 5432:5432 -d pgrouting/pgrouting:latest
```

### 2. 덤프 복원 (권장)

`floodnav.dump` 를 팀 드라이브에서 받아 복원하면 아래 3~5번을 건너뛴다.

```powershell
docker cp floodnav.dump flood-db:/tmp/
docker exec flood-db pg_restore -U postgres -d floodnav /tmp/floodnav.dump
```

### 3. 처음부터 만들 경우

```powershell
# 도구 설치 (컨테이너 안)
docker exec -u root flood-db sh -c "apt-get update -qq && apt-get install -y -qq gdal-bin osmium-tool osm2pgrouting"

# OSM 원본 받기 (272MB)
curl.exe -L -C - -o south-korea-latest.osm.pbf https://download.geofabrik.de/asia/south-korea-latest.osm.pbf
docker cp south-korea-latest.osm.pbf flood-db:/tmp/kr.osm.pbf
```

그 다음 **번호 순서대로** 실행한다.

```
sql/00_build_graph.sh    보행 그래프 생성 (4.4초)
sql/01_schema.sql        테이블 3개  ← 00 다음에 실행할 것
sql/03_manhole.sql       맨홀 CSV 적재 + 15m 스냅
sql/04_risk.sql          위험도 배치
sql/05_route.sql         경로 탐색 함수
```

`01_schema.sql` 은 `ways` 를 참조하므로 **반드시 `00` 뒤에** 실행한다.

### 4. 확인

```powershell
docker exec -i flood-db psql -U postgres -d floodnav < sql/99_check.sql
docker exec -i flood-db psql -U postgres -d floodnav < sql/98_smoke.sql
```

`99_check` 는 그래프·좌표·경로·맨홀 스냅률·회피 동작을 점검한다.
`98_smoke` 는 가짜 침수 자료로 회피가 작동하는지 확인하고 자동 롤백한다.

## 쓰는 법

```sql
SELECT * FROM route_summary(127.0466, 37.7382, 127.0468, 37.7183, 100);
--                          출발경도   출발위도   도착경도   도착위도  특보
```

| 특보 | 값 |
|---|---|
| 평상시 | 0 |
| 호우주의보 | 50 |
| 호우경보 | 100 |
| 극한호우 | 9999 |

가중치는 전부 파라미터라 배치를 다시 돌리지 않고 바꿀 수 있다.

```sql
SELECT * FROM route_summary(127.0466,37.7382, 127.0468,37.7183,
                            alert_freq := 100, w100 := 3.5);
```

## 데이터는 이 저장소에 없다

용량이 크고 매번 갱신되는 파일이라 **구글 드라이브**로 공유한다.

| 파일 | 크기 | 출처 |
|---|---|---|
| `floodnav.dump` | 6.2MB | 이 파이프라인 결과물 |
| `south-korea-latest.osm.pbf` | 272MB | [Geofabrik](https://download.geofabrik.de/asia/south-korea.html) |
| 의정부시 맨홀 현황 | 936KB | 공공데이터포털 |
| 의정부시 침수 SHP | — | [홍수위험지도 포털](https://data.floodmap.go.kr) |

## 접속 정보

```
localhost:5432 · db floodnav · user postgres · pw flood1234
```

로컬 개발용이다. 배포할 때 바꾼다.
