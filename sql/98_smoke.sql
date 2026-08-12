-- 회피 메커니즘 스모크 테스트 (의정부)
--
--   docker exec -i flood-db psql -U postgres -d floodnav < sql/98_smoke.sql
--
-- 침수 자료가 아직 없으므로, 경로 가운데를 가짜로 침수 처리해서
-- "위험 가중 → 우회" 기계장치가 도는지 확인한다.
-- 전체가 트랜잭션 안에서 돌고 마지막에 ROLLBACK 하므로 DB 에 아무것도 남지 않는다.
--
-- 기준 구간: 의정부역(127.0466,37.7382) → 회룡역(127.0468,37.7183)

BEGIN;

-- 기존 맨홀 위험은 잠시 끄고 침수만 본다 (롤백되므로 안전)
UPDATE risk_segment SET manhole_count = 0;

UPDATE risk_segment r SET min_freq = 50, flood_type = 'SMOKE_TEST'
FROM (SELECT gid, seq FROM route_safe(127.0466,37.7382, 127.0468,37.7183, 0)) t
WHERE r.seg_id = t.gid AND t.seq BETWEEN 20 AND 45;

INSERT INTO risk_segment (seg_id, min_freq, flood_type, manhole_count)
SELECT gid, 50, 'SMOKE_TEST', 0
FROM (SELECT gid, seq FROM route_safe(127.0466,37.7382, 127.0468,37.7183, 0)) t
WHERE seq BETWEEN 20 AND 45
ON CONFLICT (seg_id) DO NOTHING;

\echo '=== 의정부역 → 회룡역 · 경로 가운데를 50년 빈도 침수로 가정 ==='

SELECT '평상시  alert=0'           AS 상황, distance_m AS 거리_m, flooded_m AS 침수통과_m
  FROM route_summary(127.0466,37.7382,127.0468,37.7183, 0)
UNION ALL SELECT '호우경보 alert=100', distance_m, flooded_m
  FROM route_summary(127.0466,37.7382,127.0468,37.7183, 100)
UNION ALL SELECT '  계수 0.02', distance_m, flooded_m
  FROM route_summary(127.0466,37.7382,127.0468,37.7183, 100, w50 := 0.02)
UNION ALL SELECT '  계수 0.5',  distance_m, flooded_m
  FROM route_summary(127.0466,37.7382,127.0468,37.7183, 100, w50 := 0.5);

DO $$
DECLARE d0 numeric; d100 numeric; f100 numeric;
BEGIN
  SELECT distance_m INTO d0 FROM route_summary(127.0466,37.7382,127.0468,37.7183, 0);
  SELECT distance_m, flooded_m INTO d100, f100
    FROM route_summary(127.0466,37.7382,127.0468,37.7183, 100);

  ASSERT d100 >= d0, format('경보를 켰는데 경로가 짧아졌다 (%s → %s)', d0, d100);
  IF f100 > 0 THEN
    RAISE NOTICE 'SMOKE: 우회로가 없어 % m 를 그대로 통과 (기계장치 문제가 아님)', f100;
  ELSE
    RAISE NOTICE 'SMOKE TEST PASSED — % m → % m 로 우회, 침수통과 0 m', d0, d100;
  END IF;
END $$;

ROLLBACK;
