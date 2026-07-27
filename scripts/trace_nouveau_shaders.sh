#!/usr/bin/env bash
# trace_nouveau_shaders.sh - Trace and dump Mesa nvc0 WebGL shaders and pushbuffers
# Target GPU: NVIDIA GeForce GT 750M (GK107M / Kepler)

set -euo pipefail

LOG_DIR="/home/fbetancourt/Gemini/nouveau_mesa_kepler_fix/docs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/nouveau_trace_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

echo "[INFO] Starting Nouveau Mesa shader trace..."
echo "[INFO] Log file target: ${LOG_FILE}"

export NOUVEAU_DEBUG="pushbuf,shader"
export MESA_DEBUG="1"
export GALLIUM_DUMP_CPU="1"

echo "[INFO] Running environment flags:"
echo "       NOUVEAU_DEBUG=${NOUVEAU_DEBUG}"
echo "       MESA_DEBUG=${MESA_DEBUG}"

echo "[INFO] Environment ready. Launching diagnostic wrapper..."
