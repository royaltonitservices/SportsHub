#!/usr/bin/env bash
# Dev-only helper to reliably start/stop/check the local SportsHub FastAPI backend.
#
#   ./scripts/dev_backend.sh status    # is it running + healthy?
#   ./scripts/dev_backend.sh start     # start if down (won't start a duplicate)
#   ./scripts/dev_backend.sh stop      # stop ONLY the process this script started
#   ./scripts/dev_backend.sh restart   # stop then start
#   ./scripts/dev_backend.sh health    # curl /health and show the HTTP result
#
# Notes:
#   - Uses the repo .venv only. Never touches backend/.env. Prints no secrets.
#   - Logs + PID live under backend/.local/ (gitignored).
#   - `stop` only kills the PID in the PID file AND only if its command is our
#     uvicorn — it never pkills unrelated Python.
#   - `start` uses nohup + disown so the server survives the terminal closing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND="$ROOT/backend"
UVICORN="$BACKEND/.venv/bin/uvicorn"
LOCAL="$BACKEND/.local"
PIDFILE="$LOCAL/backend.pid"
LOGFILE="$LOCAL/backend.log"
HOST="0.0.0.0"
PORT="8000"
HEALTH_URL="http://localhost:${PORT}/health"
CMD_MATCH="uvicorn main:app"   # used to confirm a PID is really our backend

mkdir -p "$LOCAL"

_pid_from_file() { [[ -f "$PIDFILE" ]] && cat "$PIDFILE" 2>/dev/null || true; }

# Is the given PID alive AND actually our uvicorn backend?
_is_our_backend() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q "$CMD_MATCH"
}

_port_pid() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true; }

_health_code() {
  local code
  code="$(curl -s -m 4 -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null)" || code="000"
  echo "${code:-000}"
}

cmd_health() {
  local code; code="$(_health_code)"
  if [[ "$code" == "200" ]]; then
    echo "health: HTTP 200  $(curl -s -m4 "$HEALTH_URL" 2>/dev/null)"
    return 0
  fi
  echo "health: HTTP $code (not healthy / not reachable)"
  return 1
}

cmd_status() {
  local pid; pid="$(_pid_from_file)"
  local ppid; ppid="$(_port_pid)"
  if _is_our_backend "$pid"; then
    echo "status: RUNNING (our PID $pid, from $PIDFILE)"
  elif [[ -n "$ppid" ]]; then
    echo "status: port $PORT is held by PID $ppid (not started by this script)"
  else
    echo "status: NOT RUNNING (nothing on port $PORT)"
  fi
  cmd_health || true
}

cmd_start() {
  # Already healthy? Don't start a duplicate.
  if [[ "$(_health_code)" == "200" ]]; then
    local ppid; ppid="$(_port_pid)"
    echo "start: backend already running and healthy (PID ${ppid:-unknown}). Not starting a duplicate."
    return 0
  fi
  # Port held but unhealthy / not ours?
  local ppid; ppid="$(_port_pid)"
  if [[ -n "$ppid" ]]; then
    echo "start: port $PORT is already held by PID $ppid but /health is not 200."
    echo "       If that's a stale server, run: ./scripts/dev_backend.sh stop   (or inspect PID $ppid manually)."
    return 1
  fi
  if [[ ! -x "$UVICORN" ]]; then
    echo "start: ERROR — $UVICORN not found. Create the venv first (python3 -m venv backend/.venv && pip install -r backend/requirements.txt)."
    return 1
  fi
  echo "start: launching uvicorn (logs → $LOGFILE)"
  ( cd "$BACKEND" && nohup "$UVICORN" main:app --host "$HOST" --port "$PORT" >"$LOGFILE" 2>&1 & )
  disown 2>/dev/null || true
  # Wait up to ~15s for health, then record the ACTUAL listening PID (uvicorn may
  # differ from the launcher PID), so `stop` can reliably find it later.
  for _ in $(seq 1 15); do
    if [[ "$(_health_code)" == "200" ]]; then
      local ppid; ppid="$(_port_pid)"
      [[ -n "$ppid" ]] && echo "$ppid" >"$PIDFILE"
      echo "start: OK — PID ${ppid:-unknown}, /health 200"
      return 0
    fi
    sleep 1
  done
  echo "start: FAILED to become healthy within 15s. Last log lines:"; tail -n 15 "$LOGFILE" 2>/dev/null || true
  return 1
}

cmd_stop() {
  local pid; pid="$(_pid_from_file)"
  if _is_our_backend "$pid"; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "stop: stopped our backend (PID $pid)"
  else
    rm -f "$PIDFILE" 2>/dev/null || true
    echo "stop: no backend that THIS script started is running (PID file cleared)."
    local ppid; ppid="$(_port_pid)"
    [[ -n "$ppid" ]] && echo "      Note: something else (PID $ppid) is on port $PORT — not touching it."
  fi
}

cmd_restart() { cmd_stop || true; sleep 1; cmd_start; }

case "${1:-status}" in
  status)  cmd_status ;;
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  health)  cmd_health ;;
  *) echo "usage: $0 {status|start|stop|restart|health}"; exit 2 ;;
esac
