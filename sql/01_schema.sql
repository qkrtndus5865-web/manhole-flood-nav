-- 단계 1: 스키마
--
-- 선행 조건: sql/00_build_graph.sh 를 먼저 실행해 ways / ways_vertices_pgr 가 있어야 한다.
--            (아래 두 테이블이 ways(gid) 를 참조하기 때문)
--
-- 실행: docker exec -i flood-db psql -U postgres -d floodnav -v ON_ERROR_STOP=1 < sql/01_schema.sql
--
-- 도로 그래프 테이블은 따로 만들지 않는다. osm2pgrouting 이 만든 ways 를 그대로 쓴다.
--   ways.gid       = 구간 ID        ways.the_geom = LineString(4326)
--   ways.source/target = 그래프 노드  ways.length_m = 미터
-- 39만 행을 우리 테이블로 복사해봐야 원본과 어긋날 위험만 생긴다.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;

-- 맨홀 (서울시 맨홀 전자지도, 원본 EPSG:5186 → 4326 변환 후 적재)
CREATE TABLE IF NOT EXISTS manhole (
  manhole_id   bigserial PRIMARY KEY,
  geom         geometry(Point, 4326) NOT NULL,
  manhole_type text,
  segment_id   bigint REFERENCES ways(gid),   -- 가장 가까운 도로 구간 (15m 이내)
  src          text,
  updated_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS manhole_geom_idx ON manhole USING GIST (geom);
CREATE INDEX IF NOT EXISTS manhole_segment_idx ON manhole (segment_id);

-- 침수예상구역 (도시침수 / 국가하천 / 지방하천, 빈도별)
CREATE TABLE IF NOT EXISTS flood_zone (
  flood_zone_id bigserial PRIMARY KEY,
  geom          geometry(MultiPolygon, 4326) NOT NULL,
  flood_type    text NOT NULL,   -- urban | national_river | local_river
  freq          int  NOT NULL,   -- 30/50/80/100/200/500, 기왕최대=9999
  sgg_cd        text
);
CREATE INDEX IF NOT EXISTS flood_zone_geom_idx ON flood_zone USING GIST (geom);
CREATE INDEX IF NOT EXISTS flood_zone_freq_idx ON flood_zone (freq);

-- 사전 계산된 구간별 위험도 (배치로 채움, sql/04_risk.sql)
--
-- ★ 여기에는 "사실"만 넣는다. 가중치 같은 "정책"은 넣지 않는다.
--   가중치를 여기 저장하면 계수를 조금 바꿀 때마다 39만 행을 다시 써야 하고,
--   튜닝하는 사람이 배치 담당자를 계속 기다리게 된다.
--   가중치는 route_safe() 의 파라미터다.
CREATE TABLE IF NOT EXISTS risk_segment (
  seg_id        bigint PRIMARY KEY REFERENCES ways(gid),
  min_freq      int,             -- 이 구간이 잠기기 시작하는 최저 빈도. NULL이면 안 잠김
  flood_type    text,
  manhole_count int DEFAULT 0,
  computed_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS risk_segment_minfreq_idx ON risk_segment (min_freq);
