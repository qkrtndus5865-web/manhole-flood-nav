-- 단계 4: 맨홀 적재 · 구간 스냅
--
-- 원본: 경기도 의정부시_맨홀 현황_20250630.csv (공공데이터포털)
--   20,873행 · 인코딩 CP949 · 컬럼 = 관리번호, 입력일자, 입력자, 최종수정일자, 최종수정자, 경도, 위도
--   ★ 좌표가 이미 WGS84(위경도)라 좌표계 변환이 필요 없다. SHP였다면 EPSG:5186 → 4326 변환이 필요했다.
--
-- 적재 절차 (CSV → UTF-8 변환 후 컨테이너로):
--   python -c "import io;open('manhole_utf8.csv','w',encoding='utf-8').write(open('원본.csv','rb').read().decode('cp949'))"
--   docker cp manhole_utf8.csv flood-db:/tmp/
--   docker exec -i flood-db psql -U postgres -d floodnav -v ON_ERROR_STOP=1 < sql/03_manhole.sql

DROP TABLE IF EXISTS manhole_raw;
CREATE TABLE manhole_raw (
  관리번호      text,
  입력일자      text,
  입력자        text,
  최종수정일자  text,
  최종수정자    text,
  경도          double precision,
  위도          double precision
);

\copy manhole_raw FROM '/tmp/manhole_utf8.csv' WITH (FORMAT csv, HEADER true)

TRUNCATE manhole;

INSERT INTO manhole (geom, manhole_type, src)
SELECT ST_SetSRID(ST_MakePoint(경도, 위도), 4326),   -- 경도가 먼저다
       NULL,                                          -- 종류 구분 컬럼이 원본에 없다
       '의정부시 맨홀 현황 2025-06-30'
FROM manhole_raw
WHERE 경도 BETWEEN 126.9 AND 127.2      -- 의정부 밖 좌표는 오타로 보고 버린다
  AND 위도 BETWEEN 37.6  AND 37.85;

DROP TABLE manhole_raw;

-- 가장 가까운 도로 구간에 붙인다. 15m 밖이면 보행로와 무관한 것으로 보고 붙이지 않는다.
UPDATE manhole m
SET segment_id = (
  SELECT w.gid FROM ways w
  WHERE ST_DWithin(w.the_geom::geography, m.geom::geography, 15)
  ORDER BY w.the_geom <-> m.geom
  LIMIT 1
);

-- 확인. 스냅률이 80% 밑이면 좌표나 그래프 범위를 의심할 것.
SELECT count(*) AS 전체,
       count(segment_id) AS 도로에붙음,
       round(100.0 * count(segment_id) / count(*), 1) AS 스냅률_pct
FROM manhole;
