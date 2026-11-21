# Usage: source tests/set-token.sh

_is_sourced=0
if [[ -n "${ZSH_EVAL_CONTEXT:-}" ]]; then
  [[ "$ZSH_EVAL_CONTEXT" == *:file* ]] && _is_sourced=1
elif [[ -n "${BASH_VERSION:-}" ]]; then
  [[ "${BASH_SOURCE[0]}" != "$0" ]] && _is_sourced=1
fi

if [[ "$_is_sourced" -ne 1 ]]; then
  echo "Run this script with 'source' so ACCESS_TOKEN persists in your shell:" >&2
  echo "  source tests/set-token.sh" >&2
  exit 1
fi
unset _is_sourced

_set_wso2_access_token() {
  local env_file="${ENV_FILE:-.env}"
  if [[ -f "$env_file" ]]; then
    set -a
    source "$env_file"
    set +a
  fi

  if [[ -z "${CONSUMER_KEY:-}" || -z "${CONSUMER_SECRET:-}" ]]; then
    echo "Error: CONSUMER_KEY and CONSUMER_SECRET must be set in .env or environment." >&2
    return 1
  fi

  local token_url="${TOKEN_URL:-https://localhost:9443/oauth2/token}"
  local response token expires_in

  response=$(curl -k -sS -X POST "$token_url" \
    -u "${CONSUMER_KEY}:${CONSUMER_SECRET}" \
    -d "grant_type=client_credentials") || return 1

  if command -v jq >/dev/null 2>&1; then
    token=$(printf '%s' "$response" | jq -r '.access_token // empty')
    expires_in=$(printf '%s' "$response" | jq -r '.expires_in // "unknown"')
  else
    token=$(printf '%s' "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)
    expires_in=$(printf '%s' "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('expires_in', 'unknown'))" 2>/dev/null)
  fi

  if [[ -z "$token" ]]; then
    echo "Error: failed to obtain access_token. Response: $response" >&2
    return 1
  fi

  export ACCESS_TOKEN="$token"
  echo "ACCESS_TOKEN exported (expires in ${expires_in}s)"
}

_set_wso2_access_token
unset -f _set_wso2_access_token
