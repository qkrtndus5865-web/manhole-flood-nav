#!/bin/sh
# 서울 전체 보행 그래프 생성 — flood-db 컨테이너 안에서 실행한다.
#
#   docker cp data/south-korea-latest.osm.pbf flood-db:/tmp/kr.osm.pbf
#   docker cp sql/00_build_graph.sh flood-db:/tmp/
#   docker exec flood-db sh /tmp/00_build_graph.sh
#
# 결과: ways(엣지) / ways_vertices_pgr(노드) 테이블
# 실측: 엣지 399,214 / 노드 282,372 / 총연장 22,681 km / 74초
set -e

PBF=/tmp/kr.osm.pbf
BBOX=126.76,37.42,127.19,37.70          # 서울 (경도,위도 순: 서,남,동,북)
DB=floodnav
PGUSER=postgres
PGPASS=flood1234

# 자동차전용도로(motorway/trunk)를 뺀 보행 가능 도로.
# osm2pgrouting 의 mapconfig_for_pedestrian.xml 과 같은 목록이다.
TAGS=road,primary,primary_link,secondary,secondary_link,tertiary,tertiary_link,\
residential,living_street,service,track,pedestrian,services,path,cycleway,footway,\
bridleway,byway,steps,unclassified

echo "[1/5] 서울 영역 추출"
osmium extract -b $BBOX $PBF -o /tmp/seoul.osm.pbf --overwrite

echo "[2/5] 보행 가능 도로만 필터"
osmium tags-filter /tmp/seoul.osm.pbf w/highway=$TAGS -o /tmp/seoul_walk.osm.pbf --overwrite

echo "[3/5] osm2pgrouting 입력용 XML 변환"
osmium cat /tmp/seoul_walk.osm.pbf -o /tmp/seoul_walk.osm --overwrite

# 배포판 mapconfig_for_pedestrian.xml 은 XML 주석 안에 "--" 가 들어 있어 파싱에 실패한다.
# (XML 주석에는 "--" 를 쓸 수 없음) 주석 줄만 떼어내고 쓴다.
echo "[4/5] 설정 파일 정리"
grep -v '^<!--' /usr/share/osm2pgrouting/mapconfig_for_pedestrian.xml > /tmp/mapconfig_ped.xml

echo "[5/5] 그래프 생성"
osm2pgrouting -f /tmp/seoul_walk.osm -c /tmp/mapconfig_ped.xml \
  -d $DB -U $PGUSER -h localhost -p 5432 -W $PGPASS --clean

psql -U $PGUSER -d $DB -c \
  "SELECT (SELECT count(*) FROM ways) AS edges,
          (SELECT count(*) FROM ways_vertices_pgr) AS nodes,
          (SELECT round(sum(length_m)/1000) FROM ways) AS total_km;"
