#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# Ollama Model Auto-Pull
#
# Reads the OLLAMA_PULL_MODELS environment variable and instructs the local Ollama
# container to pull the requested models via its REST API.
# ==============================================================================

# Default Ollama host URL reachable from the ORDS container Docker network
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://ollama:11434}"
OLLAMA_API_URL="${OLLAMA_BASE_URL%/}/api"
OLLAMA_PULL_MODELS="${OLLAMA_PULL_MODELS:-}"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

if [ -z "$OLLAMA_PULL_MODELS" ]; then
  echo "INFO : OLLAMA_PULL_MODELS is not set or empty. Skipping AI model pull."
  exit 0
fi

echo "INFO : OLLAMA_PULL_MODELS is set to '$OLLAMA_PULL_MODELS'."

# Wait for Ollama to be reachable
echo "INFO : Waiting for Ollama container to be ready..."

if ! curl --retry 5 --retry-connrefused --retry-delay 5 -s -f "${OLLAMA_BASE_URL%/}/" > /dev/null; then
  echo "WARNING : Ollama container did not become ready in time. Skipping model pull."
  exit 0
fi

echo "INFO : Ollama is ready. Processing models..."

# Convert comma-separated string to an array and loop through it
IFS=',' read -ra MODELS <<< "$OLLAMA_PULL_MODELS"

for raw_model in "${MODELS[@]}"; do
  model=$(trim "$raw_model")

  if [ -n "$model" ]; then
    echo "INFO : Sending background pull request to Ollama for model: $model..."

    # We run the curl command in the background (&) and set "stream": false.
    # This ensures a massive 5GB+ download does not block the ORDS server from starting!
    curl -s -X POST "${OLLAMA_API_URL}/pull" \
         -H "Content-Type: application/json" \
         -d "{\"name\": \"$model\", \"stream\": false}" > /dev/null &
  fi
done

echo "INFO : All Ollama model pull requests submitted successfully."