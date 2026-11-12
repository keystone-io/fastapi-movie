"""TMDB 프록시 API 서버.

프론트엔드는 TMDB를 직접 호출하지 않고 이 서버의 /api/* 만 호출한다.
(API 키가 브라우저에 노출되지 않도록)
"""

import asyncio
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Literal

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

load_dotenv(Path(__file__).parent / ".env")


def _env(name: str, default: str = "") -> str:
    value = os.getenv(name, default).strip()
    # .env 의 안내용 placeholder 는 빈 값으로 취급
    return "" if value.startswith("여기에") else value


TMDB_API_KEY = _env("TMDB_API_KEY")
TMDB_ACCESS_TOKEN = _env("TMDB_ACCESS_TOKEN")
LANGUAGE = _env("TMDB_LANGUAGE", "ko-KR")
REGION = _env("TMDB_REGION", "KR")
FRONTEND_ORIGIN = _env("FRONTEND_ORIGIN", "http://localhost:5173")

TMDB_BASE = "https://api.themoviedb.org/3"
CACHE_TTL = 60 * 10  # 10분

MediaType = Literal["movie", "tv"]

_cache: dict[str, tuple[float, Any]] = {}
client: httpx.AsyncClient


@asynccontextmanager
async def lifespan(_: FastAPI):
    global client
    headers = {"accept": "application/json"}
    if TMDB_ACCESS_TOKEN:
        headers["Authorization"] = f"Bearer {TMDB_ACCESS_TOKEN}"
    client = httpx.AsyncClient(base_url=TMDB_BASE, headers=headers, timeout=10)
    yield
    await client.aclose()


app = FastAPI(title="Movie OTT API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[FRONTEND_ORIGIN, "http://127.0.0.1:5173"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# TMDB helpers
# ---------------------------------------------------------------------------
async def tmdb(path: str, **params: Any) -> dict:
    if not (TMDB_API_KEY or TMDB_ACCESS_TOKEN):
        raise HTTPException(500, "TMDB 키가 설정되지 않았습니다. backend/.env 를 확인하세요.")

    params = {"language": LANGUAGE, **{k: v for k, v in params.items() if v is not None}}
    if not TMDB_ACCESS_TOKEN:
        params["api_key"] = TMDB_API_KEY

    key = path + "?" + "&".join(f"{k}={params[k]}" for k in sorted(params) if k != "api_key")
    hit = _cache.get(key)
    if hit and hit[0] > time.time():
        return hit[1]

    try:
        res = await client.get(path, params=params)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"TMDB 요청 실패: {e}") from e
    if res.status_code == 401:
        raise HTTPException(500, "TMDB 인증 실패: backend/.env 의 키를 확인하세요.")
    if res.status_code == 404:
        raise HTTPException(404, "콘텐츠를 찾을 수 없습니다.")
    if res.is_error:
        raise HTTPException(502, f"TMDB 오류 ({res.status_code})")

    data = res.json()
    _cache[key] = (time.time() + CACHE_TTL, data)
    return data


def normalize(item: dict, media_type: str | None = None) -> dict:
    return {
        "id": item["id"],
        "media_type": item.get("media_type") or media_type,
        "title": item.get("title") or item.get("name") or "",
        "original_title": item.get("original_title") or item.get("original_name") or "",
        "overview": item.get("overview") or "",
        "poster_path": item.get("poster_path"),
        "backdrop_path": item.get("backdrop_path"),
        "vote_average": round(item.get("vote_average") or 0, 1),
        "release_date": item.get("release_date") or item.get("first_air_date") or "",
        "genre_ids": item.get("genre_ids", []),
        "adult": item.get("adult", False),
    }


async def fetch_list(path: str, media_type: str | None = None, **params: Any) -> list[dict]:
    data = await tmdb(path, **params)
    items = [normalize(i, media_type) for i in data.get("results", [])]
    return [i for i in items if i["media_type"] in ("movie", "tv") and i["poster_path"]]


async def attach_logos(items: list[dict]) -> list[dict]:
    """히어로 배너용 타이틀 로고 이미지를 붙인다."""

    async def one(item: dict) -> dict:
        try:
            data = await tmdb(
                f"/{item['media_type']}/{item['id']}/images",
                include_image_language="ko,en,null",
            )
            logos = data.get("logos") or []
            ko = [l for l in logos if l.get("iso_639_1") == "ko"]
            item["logo_path"] = (ko or logos or [{}])[0].get("file_path")
        except HTTPException:
            item["logo_path"] = None
        return item

    return list(await asyncio.gather(*(one(i) for i in items)))


async def build_sections(specs: list[tuple]) -> list[dict]:
    """specs: (key, title, layout, coroutine) 목록 → 섹션 목록"""
    results = await asyncio.gather(*(s[3] for s in specs), return_exceptions=True)
    sections = []
    for (key, title, layout, _), items in zip(specs, results):
        if isinstance(items, Exception) or not items:
            continue
        if layout == "rank":
            items = items[:10]
        sections.append({"key": key, "title": title, "layout": layout, "items": items})
    return sections


async def hero_items(path: str, media_type: str | None = None, **params) -> list[dict]:
    items = await fetch_list(path, media_type, **params)
    items = [i for i in items if i["backdrop_path"] and i["overview"]][:8]
    return await attach_logos(items)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/api/health")
async def health():
    return {"ok": True, "tmdb_configured": bool(TMDB_API_KEY or TMDB_ACCESS_TOKEN)}


@app.get("/api/home")
async def home():
    hero = hero_items("/trending/all/day")
    sections = build_sections([
        ("top-today", "오늘의 TOP 10", "rank", fetch_list("/trending/all/day")),
        ("popular-movie", "지금 가장 인기 있는 영화", "poster", fetch_list("/movie/popular", "movie", region=REGION)),
        ("popular-tv", "놓치면 안 될 인기 시리즈", "poster", fetch_list("/tv/popular", "tv")),
        ("now-playing", "극장 상영작", "landscape", fetch_list("/movie/now_playing", "movie", region=REGION)),
        ("k-drama", "화제의 한국 드라마", "poster", fetch_list(
            "/discover/tv", "tv", with_original_language="ko", with_genres="18", sort_by="popularity.desc")),
        ("top-rated-movie", "평점 높은 명작 영화", "poster", fetch_list("/movie/top_rated", "movie")),
        ("upcoming", "공개 예정 콘텐츠", "landscape", fetch_list("/movie/upcoming", "movie", region=REGION)),
        ("animation", "애니메이션", "poster", fetch_list(
            "/discover/movie", "movie", with_genres="16", sort_by="popularity.desc")),
        ("top-rated-tv", "평점 높은 시리즈", "poster", fetch_list("/tv/top_rated", "tv")),
    ])
    hero, sections = await asyncio.gather(hero, sections)
    return {"hero": hero, "sections": sections}


MOVIE_GENRES = [(28, "액션"), (35, "코미디"), (10749, "로맨스"), (53, "스릴러"),
                (878, "SF"), (27, "공포"), (18, "드라마"), (10751, "가족")]
TV_GENRES = [(18, "드라마"), (35, "코미디"), (80, "범죄"), (10765, "SF & 판타지"),
             (16, "애니메이션"), (10764, "리얼리티"), (9648, "미스터리"), (10759, "액션 & 어드벤처")]


@app.get("/api/browse/{media_type}")
async def browse(media_type: MediaType):
    if media_type == "movie":
        hero = hero_items("/movie/popular", "movie", region=REGION)
        specs = [
            ("trending", "이번 주 인기 영화 TOP 10", "rank", fetch_list("/trending/movie/week", "movie")),
            ("now-playing", "극장 상영작", "landscape", fetch_list("/movie/now_playing", "movie", region=REGION)),
            ("upcoming", "개봉 예정작", "poster", fetch_list("/movie/upcoming", "movie", region=REGION)),
            ("top-rated", "평점 높은 영화", "poster", fetch_list("/movie/top_rated", "movie")),
        ]
        genres = MOVIE_GENRES
    else:
        hero = hero_items("/tv/popular", "tv")
        specs = [
            ("trending", "이번 주 인기 시리즈 TOP 10", "rank", fetch_list("/trending/tv/week", "tv")),
            ("k-drama", "한국 드라마", "poster", fetch_list(
                "/discover/tv", "tv", with_original_language="ko", sort_by="popularity.desc")),
            ("on-the-air", "방영 중인 시리즈", "landscape", fetch_list("/tv/on_the_air", "tv")),
            ("top-rated", "평점 높은 시리즈", "poster", fetch_list("/tv/top_rated", "tv")),
        ]
        genres = TV_GENRES

    specs += [
        (f"genre-{gid}", name, "poster", fetch_list(
            f"/discover/{media_type}", media_type, with_genres=str(gid), sort_by="popularity.desc"))
        for gid, name in genres
    ]
    hero, sections = await asyncio.gather(hero, build_sections(specs))
    return {"hero": hero, "sections": sections}


@app.get("/api/detail/{media_type}/{item_id}")
async def detail(media_type: MediaType, item_id: int):
    rating_part = "release_dates" if media_type == "movie" else "content_ratings"
    data = await tmdb(
        f"/{media_type}/{item_id}",
        append_to_response=f"videos,credits,similar,recommendations,images,{rating_part}",
        include_video_language="ko,en",
        include_image_language="ko,en,null",
    )

    # 연령 등급 (한국 기준)
    certification = ""
    if media_type == "movie":
        for r in data.get("release_dates", {}).get("results", []):
            if r["iso_3166_1"] == "KR":
                certification = next((d["certification"] for d in r["release_dates"] if d["certification"]), "")
    else:
        for r in data.get("content_ratings", {}).get("results", []):
            if r["iso_3166_1"] == "KR":
                certification = r.get("rating", "")

    videos = [v for v in data.get("videos", {}).get("results", []) if v.get("site") == "YouTube"]
    videos.sort(key=lambda v: (v.get("type") != "Trailer", v.get("iso_639_1") != "ko"))

    credits = data.get("credits", {})
    if media_type == "movie":
        directors = [c["name"] for c in credits.get("crew", []) if c.get("job") == "Director"]
    else:
        directors = [c["name"] for c in data.get("created_by", [])]

    logos = data.get("images", {}).get("logos") or []
    ko_logos = [l for l in logos if l.get("iso_639_1") == "ko"]

    related = data.get("recommendations", {}).get("results") or data.get("similar", {}).get("results") or []

    return {
        **normalize(data, media_type),
        "genres": [g["name"] for g in data.get("genres", [])],
        "runtime": data.get("runtime") or (data.get("episode_run_time") or [None])[0],
        "number_of_seasons": data.get("number_of_seasons"),
        "number_of_episodes": data.get("number_of_episodes"),
        "tagline": data.get("tagline") or "",
        "certification": certification,
        "logo_path": (ko_logos or logos or [{}])[0].get("file_path"),
        "trailer_key": videos[0]["key"] if videos else None,
        "directors": directors[:3],
        "cast": [
            {"id": c["id"], "name": c["name"], "character": c.get("character", ""),
             "profile_path": c.get("profile_path")}
            for c in credits.get("cast", [])[:12]
        ],
        "related": [i for i in (normalize(r, media_type) for r in related) if i["poster_path"]][:20],
    }


@app.get("/api/search")
async def search(q: str = Query(..., min_length=1), page: int = 1):
    data = await tmdb("/search/multi", query=q, page=page, include_adult="false")
    items = [normalize(i) for i in data.get("results", [])]
    return {
        "page": data.get("page", 1),
        "total_pages": data.get("total_pages", 1),
        "results": [i for i in items if i["media_type"] in ("movie", "tv") and i["poster_path"]],
    }
