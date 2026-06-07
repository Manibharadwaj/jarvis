#!/usr/bin/env bash
set -e

JARVIS_DIR="/root/jarvis"
LOG_DIR="$JARVIS_DIR/logs"
PID_DIR="$JARVIS_DIR/pids"
PORT="${PORT:-3000}"

mkdir -p "$LOG_DIR" "$PID_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Find PIDs listening on $PORT (lsof preferred, fuser fallback, ss as last resort).
# Always returns 0 — empty stdout means "no holder" — so it can be used inside
# `$(...)` assignment without tripping `set -e`.
pids_on_port() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti:"$port" 2>/dev/null || true
  elif command -v fuser >/dev/null 2>&1; then
    fuser "${port}/tcp" 2>/dev/null | tr -s ' ' '\n' | grep -v '$$$' || true
  else
    ss -tlnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}' | grep -oE 'pid=[0-9]+' | cut -d= -f2 || true
  fi
  return 0
}

# Find PIDs by command pattern
pids_by_pattern() {
  pgrep -f "$1" 2>/dev/null || true
  return 0
}

# Find the agent python child (not the supervisor bash that contains the
# python string in its argv).
agent_python_pids() {
  pgrep -f "venv/bin/python.*agent.py dev" 2>/dev/null || true
  pgrep -f "/usr/bin/python.*agent.py dev" 2>/dev/null || true
  return 0
}

# Wait until a URL returns 200 (or timeout)
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

# Kill anything related to jarvis: pid files, port listeners, and command patterns
stop_all() {
  echo "Stopping existing Jarvis processes..."

  # 1) PIDs we recorded ourselves
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] || continue
    local PID
    PID=$(cat "$pidfile")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null || true
      echo "  Stopped PID $PID ($(basename "$pidfile" .pid))"
    fi
    rm -f "$pidfile"
  done

  # 2) Anything else listening on $PORT (catches orphan node from a prior boot)
  local port_pids
  port_pids=$(pids_on_port "$PORT")
  if [ -n "$port_pids" ]; then
    for p in $port_pids; do
      if kill -0 "$p" 2>/dev/null; then
        kill "$p" 2>/dev/null || true
        echo "  Stopped port $PORT holder PID $p"
      fi
    done
  fi

  # 3) Belt-and-braces: pkill by command pattern.
  #    Use the literal python binary path so we don't match the supervisor
  #    bash whose argv contains the python command string.
  pkill -f "venv/bin/python.*agent.py dev" 2>/dev/null && echo "  pkill: venv python agent" || true
  pkill -f "/usr/bin/python.*agent.py dev" 2>/dev/null && echo "  pkill: system python agent" || true

  sleep 2
  # Force-kill anything that ignored SIGTERM
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] || continue
    local PID
    PID=$(cat "$pidfile")
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
      echo "  Force-killed PID $PID"
    fi
    rm -f "$pidfile"
  done
  local leftover
  leftover=$(pids_on_port "$PORT")
  if [ -n "$leftover" ]; then
    for p in $leftover; do
      kill -9 "$p" 2>/dev/null || true
      echo "  Force-killed port $PORT holder PID $p"
    done
    sleep 1
  fi
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
    echo ""

    # Backend
    backend_pid="(none)"
    if [ -f "$PID_DIR/backend.pid" ]; then
      backend_pid=$(cat "$PID_DIR/backend.pid")
    fi
    backend_alive="STOPPED"
    if [ -n "$backend_pid" ] && [ "$backend_pid" != "(none)" ] && kill -0 "$backend_pid" 2>/dev/null; then
      backend_alive="RUNNING (pid $backend_pid)"
    fi
    port_holders=$(pids_on_port "$PORT" | tr '\n' ' ')
    if [ -n "$port_holders" ]; then
      echo "  Backend (pid file): $backend_alive"
      echo "  Port $PORT:         HELD BY $port_holders"
    else
      echo "  Backend (pid file): $backend_alive"
      echo "  Port $PORT:         FREE"
    fi
    if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
      echo "  Health endpoint:    OK"
    else
      echo "  Health endpoint:    DOWN"
    fi
    echo ""

    # Agent
    agent_pid="(none)"
    if [ -f "$PID_DIR/agent.pid" ]; then
      agent_pid=$(cat "$PID_DIR/agent.pid")
    fi
    agent_alive="STOPPED"
    if [ -n "$agent_pid" ] && [ "$agent_pid" != "(none)" ] && kill -0 "$agent_pid" 2>/dev/null; then
      agent_alive="RUNNING (pid $agent_pid)"
    fi
    agent_pids=$(agent_python_pids | tr '\n' ' ')
    echo "  Agent (pid file):   $agent_alive"
    if [ -n "$agent_pids" ]; then
      echo "  Agent processes:    $agent_pids"
    else
      echo "  Agent processes:    (none)"
    fi
    echo ""
    echo "  Logs: $LOG_DIR/"
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

# 0. Backend (Node.js)
echo "[0/2] Starting Backend..."
cd "$JARVIS_DIR/backend"
# setsid: put the backend in its own session so it survives the parent shell
# closing (logout, SSH disconnect, etc). nohup adds SIGHUP immunity on top.
# $! is the setsid wrapper PID, which exits immediately after spawning node,
# so we wait briefly and grab the actual node PID by command.
setsid nohup node src/server.js > "$LOG_DIR/backend.log" 2>&1 < /dev/null &
disown 2>/dev/null || true
sleep 2
BACKEND_PID=$(pgrep -f "node src/server.js" | head -1)
if [ -z "$BACKEND_PID" ]; then
  echo "  Backend: FAILED to start (check $LOG_DIR/backend.log)"
  exit 1
fi
echo "$BACKEND_PID" > "$PID_DIR/backend.pid"
wait_for "Backend" "http://localhost:$PORT/health" 15
echo "  Backend pid: $BACKEND_PID"

# 1. Voice Agent (Python) — wrapped in a self-restart loop
#    The LiveKit worker occasionally crashes between calls (worker connection
#    closed unexpectedly, OOM, etc). The supervisor runs an outer shell that
#    respawns `python agent.py dev` whenever it exits. pkill -f inside
#    stop_all handles cleanup.
#
#    Process layout:
#      start.sh  ── spawns ──>  supervisor (bash, recorded in pids/agent.pid)
#                                   │
#                                   └── while true; do python agent.py dev; done
#                                              │
#                                              └── forkserver children
#
#    The supervisor is bash; python is its child. When python dies, the loop
#    respawns it after 2s. When start.sh stop runs, pkill -f "python agent.py
#    dev" kills the children and the supervisor (whose $! is the subshell
#    bash that execs to python when it spawns a child).
echo "[1/2] Starting Voice Agent (with auto-restart)..."
# Use the venv python directly so the supervisor doesn't need a sourced venv.
# (Background bash -c doesn't inherit `source venv/bin/activate`.)
VENV_PY="$JARVIS_DIR/agent/venv/bin/python"
# setsid: own session. nohup: SIGHUP immune. disown: remove from job table.
setsid nohup bash -c '
  set +e
  while true; do
    {
      echo "=== agent boot: $(date -Iseconds) ==="
      echo "=== agent exited: $(date -Iseconds), restarting in 2s ==="
    } >> "'"$LOG_DIR"'/agent.log"
    cd "'"$JARVIS_DIR"'/agent"
    "'"$VENV_PY"'" -u agent.py dev >> "'"$LOG_DIR"'/agent.log" 2>&1
    sleep 2
  done
' >/dev/null 2>&1 < /dev/null &
disown 2>/dev/null || true
sleep 2
# Find the supervisor bash (comm=bash, with the agent loop in argv) — not the
# node backend, not the venv python. pgrep -f matches by full command line,
# so we use comm to be precise.
AGENT_PID=$(ps -eo pid,comm,args | awk '$2 == "bash" && $0 ~ /agent\.py dev/ && $0 ~ /venv\/bin\/python/ {print $1; exit}')
if [ -z "$AGENT_PID" ]; then
  # Fallback: match the older pattern
  AGENT_PID=$(pgrep -f "while true.*agent.py dev" | head -1)
fi
if [ -z "$AGENT_PID" ]; then
  echo "  Voice Agent: FAILED to start (supervisor not found)"
  exit 1
fi
echo "$AGENT_PID" > "$PID_DIR/agent.pid"
sleep 3
if kill -0 "$AGENT_PID" 2>/dev/null; then
  echo "  Voice Agent: OK (supervisor pid $AGENT_PID)"
else
  echo "  Voice Agent: FAILED (check $LOG_DIR/agent.log)"
fi

# 2. Summary
echo "[2/2] Verification..."
echo ""
echo "=== Jarvis is running ==="
echo ""
echo "  Backend:     http://localhost:$PORT"
echo "  Health:      http://localhost:$PORT/health"
echo "  Chat API:    http://localhost:$PORT/api/chat"
echo "  Voice Start: http://localhost:$PORT/api/voice/start"
echo ""
echo "  STT:         Groq Whisper (cloud)"
echo "  LLM:         Ollama Cloud"
echo "  TTS:         Edge TTS (streaming)"
echo ""
echo "  Logs: $LOG_DIR/"
echo "  PIDs: $PID_DIR/"
echo ""
echo "  Use '$0 status' to check health"
echo "  Use '$0 stop' to shut down"
