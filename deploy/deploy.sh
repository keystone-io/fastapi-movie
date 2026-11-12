#!/usr/bin/env bash
# 서버에서 최신 코드를 받아 Docker 컨테이너를 다시 빌드/실행한다.
# GitHub Actions 가 SSH 로 이 스크립트를 실행하며, 서버에서 직접 실행해도 된다.
#
#   bash ~/fastapi-movie/deploy/deploy.sh
#
# (스크립트 전체를 main 함수로 감싼 이유: git reset 으로 이 파일이 실행 중에
#  바뀌어도 bash 가 이미 읽어 둔 함수를 끝까지 실행하도록)
set -euo pipefail

main() {
  local app_dir="${APP_DIR:-$HOME/fastapi-movie}"
  local branch="${BRANCH:-main}"

  cd "${app_dir}"

  if [ ! -f backend/.env ]; then
    echo "!! backend/.env 가 없습니다. TMDB 키 파일을 먼저 서버에 복사하세요." >&2
    exit 1
  fi
  chmod 600 backend/.env

  echo "==> 최신 코드 받기 (${branch})"
  git fetch --prune origin "${branch}"
  git reset --hard "origin/${branch}"   # .env 는 git 이 관리하지 않으므로 유지됨
  echo "    $(git log -1 --format='%h %s')"

  echo "==> 컨테이너 빌드 및 실행"
  docker compose up -d --build --remove-orphans

  echo "==> 이전 이미지 정리"
  docker image prune -f >/dev/null

  echo "==> 헬스 체크"
  for _ in $(seq 1 30); do
    if curl -fsS http://localhost/api/health >/dev/null 2>&1; then
      docker compose ps
      echo "✅ 배포 완료: $(git log -1 --format='%h %s')"
      return 0
    fi
    sleep 3
  done

  echo "❌ 헬스 체크 실패 — 최근 로그:" >&2
  docker compose ps >&2
  docker compose logs --tail 50 >&2
  exit 1
}

main "$@"
