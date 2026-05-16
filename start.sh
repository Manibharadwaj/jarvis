#!/usr/bin/env bash
set -e

JARVIS_DIR="/root/jarvis"
LOG_DIR="$JARVIS_DIR/logs"
PID_DIR="$JARVIS_DIR/pids"

mkdir -p "$LOG_DIR" "$PID_DIR"

# Kill existing processes if running
stop_all() {
  echo "Stopping existing Jarvis processes..."
  for pidfile in "$PID_DIR"/*.pid; do
    if [ -f "$pidfile" ]; then
      PID=$(cat "$pidfile")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        echo "  Stopped PID $PID ($(basename "$pidfile" .pid))"
      fi
      rm "$pidfile"
    fi
  done
  docker stop faster-whisper-server 2>/dev/null && echo "  Stopped faster-whisper-server" || true
  sleep 2
}

# Health check: wait for a URL to return 200
wait_for() {
  local name="$1" url="$2" timeout="${3:-30}"
  echo -n "  Waiting for $name..."
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if curl -sf "$url" > /dev/null 2>&1; then
      echo " OK"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo " FAILED (timeout after ${timeout}s)"
  return 1
}

case "${1:-start}" in
  stop)
    stop_all
    echo "All stopped."
    exit 0
    ;;
  restart)
    stop_all
    ;;
  start)
    stop_all
    ;;
  status)
    echo "Jarvis Status:"
    for pidfile in "$PID_DIR"/*.pid; do
      if [ -f "$pidfile" ]; then
        PID=$(cat "$pidfile")
        if kill -0 "$PID" 2>/dev/null; then
          echo "  $(basename "$pidfile" .pid): RUNNING (PID $PID)"
        else
          echo "  $(basename "$pidfile" .pid): STOPPED (stale pid)"
          rm "$pidfile"
        fi
      fi
    done
    # Quick health checks
    curl -sf http://localhost:3000/health > /dev/null 2>&1 && echo "  Backend health: OK" || echo "  Backend health: DOWN"
    exit 0
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

echo ""
echo "=== Starting Jarvis ==="
echo ""

# 0. Faster-whisper STT (Docker)
if ! docker ps --format '{{.Names}}' | grep -q 'faster-whisper-server'; then
  echo "[0/3] Starting Faster-whisper STT..."
  docker start faster-whisper-server 2>/dev/null || \
    docker run -d --name faster-whisper-server --restart unless-stopped \
      -p 8000:8000 \
      -e WHISPER__MODEL=small \
      -e WHISPER__COMPUTE_TYPE=int8 \
      fedirz/faster-whisper-server:latest-cpu
  wait_for "Faster-whisper" "http://localhost:8000/v1/models" 60
else
  echo "[0/3] Faster-whisper STT: already running"
fi

# 1. Backend (Node.js)
echo "[1/3] Starting Backend..."
cd "$JARVIS_DIR/backend"
nohup node src/server.js > "$LOG_DIR/backend.log" 2>&1 &
echo $! > "$PID_DIR/backend.pid"
wait_for "Backend" "http://localhost:3000/health" 15

# 2. Voice Agent (Python)
echo "[2/3] Starting Voice Agent..."
cd "$JARVIS_DIR/agent"
source venv/bin/activate
nohup python agent.py dev > "$LOG_DIR/agent.log" 2>&1 &
echo $! > "$PID_DIR/agent.pid"
sleep 5
if kill -0 $(cat "$PID_DIR/agent.pid") 2>/dev/null; then
  echo "  Voice Agent: OK"
else
  echo "  Voice Agent: FAILED (check $LOG_DIR/agent.log)"
fi

# 3. Summary
echo "[3/3] Verification..."
echo ""
echo "=== Jarvis is running ==="
echo ""
echo "  Backend:     http://localhost:3000"
echo "  Health:      http://localhost:3000/health"
echo "  Chat API:    http://localhost:3000/api/chat"
echo "  Voice Start: http://localhost:3000/api/voice/start"
echo ""
echo "  Logs: $LOG_DIR/"
echo "  PIDs: $PID_DIR/"
echo ""
echo "  Use '$0 status' to check health"
echo "  Use '$0 stop' to shut down"