#!/usr/bin/env bash
# EC2(Ubuntu 22.04/24.04) 최초 1회 서버 준비 스크립트
#   - Docker Engine + Compose 플러그인 설치
#   - 2GB 스왑 추가 (t3.micro 메모리 1GB → 이미지 빌드 시 메모리 부족 방지)
#   - 프로젝트 git clone
#
# 사용법 (서버에서):
#   curl -fsSL https://raw.githubusercontent.com/keystone-io/fastapi-movie/main/deploy/setup-server.sh | bash
#   또는  bash setup-server.sh [REPO_URL]
set -euo pipefail

main() {
  local repo_url="${1:-https://github.com/keystone-io/fastapi-movie.git}"
  local app_dir="${APP_DIR:-$HOME/fastapi-movie}"

  echo "==> [1/4] 기본 패키지 설치"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl git

  echo "==> [2/4] Docker 설치"
  if ! command -v docker >/dev/null 2>&1; then
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    local codename
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    echo "    이미 설치됨: $(docker --version)"
  fi
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"

  echo "==> [3/4] 스왑 2GB"
  if ! swapon --show | grep -q '/swapfile'; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null
    sudo swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  else
    echo "    이미 설정됨"
  fi

  echo "==> [4/4] 소스 코드 받기 → ${app_dir}"
  if [ ! -d "${app_dir}/.git" ]; then
    git clone "${repo_url}" "${app_dir}"
  else
    echo "    이미 존재함"
  fi

  cat <<EOF

완료! 다음 단계:
  1) 로컬 PC에서 TMDB 키 파일 복사
       scp -i <키.pem> backend/.env ubuntu@<서버IP>:${app_dir}/backend/.env
  2) 서버에 다시 접속(docker 그룹 권한 적용)한 뒤 배포
       bash ${app_dir}/deploy/deploy.sh
EOF
}

main "$@"
