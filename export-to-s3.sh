#!/usr/bin/env bash
# Amazon Linux에서 pipefail 에러가 나면 아래 줄을 잠시 주석 처리하세요.
set -euo pipefail

# ===== 사용자 환경 변수(스크립트 내부에서만 사용; .bashrc 건드리지 않음) =====
ES="${ES:-http://10.0.129.85:9200}"
BUCKET="${BUCKET:-project-team2bucket}"
INDEX_PATTERN="${INDEX_PATTERN:-webapp2-*}"
TIME_RANGE="${TIME_RANGE:-now-1h}"
SIZE="${SIZE:-10000}"          # 1만 건 이하일 때만 사용 (그 이상이면 search_after 권장)

# ===== 사전 의존성 / 연결 점검 =====
command -v jq >/dev/null      || { echo "[ERROR] jq 미설치"; exit 1; }
command -v aws >/dev/null     || { echo "[ERROR] aws CLI 미설치"; exit 1; }

if ! curl -sS "$ES" >/dev/null; then
  echo "[ERROR] Elasticsearch 접속 실패: $ES"
  exit 1
fi

# 인덱스 존재 확인(없으면 바로 중단)
if ! curl -sS "$ES/_cat/indices/$INDEX_PATTERN?h=index" | grep -q .; then
  echo "[ERROR] 인덱스 패턴에 해당하는 인덱스가 없음: $INDEX_PATTERN"
  echo "        (참고) 실제 인덱스 목록: curl -s \"$ES/_cat/indices?v\""
  exit 1
fi

# 최근 문서 수 확인
COUNT_JSON=$(curl -sS "$ES/$INDEX_PATTERN/_count" \
  -H 'Content-Type: application/json' \
  -d "{\"query\":{\"range\":{\"@timestamp\":{\"gte\":\"$TIME_RANGE\"}}}}")
COUNT=$(echo "$COUNT_JSON" | jq -r '.count // 0')
echo "[INFO] 최근 1시간 문서 수: $COUNT"

if [[ "$COUNT" -eq 0 ]]; then
  echo "[INFO] 추출할 문서가 없어 업로드를 스킵합니다."
  exit 0
fi

# ===== 추출 → JSONL → 압축 → 업로드 =====
TMP_JSONL=$(mktemp /tmp/export.XXXXXX.jsonl)
OUT_GZ="export-$(date +%Y%m%d-%H%M%S).jsonl.gz"

curl -sS "$ES/$INDEX_PATTERN/_search?size=$SIZE&sort=@timestamp:asc" \
  -H 'Content-Type: application/json' \
  -d '{
    "_source": [
      "@timestamp","event_code","event.category","url.path",
      "http.request.method","client.ip","http.response.status_code",
      "http.request.referrer","user_agent.name","app"
    ],
    "query":{"range":{"@timestamp":{"gte":"'"$TIME_RANGE"'"}}}
  }' \
| jq -r '.hits.hits[]._source | @json' > "$TMP_JSONL"

# 빈 파일 방지(혹시라도 size 제한 등으로 hits가 0인 경우)
if [[ ! -s "$TMP_JSONL" ]]; then
  echo "[WARN] 검색 응답은 있었지만 추출 결과 파일이 비었습니다. 업로드 스킵."
  echo "       (SIZE 제한, _source 필드 불일치 가능성 확인)"
  exit 0
fi

gzip -f "$TMP_JSONL"
mv "${TMP_JSONL}.gz" "$OUT_GZ"

aws s3 cp "$OUT_GZ" "s3://$BUCKET/ad-hoc/$OUT_GZ"

echo "[DONE] 업로드 완료 → s3://$BUCKET/ad-hoc/$OUT_GZ"

