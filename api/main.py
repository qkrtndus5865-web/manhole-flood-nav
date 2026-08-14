import os

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pg8000

app = FastAPI()

DB_CONFIG = {
    "host": os.environ.get("FLOODNAV_DB_HOST", "localhost"),
    "port": int(os.environ.get("FLOODNAV_DB_PORT", 5432)),
    "database": "floodnav",
    "user": "postgres",
    # 저장소가 공개라 비밀번호는 환경변수로 뺀다. 기본값은 로컬 개발용.
    "password": os.environ.get("FLOODNAV_DB_PASSWORD", "flood1234"),
}

ALERT = {"none": 0, "advisory": 50, "warning": 100, "extreme": 9999}


def query(sql, params=()):
    # finally 로 닫는 이유: 쿼리가 터져도 연결이 닫힌다.
    # 안 그러면 에러 날 때마다 연결이 하나씩 남아서 결국 DB 가 더 안 받아준다.
    # ponytail: 요청마다 새 연결. 커넥션 풀은 느려지면 그때 넣는다.
    conn = pg8000.connect(**DB_CONFIG)
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        return cur.fetchall()
    finally:
        conn.close()


def query_one(sql, params=()):
    rows = query(sql, params)
    return rows[0] if rows else None


class RouteReq(BaseModel):
    start: list[float]
    goal:  list[float]
    alert: str = "none"


@app.post("/v1/routes")
def create_route(req: RouteReq):
    if req.alert not in ALERT:
        raise HTTPException(status_code=400, detail="alert 값은 none/advisory/warning/extreme 중 하나여야 합니다")

    alert_freq = ALERT[req.alert]
    lon1, lat1 = req.start
    lon2, lat2 = req.goal

    try:
        row = query_one(
            "SELECT * FROM route_summary(%s, %s, %s, %s, %s)",
            (lon1, lat1, lon2, lat2, alert_freq),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"DB 연결 또는 쿼리 오류: {e}")

    # route_summary 는 경로가 없어도 집계 함수라 한 행을 준다. 값이 전부 NULL 이다.
    if row is None or row[0] is None:
        raise HTTPException(status_code=404, detail="경로를 찾을 수 없습니다")

    distance_m, flooded_m, manhole_count, geometry = row

    return {
        "path": geometry,
        "distance_m": float(distance_m),
        "alert": req.alert,
        "risk_segments": [
            {"type": "위험구간(침수+맨홀)", "length_m": float(flooded_m), "manhole_count": manhole_count}
        ]
    }


@app.get("/v1/warning-manholes")
def warning_manholes():
    """진동 키링용. 앱이 통째로 받아 폰에 저장한다. 5,975개 · 약 140KB."""
    try:
        rows = query("SELECT manhole_id, lon, lat, min_freq FROM warning_manhole")
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"DB 연결 또는 쿼리 오류: {e}")

    return [{"id": r[0], "lon": float(r[1]), "lat": float(r[2]), "min_freq": r[3]} for r in rows]
