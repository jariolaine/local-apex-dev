#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Ollama Model Auto-Pull
#
# Reads the OLLAMA_PULL_MODELS environment variable and instructs the local Ollama
# container to pull the requested models via its REST API.
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration Variables
# ------------------------------------------------------------------------------
# Default Ollama host URL reachable from the container Docker network.
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://ollama:11434}"
OLLAMA_PULL_MODELS="${OLLAMA_PULL_MODELS:-}"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if [ -z "$OLLAMA_PULL_MODELS" ]; then
  echo "INFO : OLLAMA_PULL_MODELS is not set or empty. Skipping AI model pull."
  return 0
fi

echo "INFO : OLLAMA_PULL_MODELS is set to '$OLLAMA_PULL_MODELS'."

# Wait for Ollama to be reachable.
echo "INFO : Waiting for Ollama container to be ready..."

if ! curl --retry-connrefused --retry 5 --retry-delay 5 -s -f "${OLLAMA_BASE_URL%/}/" > /dev/null; then
  echo "WARNING : Ollama container did not become ready in time. Skipping model pull." >&2
  return 0
fi

echo "INFO : Ollama is ready. Processing models..."


# Convert comma-separated string to an array and loop through it.
IFS=',' read -ra MODELS <<< "$OLLAMA_PULL_MODELS"

pull_count=0
for raw_model in "${MODELS[@]}"; do
  model=$(trim "$raw_model")

  if [ -n "$model" ]; then
    echo "INFO : Sending background pull request to Ollama for model: $model..."

    # Run each pull request in the background so model downloads do not block database startup.
    # "stream": false writes one final response to the log when each pull request completes.
    curl -s -X POST "${OLLAMA_BASE_URL%/}/api/pull" \
         -H "Content-Type: application/json" \
         -d "{\"name\": \"$model\", \"stream\": false}" \
         >> /tmp/ollama_pull.log 2>&1 &
    ((pull_count += 1))
  fi
done

if ((pull_count == 0 )); then
  echo "INFO : No valid model names found. Nothing to pull."
else
  echo "INFO : Started ${pull_count} Ollama model pull requests in the background."
  echo "INFO : Monitor progress with:"
  echo "INFO : docker compose exec -it db tail -f /tmp/ollama_pull.log"
fi
