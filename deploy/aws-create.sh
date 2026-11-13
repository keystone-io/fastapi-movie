#!/usr/bin/env bash
# AWS 에 EC2 서버를 만들고 앱을 배포하는 스크립트 (로컬 PC 에서 실행)
#
#   bash deploy/aws-create.sh             # 리소스 생성 + 서버 설정 + 배포
#   bash deploy/aws-create.sh --dry-run   # 권한/설정만 확인 (아무것도 만들지 않음)
#   bash deploy/aws-create.sh --infra-only  # AWS 리소스만 만들고 서버 설정/배포는 생략
#
# 만드는 것 (모두 Project=<PROJECT> 태그):
#   키페어(<PROJECT>-key, ~/.ssh 에 .pem 저장) / 보안그룹(80, 22) / EC2(Ubuntu 24.04) / 고정 IP
#
# 필요: AWS CLI v2 + 로그인(aws login), ssh/scp, 프로젝트 루트의 backend/.env
#
# 설정은 환경변수로 바꿀 수 있다:
#   AWS_REGION(ap-southeast-2) PROJECT(fastapi-movie) INSTANCE_TYPE(t3.micro)
#   VOLUME_SIZE(20) SSH_CIDR(0.0.0.0/0) USE_EIP(true) REPO_URL(...)
#
# 참고: 이 계정은 조직 정책(SCP)으로 서울(ap-northeast-2) 리전이 막혀 있어 시드니를 기본값으로 둔다.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash 가 /dev/sda1 같은 경로를 윈도우 경로로 바꾸는 것 방지
export AWS_PAGER=""

main() {
  local mode="full"
  case "${1:-}" in
    --dry-run) mode="dry-run" ;;
    --infra-only) mode="infra" ;;
    "") ;;
    *) echo "사용법: $0 [--dry-run | --infra-only]" >&2; exit 2 ;;
  esac

  local region="${AWS_REGION:-ap-southeast-2}"
  local project="${PROJECT:-fastapi-movie}"
  local itype="${INSTANCE_TYPE:-t3.micro}"
  local vsize="${VOLUME_SIZE:-20}"
  local ssh_cidr="${SSH_CIDR:-0.0.0.0/0}"
  local use_eip="${USE_EIP:-true}"
  local repo_url="${REPO_URL:-https://github.com/keystone-io/fastapi-movie.git}"
  local key_name="${project}-key"
  local key_path="${HOME}/.ssh/${key_name}.pem"
  local sg_name="${project}-sg"
  local root_dir; root_dir="$(cd "$(dirname "$0")/.." && pwd)"
  local ec2="aws ec2 --region ${region}"
  local tags="{Key=Name,Value=${project}},{Key=Project,Value=${project}}"

  step "0. 사전 확인 (리전: ${region}, 모드: ${mode})"
  local who; who="$(aws sts get-caller-identity --query Arn --output text)" \
    || die "AWS 로그인이 필요합니다: aws login"
  echo "    계정: ${who}"
  if [ "${mode}" = "full" ] && [ ! -f "${root_dir}/backend/.env" ]; then
    die "backend/.env 가 없습니다. TMDB 키 파일을 먼저 만드세요 (backend/.env.example 참고)."
  fi

  local existing
  existing="$(${ec2} describe-instances \
    --filters "Name=tag:Project,Values=${project}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text)"
  if [ -n "${existing}" ]; then
    echo "    이미 ${project} 서버가 있습니다:"; echo "${existing}" | sed 's/^/      /'
    [ "${mode}" = "dry-run" ] || die "중복 생성을 막기 위해 중단합니다. (삭제: bash deploy/aws-destroy.sh)"
  fi

  local vpc; vpc="$(${ec2} describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
  [ "${vpc}" != "None" ] || die "기본 VPC 가 없습니다."
  local ami; ami="$(${ec2} describe-images --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
  [[ "${ami}" == ami-* ]] || die "Ubuntu 24.04 AMI 를 찾지 못했습니다."
  echo "    VPC: ${vpc} / AMI: ${ami} (Ubuntu 24.04) / 타입: ${itype} / 디스크: ${vsize}GB"

  if [ "${mode}" = "dry-run" ]; then
    step "권한 확인 (--dry-run, 실제 생성 안 함)"
    dry "키페어 생성"   ${ec2} create-key-pair --dry-run --key-name "${key_name}"
    dry "보안그룹 생성" ${ec2} create-security-group --dry-run --group-name "${sg_name}" --description test --vpc-id "${vpc}"
    dry "EC2 생성"      ${ec2} run-instances --dry-run --image-id "${ami}" --instance-type "${itype}" --count 1
    dry "고정 IP 할당"  ${ec2} allocate-address --dry-run --domain vpc
    echo; echo "dry-run 완료: 위 항목이 모두 '가능'이면 실제 실행해도 됩니다."
    return 0
  fi

  step "1. 키페어 (${key_name})"
  if ${ec2} describe-key-pairs --key-names "${key_name}" >/dev/null 2>&1; then
    [ -f "${key_path}" ] || die "AWS 에 키페어는 있는데 ${key_path} 가 없습니다. 키페어를 삭제하거나 .pem 을 복구하세요."
    echo "    기존 키페어 사용: ${key_path}"
  else
    mkdir -p "${HOME}/.ssh"
    local material
    material="$(${ec2} create-key-pair --key-name "${key_name}" --key-type ed25519 \
      --tag-specifications "ResourceType=key-pair,Tags=[${tags}]" --query KeyMaterial --output text)"
    # 윈도우 AWS CLI 출력의 CR 제거 + 마지막 줄바꿈 보장 (없으면 ssh 가 'invalid format' 오류)
    printf '%s\n' "${material}" | tr -d '\r' > "${key_path}"
    chmod 600 "${key_path}"
    echo "    생성 및 저장: ${key_path}  (분실하면 서버 접속 불가 — 안전하게 보관)"
  fi

  step "2. 보안그룹 (${sg_name}: 80=전체, 22=${ssh_cidr})"
  local sg
  sg="$(${ec2} describe-security-groups --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${vpc}" \
    --query 'SecurityGroups[0].GroupId' --output text)"
  if [ "${sg}" = "None" ]; then
    sg="$(${ec2} create-security-group --group-name "${sg_name}" --description "${project} web (80) and ssh (22)" \
      --vpc-id "${vpc}" --tag-specifications "ResourceType=security-group,Tags=[${tags}]" --query GroupId --output text)"
    ${ec2} authorize-security-group-ingress --group-id "${sg}" --ip-permissions \
      "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP}]" \
      "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${ssh_cidr},Description=SSH}]" >/dev/null
    echo "    생성: ${sg}"
  else
    echo "    기존 보안그룹 사용: ${sg}"
  fi

  step "3. EC2 생성 (${itype})"
  local iid
  iid="$(${ec2} run-instances --image-id "${ami}" --instance-type "${itype}" --count 1 \
    --key-name "${key_name}" --security-group-ids "${sg}" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${vsize},VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
    --tag-specifications "ResourceType=instance,Tags=[${tags}]" "ResourceType=volume,Tags=[${tags}]" \
    --query 'Instances[0].InstanceId' --output text)"
  [[ "${iid}" == i-* ]] || die "EC2 생성 실패: ${iid}"
  echo "    ${iid} 실행 대기 중..."
  ${ec2} wait instance-running --instance-ids "${iid}"

  local ip
  if [ "${use_eip}" = "true" ]; then
    step "4. 고정 IP 연결"
    local alloc
    alloc="$(${ec2} allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[${tags}]" \
      --query AllocationId --output text)"
    ${ec2} associate-address --instance-id "${iid}" --allocation-id "${alloc}" >/dev/null
    ip="$(${ec2} describe-addresses --allocation-ids "${alloc}" --query 'Addresses[0].PublicIp' --output text)"
    echo "    ${ip} (${alloc})"
  else
    ip="$(${ec2} describe-instances --instance-ids "${iid}" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
    echo "    고정 IP 사용 안 함 — 서버를 껐다 켜면 IP 가 바뀝니다: ${ip}"
  fi

  if [ "${mode}" = "infra" ]; then
    summary "${iid}" "${ip}" "${key_path}" "(서버 설정/배포는 생략됨: README 의 '최초 1회' 절차 참고)"
    return 0
  fi

  local ssh_opts=(-i "${key_path}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30)
  local host="ubuntu@${ip}"

  step "5. SSH 접속 대기"
  local ok=""
  for _ in $(seq 1 30); do
    if ssh "${ssh_opts[@]}" "${host}" true 2>/dev/null; then ok=1; break; fi
    sleep 5
  done
  [ -n "${ok}" ] || die "SSH 접속 실패: ssh -i ${key_path} ${host}"

  step "6. 서버 설정 (Docker, 스왑, git clone)"
  ssh "${ssh_opts[@]}" "${host}" "curl -fsSL ${repo_url%.git}/raw/main/deploy/setup-server.sh | bash -s -- ${repo_url}" \
    | grep -E '==>|완료' || true

  step "7. TMDB 키(.env) 복사"
  scp -q "${ssh_opts[@]}" "${root_dir}/backend/.env" "${host}:fastapi-movie/backend/.env"
  ssh "${ssh_opts[@]}" "${host}" 'sed -i "s/\r$//" ~/fastapi-movie/backend/.env && chmod 600 ~/fastapi-movie/backend/.env'
  echo "    완료 (권한 600)"

  step "8. 배포 (docker compose)"
  ssh "${ssh_opts[@]}" "${host}" 'bash ~/fastapi-movie/deploy/deploy.sh' | grep -E '==>|✅|❌' || true

  step "9. 외부 접속 확인"
  local code; code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://${ip}/api/health" || true)"
  echo "    http://${ip}/api/health → ${code}"

  summary "${iid}" "${ip}" "${key_path}" ""
}

summary() {
  cat <<EOF

==================================================================
 완료  →  http://$2
------------------------------------------------------------------
 EC2      : $1
 SSH      : ssh -i $3 ubuntu@$2
 $4
 GitHub 자동 배포를 쓰려면 저장소 Settings → Secrets and variables
 → Actions 에서 아래 값을 새로 입력/수정하세요:
   Secret   EC2_HOST       = $2
   Secret   EC2_USER       = ubuntu
   Secret   EC2_SSH_KEY    = $3 파일 내용 전체
   Variable DEPLOY_ENABLED = true
==================================================================
EOF
}

dry() {
  local label="$1"; shift
  local out; out="$("$@" 2>&1 || true)"
  if grep -q DryRunOperation <<<"${out}"; then echo "    ✅ ${label}: 가능"
  else echo "    ❌ ${label}: $(tail -1 <<<"${out}")"; fi
}

step() { echo; echo "==> $*"; }
die() { echo "!! $*" >&2; exit 1; }

main "$@"
