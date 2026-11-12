# MOVING — TMDB 기반 OTT 스타일 웹

- **backend/**: FastAPI — TMDB API 프록시 (키는 서버에만 보관)
- **frontend/**: React + Vite — OTT 스타일 UI

## 1. TMDB 키 설정

`backend/.env` 를 열어 값을 채운다. (둘 중 하나만 있어도 됨, 둘 다 있으면 액세스 토큰 우선)

```
TMDB_API_KEY=발급받은_API_키
TMDB_ACCESS_TOKEN=발급받은_API_읽기_액세스_토큰(eyJ...)
```

## 2. 한 번에 실행 (권장)

프로젝트 루트에서:

```powershell
npm run setup   # 최초 1회: 백엔드 venv + 패키지, 프론트 패키지 설치
npm run dev     # 백엔드(8000) + 프론트(5173) 동시 실행, Ctrl+C 로 둘 다 종료
```

브라우저에서 http://localhost:5173 접속.

아래는 따로 실행하고 싶을 때의 방법이다.

## 2-1. 백엔드만 실행 (http://127.0.0.1:8000)

```powershell
cd backend
python -m venv .venv          # 최초 1회
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\uvicorn main:app --reload --port 8000
```

API 문서: http://127.0.0.1:8000/docs

| 엔드포인트 | 설명 |
| --- | --- |
| `GET /api/home` | 메인 배너 + 섹션 목록 |
| `GET /api/browse/{movie\|tv}` | 영화 / TV 탭 |
| `GET /api/detail/{movie\|tv}/{id}` | 상세 (출연진, 예고편, 비슷한 콘텐츠) |
| `GET /api/search?q=` | 통합 검색 |

## 2-2. 프론트엔드만 실행 (http://localhost:5173)

```powershell
cd frontend
npm install                   # 최초 1회
npm run dev
```

`/api` 요청은 Vite 프록시를 통해 백엔드로 전달된다.
