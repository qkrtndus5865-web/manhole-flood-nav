-- 단계 6: 위험 가중 경로 탐색
--
-- 실행: docker exec -i flood-db psql -U postgres -d floodnav -v ON_ERROR_STOP=1 < sql/05_route.sql
--
-- 핵심 아이디어: 위험한 길은 "실제보다 길게" 보이도록 비용을 부풀린다.
--   cost = length_m * (1 + w_flood + w_manhole)
-- 100m 구간에 w_flood=2.0 이면 300m 로 읽히므로,
-- 300m 미만짜리 우회로가 있으면 다익스트라가 알아서 그쪽을 고른다.
--
-- ★ 가중치는 전부 파라미터다. 배치를 다시 돌리지 않고 호출할 때마다 바꿀 수 있다.
--   튜닝 담당자가 적재 담당자를 기다리지 않아도 된다.
--
--   SELECT * FROM route_summary(126.978,37.567, 127.028,37.498,
--                               alert_freq := 100, w100 := 3.5);

DROP FUNCTION IF EXISTS route_summary(double precision,double precision,double precision,double precision,int,double precision,double precision,double precision,double precision,double precision,double precision,double precision);
DROP FUNCTION IF EXISTS route_summary(double precision,double precision,double precision,double precision,int);
DROP FUNCTION IF EXISTS route_safe(double precision,double precision,double precision,double precision,int,double precision,double precision,double precision,double precision,double precision,double precision,double precision,double precision);
DROP FUNCTION IF EXISTS route_safe(double precision,double precision,double precision,double precision,int,double precision);
DROP FUNCTION IF EXISTS nearest_vertex(double precision,double precision);

-- 좌표에서 가장 가까운 그래프 노드를 찾는다.
-- 주의: ways_vertices_pgr 에 lon / lat 칼럼이 이미 있다. 파라미터를 lon/lat 으로 지으면
--       칼럼이 파라미터를 가려서 모든 행의 거리가 0 이 되고 엉뚱한 노드가 나온다. p_ 접두사 필수.
CREATE OR REPLACE FUNCTION nearest_vertex(p_lon double precision, p_lat double precision)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT id FROM ways_vertices_pgr
  ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION route_safe(
  lon1 double precision, lat1 double precision,
  lon2 double precision, lat2 double precision,

  -- 기상 경보 수준. 이 빈도 이하로 잠기는 구간만 위험으로 친다.
  --   0 평상시 / 50 호우주의보 / 100 호우경보 / 9999 극한호우
  alert_freq int DEFAULT 0,

  -- ── 정책 (튜닝 대상) ──
  -- 잠기는 빈도가 낮을수록 자주 잠기므로 더 크게 피한다.
  w30            double precision DEFAULT 3.0,   -- 30년 빈도 이하
  w50            double precision DEFAULT 2.5,
  w100           double precision DEFAULT 2.0,
  w200           double precision DEFAULT 1.0,
  w_else         double precision DEFAULT 0.5,   -- 500년·기왕최대 등
  w_manhole_each double precision DEFAULT 0.3,   -- 맨홀 1개당
  w_manhole_cap  double precision DEFAULT 1.5,   -- 맨홀 가중치 상한

  -- bbox 여유 (도 단위). 시청→강남역(9.4km) 실측:
  --   제한 없음(39만 엣지) 1334ms / 0.03 → 348ms / 0.015 → 103ms. 경로 결과는 셋 다 동일.
  -- ponytail: 고정값. 장거리에서 우회로를 놓치면 거리 비례로 키울 것.
  pad double precision DEFAULT 0.015
)
RETURNS TABLE (
  seq           int,
  gid           bigint,
  length_m      double precision,
  min_freq      int,
  flood_type    text,
  manhole_count int,
  risk_weight   double precision,   -- 이 구간에 실제로 적용된 가중치 합
  geom          geometry
)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  src bigint := nearest_vertex(lon1, lat1);
  dst bigint := nearest_vertex(lon2, lat2);
  -- 가중치 계산식. 엣지 쿼리와 결과 표시 양쪽에서 똑같이 쓴다.
  wexpr text := format($w$(
      CASE WHEN r.min_freq IS NULL OR r.min_freq > %1$s THEN 0
           WHEN r.min_freq <=  30 THEN %2$s
           WHEN r.min_freq <=  50 THEN %3$s
           WHEN r.min_freq <= 100 THEN %4$s
           WHEN r.min_freq <= 200 THEN %5$s
           ELSE %6$s END
    + CASE WHEN %1$s > 0
           THEN LEAST(%7$s * COALESCE(r.manhole_count, 0), %8$s) ELSE 0 END)$w$,
    alert_freq, w30, w50, w100, w200, w_else, w_manhole_each, w_manhole_cap);
  edge_sql text;
BEGIN
  -- 출발·도착을 감싸는 사각형만 그래프로 넘긴다. 서울 전체 39만 엣지를 다 읽으면 느리다.
  -- pad 가 너무 작으면 우회로가 사각형 밖에 있을 때 경로를 못 찾으니 주의.
  edge_sql := format($q$
    SELECT w.gid AS id, w.source, w.target,
           w.length_m * (1 + %1$s) AS cost,
           w.length_m * (1 + %1$s) AS reverse_cost
    FROM ways w LEFT JOIN risk_segment r ON r.seg_id = w.gid
    WHERE w.the_geom && ST_Expand(
            ST_Envelope(ST_Collect(ST_MakePoint(%2$s,%3$s), ST_MakePoint(%4$s,%5$s))), %6$s)
  $q$, wexpr, lon1, lat1, lon2, lat2, pad);

  RETURN QUERY EXECUTE format($q$
    SELECT d.seq, w.gid, w.length_m, r.min_freq, r.flood_type,
           COALESCE(r.manhole_count, 0), (%2$s)::double precision, w.the_geom
    FROM pgr_dijkstra(%1$L, %3$s, %4$s, directed := false) d
    JOIN ways w ON w.gid = d.edge
    LEFT JOIN risk_segment r ON r.seg_id = w.gid
    ORDER BY d.seq
  $q$, edge_sql, wexpr, src, dst);
END;
$fn$;

-- 경로 요약 한 줄. API 가 그대로 쓸 수 있는 형태.
CREATE OR REPLACE FUNCTION route_summary(
  lon1 double precision, lat1 double precision,
  lon2 double precision, lat2 double precision,
  alert_freq int DEFAULT 0,
  w30 double precision DEFAULT 3.0,  w50  double precision DEFAULT 2.5,
  w100 double precision DEFAULT 2.0, w200 double precision DEFAULT 1.0,
  w_else double precision DEFAULT 0.5,
  w_manhole_each double precision DEFAULT 0.3,
  w_manhole_cap  double precision DEFAULT 1.5
)
RETURNS TABLE (
  distance_m    numeric,
  flooded_m     numeric,   -- 경로 중 위험으로 판정된 구간의 길이
  manhole_count bigint,
  geometry      json
)
LANGUAGE sql STABLE AS $$
  WITH r AS (
    SELECT * FROM route_safe(lon1, lat1, lon2, lat2, alert_freq,
                             w30, w50, w100, w200, w_else,
                             w_manhole_each, w_manhole_cap)
  )
  SELECT round(sum(length_m)::numeric),
         COALESCE(round(sum(length_m) FILTER (WHERE risk_weight > 0)::numeric), 0),
         COALESCE(sum(manhole_count), 0),
         ST_AsGeoJSON(ST_LineMerge(ST_Union(geom)))::json
  FROM r;
$$;
