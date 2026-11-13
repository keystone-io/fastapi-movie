#!/usr/bin/env bash
# aws-create.sh 로 만든 AWS 리소스를 모두 삭제하는 스크립트 (로컬 PC 에서 실행)
#
#   bash deploy/aws-destroy.sh --dry-run   # 삭제 대상만 보여줌 (아무것도 지우지 않음)
#   bash deploy/aws-destroy.sh             # 확인 문구 입력 후 삭제
#   bash deploy/aws-destroy.sh --yes       # 확인 없이 삭제
#
# 삭제 대상: Project=<PROJECT> 태그의 EC2(+디스크) / 고정 IP / 보안그룹 <PROJECT>-sg / 키페어 <PROJECT>-key
# 로컬의 ~/.ssh/<PROJECT>-key.pem 과 backend/.env, GitHub 저장소는 건드리지 않는다.
set -euo pipefail
export MSYS_NO_PATHCONV=1
export AWS_PAGER=""

main() {
  local mode="ask"
  case "${1:-}" in
    --dry-run) mode="dry-run" ;;
    --yes) mode="yes" ;;
    "") ;;
    *) echo "사용법: $0 [--dry-run | --yes]" >&2; exit 2 ;;
  esac

  local region="${AWS_REGION:-ap-southeast-2}"
  local project="${PROJECT:-fastapi-movie}"
  local key_name="${project}-key"
  local sg_name="${project}-sg"
  local ec2="aws ec2 --region ${region}"

  aws sts get-caller-identity --query Arn --output text >/dev/null || die "AWS 로그인이 필요합니다: aws login"

  echo "==> 삭제 대상 조회 (리전: ${region}, 프로젝트: ${project})"
  local instances eips sg key
  instances="$(${ec2} describe-instances \
    --filters "Name=tag:Project,Values=${project}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)"
  eips="$(${ec2} describe-addresses --filters "Name=tag:Project,Values=${project}" \
    --query 'Addresses[].[AllocationId,PublicIp,AssociationId]' --output text)"
  sg="$(${ec2} describe-security-groups --filters "Name=group-name,Values=${sg_name}" \
    --query 'SecurityGroups[0].GroupId' --output text)"
  key="$(${ec2} describe-key-pairs --filters "Name=key-name,Values=${key_name}" \
    --query 'KeyPairs[0].KeyName' --output text)"

  echo "    EC2      : ${instances:-(없음)}"
  if [ -n "${eips}" ]; then
    echo "    고정 IP  : $(awk '{print $2" ("$1")"}' <<<"${eips}" | paste -sd' ' -)"
  else
    echo "    고정 IP  : (없음)"
  fi
  echo "    보안그룹 : $( [ "${sg}" = "None" ] && echo '(없음)' || echo "${sg}" )"
  echo "    키페어   : $( [ "${key}" = "None" ] && echo '(없음)' || echo "${key}" )"

  if [ -z "${instances}" ] && [ -z "${eips}" ] && [ "${sg}" = "None" ] && [ "${key}" = "None" ]; then
    echo "삭제할 리소스가 없습니다."; return 0
  fi
  if [ "${mode}" = "dry-run" ]; then echo "dry-run: 아무것도 삭제하지 않았습니다."; return 0; fi
  if [ "${mode}" = "ask" ]; then
    echo
    echo "!! 위 리소스를 영구 삭제합니다. 서버 안의 데이터(.env 포함)는 복구할 수 없습니다."
    read -r -p "계속하려면 프로젝트 이름(${project})을 입력하세요: " answer
    [ "${answer}" = "${project}" ] || die "취소했습니다."
  fi

  if [ -n "${eips}" ]; then
    echo "==> 고정 IP 해제"
    while read -r alloc ip assoc; do
      [ -n "${alloc}" ] || continue
      if [ -n "${assoc}" ] && [ "${assoc}" != "None" ]; then
        ${ec2} disassociate-address --association-id "${assoc}"
      fi
      ${ec2} release-address --allocation-id "${alloc}"
      echo "    해제: ${ip}"
    done <<<"${eips}"
  fi

  if [ -n "${instances}" ]; then
    echo "==> EC2 종료 (디스크 포함): ${instances}"
    # shellcheck disable=SC2086
    ${ec2} terminate-instances --instance-ids ${instances} >/dev/null
    # shellcheck disable=SC2086
    ${ec2} wait instance-terminated --instance-ids ${instances}
    echo "    종료 완료"
  fi

  if [ "${sg}" != "None" ]; then
    echo "==> 보안그룹 삭제: ${sg}"
    ${ec2} delete-security-group --group-id "${sg}"
  fi

  if [ "${key}" != "None" ]; then
    echo "==> 키페어 삭제: ${key}"
    ${ec2} delete-key-pair --key-name "${key}" >/dev/null
    echo "    (로컬 ~/.ssh/${key}.pem 파일은 남아 있습니다. 더 이상 쓸모없으니 직접 지워도 됩니다.)"
  fi

  cat <<EOF

✅ 삭제 완료. 더 이상 요금이 발생하지 않습니다.
   GitHub 자동 배포는 서버가 없으므로 실패합니다. 저장소 Variables 의
   DEPLOY_ENABLED 를 false 로 바꾸면 빌드 검사만 실행됩니다.
   다시 만들 때: bash deploy/aws-create.sh
EOF
}

die() { echo "!! $*" >&2; exit 1; }

main "$@"
