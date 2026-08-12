-- 단계 5: 위험도 사전 계산 (배치)
--
-- 실행: docker exec -i flood-db psql -U postgres -d floodnav -v ON_ERROR_STOP=1 < sql/04_risk.sql
--
-- ★ 이 테이블에는 "사실"만 넣는다. "정책"은 넣지 않는다.
--
--   사실  = 이 길은 50년 빈도 비에 잠기고, 맨홀이 3개 있다   → 데이터가 바뀔 때만 변함
--   정책  = 그래서 얼마나 피할 것인가 (가중치)                → 튜닝할 때마다 변함
--
-- 예전에는 가중치(w_flood, w_manhole)까지 여기 저장했다. 그러면 계수를 조금만 바꿔도
-- 39만 행을 다시 써야 하고, 튜닝하는 사람이 매번 배치 담당자를 기다려야 했다.
-- 지금은 가중치를 route_safe() 의 파라미터로 뺐다. 이 배치는 데이터가 바뀔 때만 돌리면 된다.

TRUNCATE risk_segment;

INSERT INTO risk_segment (seg_id, min_freq, flood_type, manhole_count)
WITH flooded AS (
  -- 각 구간이 잠기기 시작하는 최저 빈도. 낮을수록 자주 잠긴다.
  -- (30년 빈도에 잠기는 곳은 100년 빈도에도 당연히 잠기므로 MIN 이 맞다)
  SELECT w.gid AS seg_id,
         MIN(f.freq) AS min_freq,
         (array_agg(f.flood_type ORDER BY f.freq))[1] AS flood_type
  FROM ways w
  JOIN flood_zone f ON ST_Intersects(w.the_geom, f.geom)
  GROUP BY w.gid
), mh AS (
  -- 우수·오수 맨홀만 센다. 통신·전력은 내부 수압으로 뚜껑이 밀리는 구조가 아니라 오탐만 늘린다.
  SELECT segment_id AS seg_id, count(*) AS cnt
  FROM manhole
  WHERE segment_id IS NOT NULL
    AND COALESCE(manhole_type, '우수') IN ('우수', '오수')
  GROUP BY segment_id
)
SELECT w.gid, f.min_freq, f.flood_type, COALESCE(m.cnt, 0)
FROM ways w
LEFT JOIN flooded f ON f.seg_id = w.gid
LEFT JOIN mh      m ON m.seg_id = w.gid
WHERE f.seg_id IS NOT NULL OR m.seg_id IS NOT NULL;

-- 결과 확인. 둘 다 0 이면 적재가 안 된 것이다.
SELECT count(*) FILTER (WHERE min_freq IS NOT NULL) AS 침수구간,
       count(*) FILTER (WHERE manhole_count > 0)    AS 맨홀있는구간,
       count(*)                                     AS 전체
FROM risk_segment;
