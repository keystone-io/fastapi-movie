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

## 3. 배포 (Docker + AWS EC2 + GitHub Actions)

```
브라우저 ──80──▶ [EC2] frontend 컨테이너(Nginx) ─┬─ /      → React 빌드 결과
                                                 └─ /api/* → backend 컨테이너(FastAPI:8000) → TMDB
```

| 파일 | 역할 |
| --- | --- |
| `backend/Dockerfile` | FastAPI 이미지 |
| `frontend/Dockerfile`, `frontend/nginx.conf` | React 빌드 → Nginx 이미지, `/api` 프록시 |
| `docker-compose.yml` | 두 컨테이너 실행 (`backend/.env` 를 env_file 로 주입) |
| `deploy/setup-server.sh` | EC2 최초 1회: Docker 설치, 스왑, git clone |
| `deploy/deploy.sh` | 서버에서 최신 코드 받아 재빌드/재실행 + 헬스 체크 |
| `.github/workflows/deploy.yml` | main push 시 빌드 검사 → EC2 SSH 배포 |

### 최초 1회
1. EC2(Ubuntu 24.04) 생성, 보안그룹 22(SSH)/80(HTTP) 허용
2. 서버 접속 후 `curl -fsSL https://raw.githubusercontent.com/keystone-io/fastapi-movie/main/deploy/setup-server.sh | bash`
3. 로컬에서 키 복사: `scp -i <키.pem> backend/.env ubuntu@<서버IP>:~/fastapi-movie/backend/.env`
4. 서버 재접속 후 `bash ~/fastapi-movie/deploy/deploy.sh`

### GitHub 자동 배포 설정 (저장소 Settings → Secrets and variables → Actions)
| 종류 | 이름 | 값 |
| --- | --- | --- |
| Secret | `EC2_HOST` | 서버 공인 IP 또는 도메인 |
| Secret | `EC2_USER` | `ubuntu` |
| Secret | `EC2_SSH_KEY` | `.pem` 파일 전체 내용 |
| Variable | `DEPLOY_ENABLED` | `true` |

이후에는 **`git push` 만 하면 자동 배포**된다. (Actions 탭에서 수동 실행도 가능)
`DEPLOY_ENABLED` 가 없으면 Docker 빌드 검사만 하고 배포는 건너뛴다.
