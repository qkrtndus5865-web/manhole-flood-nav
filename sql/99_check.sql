-- 파이프라인 자체 점검 (의정부)
--   docker exec -i flood-db psql -U postgres -d floodnav -v ON_ERROR_STOP=1 < sql/99_check.sql
-- 통과하면 "ALL CHECKS PASSED", 실패하면 어디서 깨졌는지 찍고 멈춘다.
--
-- 기준 좌표: 의정부역(127.0466,37.7382) · 회룡역(127.0468,37.7183)

DO $$
DECLARE
  n_edges bigint; n_nodes bigint;
  v1 bigint; v2 bigint;
  n_seg bigint; dist numeric;
  n_mh bigint; n_snap bigint;
BEGIN
  -- 1. 그래프
  SELECT count(*) INTO n_edges FROM ways;
  SELECT count(*) INTO n_nodes FROM ways_vertices_pgr;
  ASSERT n_edges > 20000, format('엣지가 너무 적다: %s (의정부면 약 4만)', n_edges);
  ASSERT n_nodes > 15000, format('노드가 너무 적다: %s', n_nodes);
  RAISE NOTICE '[1] 그래프 OK — 엣지 %, 노드 %', n_edges, n_nodes;

  -- 2. 좌표→노드. 서로 다른 좌표는 서로 다른 노드가 나와야 한다.
  --    ways_vertices_pgr 에 lon/lat 칼럼이 있어서, 함수 파라미터를 lon/lat 으로 지으면
  --    칼럼이 파라미터를 가려 모든 좌표가 1번 노드로 나오는 버그가 있었다.
  v1 := nearest_vertex(127.0466, 37.7382);
  v2 := nearest_vertex(127.0468, 37.7183);
  ASSERT v1 <> v2, format('서로 다른 좌표가 같은 노드로 나옴 (%s). 파라미터 이름 가림 버그 재발.', v1);
  RAISE NOTICE '[2] 좌표→노드 OK — 의정부역 %, 회룡역 %', v1, v2;

  -- 3. 경로
  SELECT count(*), round(sum(length_m)::numeric) INTO n_seg, dist
    FROM route_safe(127.0466, 37.7382, 127.0468, 37.7183, 0);
  ASSERT n_seg > 0, '경로가 비었다';
  ASSERT dist BETWEEN 1500 AND 5000,
         format('의정부역→회룡역 거리가 이상하다: %s m (직선 약 2.2km 기대)', dist);
  RAISE NOTICE '[3] 경로 OK — % 구간, % m', n_seg, dist;

  -- 4. 맨홀
  SELECT count(*), count(segment_id) INTO n_mh, n_snap FROM manhole;
  IF n_mh = 0 THEN
    RAISE WARNING '[4] manhole 이 비어 있다 — 단계 4 미완료';
  ELSE
    ASSERT 100.0 * n_snap / n_mh > 80,
           format('스냅률이 %s 퍼센트로 낮다. 좌표계나 그래프 범위를 의심할 것',
                  round(100.0 * n_snap / n_mh, 1));
    -- RAISE 의 치환 기호는 % 하나다. 퍼센트 기호를 같이 쓰면 헷갈리므로 글자로 적는다.
    RAISE NOTICE '[4] 맨홀 OK — % 개 중 % 개 스냅 (% 퍼센트)',
                 n_mh, n_snap, round(100.0 * n_snap / n_mh, 1);
  END IF;

  -- 5. 침수
  IF (SELECT count(*) FROM flood_zone) = 0 THEN
    RAISE WARNING '[5] flood_zone 이 비어 있다 — 의정부시 침수 SHP 3종 필요';
  END IF;

  -- 6. 경보에 따라 경로가 바뀌는가
  IF (SELECT count(*) FROM risk_segment) > 0 THEN
    DECLARE d0 numeric; d100 numeric; m0 bigint; m100 bigint;
    BEGIN
      SELECT distance_m, manhole_count INTO d0, m0
        FROM route_summary(127.0466,37.7382,127.0468,37.7183, 0);
      SELECT distance_m, manhole_count INTO d100, m100
        FROM route_summary(127.0466,37.7382,127.0468,37.7183, 100);
      ASSERT d100 >= d0, '경보를 켰는데 경로가 짧아졌다 — 비용 계산 오류';
      ASSERT m100 <= m0, '경보를 켰는데 맨홀을 더 많이 지난다 — 비용 계산 오류';
      RAISE NOTICE '[6] 회피 OK — 평상시 % m/맨홀 % 개 → 호우경보 % m/맨홀 % 개',
                   d0, m0, d100, m100;
    END;
  ELSE
    RAISE WARNING '[6] risk_segment 가 비어 있다 — 단계 5 미완료';
  END IF;

  RAISE NOTICE 'ALL CHECKS PASSED';
END $$;
