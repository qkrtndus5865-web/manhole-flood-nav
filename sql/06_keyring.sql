-- 단계 8: 진동 키링용 경고 맨홀 목록
--
-- 실행: docker exec -i flood-db psql -U postgres -d floodnav -v ON_ERROR_STOP=1 < sql/06_keyring.sql
--
-- 키링은 맨홀 근처에서 진동한다. 그런데 "모든 맨홀"을 대상으로 하면 쓸 수가 없다.
-- GPS 오차가 3~10m 라 판정 반경을 15m 밑으로 못 내리는데, 그 반경으로 의정부를
-- 걸으면 3.4km 동안 맨홀 166 개가 걸린다. 16 초마다 울리는 셈이라 사람이 곧 무시한다.
--
--   반경 15m 안 모든 맨홀        166 개    16 초마다
--   그중 침수 구간에 있는 것        3 개    15 분마다   ← 이 뷰가 거르는 것
--
-- 그래서 침수 구간에 속한 맨홀만 남긴다. 원래 위험한 것도 이쪽이다 --
-- 물이 차면 뚜껑이 수압에 밀려 열리고, 열린 구멍이 흙탕물에 가려 안 보인다.
--
-- 판정은 도로 구간 단위다. 맨홀 좌표가 침수 폴리곤 안에 있는지 직접 보지 않고
-- 그 맨홀이 붙은 도로가 침수 구간인지를 본다. 시스템 나머지가 전부 도로 구간
-- 단위이고(cost = length_m × …), 점-다각형 판정은 요청마다 하기엔 비싸다.
-- 결과 차이도 크지 않다 (구간 기준 5,975 / 점 기준 5,168).

CREATE OR REPLACE VIEW warning_manhole AS
SELECT m.manhole_id,
       round(ST_X(m.geom)::numeric, 6) AS lon,   -- 6 자리면 약 10cm. 그 이상은 GPS 가 못 따라온다
       round(ST_Y(m.geom)::numeric, 6) AS lat,
       r.min_freq                                -- 이 값 이상의 특보에서만 경고한다
FROM manhole m
JOIN risk_segment r ON r.seg_id = m.segment_id
WHERE r.min_freq IS NOT NULL;

COMMENT ON VIEW warning_manhole IS
  '진동 키링 경고 대상. 앱이 통째로 받아 로컬에 저장하고 오프라인으로 판정한다.';

-- 앱은 이 목록을 통째로 받아 폰에 저장한다. 매번 서버에 묻지 않는다 --
-- 비 오는 날 지하도나 골목에서 신호가 약해지면 그때 경고가 멈추면 안 된다.
--
-- 특보별로 나눠 받을 필요도 없다. min_freq 를 같이 주면 앱이
--   min_freq <= 현재특보  인 것만 골라 쓰면 된다.

SELECT count(*) AS 경고대상_맨홀,
       pg_size_pretty(sum(24)::bigint) AS 전송크기_대략
FROM warning_manhole;

SELECT min_freq AS 이_특보부터_경고, count(*) AS 맨홀수
FROM warning_manhole GROUP BY 1 ORDER BY 1;
