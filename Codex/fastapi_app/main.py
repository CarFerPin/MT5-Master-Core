from __future__ import annotations

import json
import sys
from enum import Enum
from pathlib import Path

from fastapi import FastAPI, HTTPException


CURRENT_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = CURRENT_DIR.parent
if str(WORKSPACE_DIR) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_DIR))

from terminal_filesystem import BASE_DIR, RUNTIME_DIR, create_terminal, read_state, write_action


class ActionType(str, Enum):
    buy = "buy"
    sell = "sell"
    be = "be"
    cancel = "cancel"
    close = "close"


app = FastAPI(title="Manual Execution Backend", version="0.1.0")


def read_ea_state(terminal_id: str) -> dict:
    state_path = BASE_DIR / "runtime" / "terminals" / terminal_id / "TradeAssistant" / "state.json"
    if not state_path.exists():
        return {"error": "state not available"}
    return json.loads(state_path.read_text(encoding="utf-8"))


@app.get("/terminals")
def list_terminals() -> dict[str, list[str]]:
    if not RUNTIME_DIR.exists():
        return {"terminals": []}

    terminals = sorted(path.name for path in RUNTIME_DIR.iterdir() if path.is_dir())
    return {"terminals": terminals}


@app.get("/terminals/{terminal_id}/state")
def get_terminal_state(terminal_id: str) -> dict:
    try:
        return read_ea_state(terminal_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/terminals/{terminal_id}/symbols/{symbol}/actions/{action_type}")
def post_action(terminal_id: str, symbol: str, action_type: ActionType) -> dict[str, str]:
    try:
        terminal_dir = RUNTIME_DIR / terminal_id
        if not terminal_dir.exists():
            raise HTTPException(
                status_code=404,
                detail=f"Terminal '{terminal_id}' does not exist",
            )
        control = write_action(terminal_id, symbol, action_type.value)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Filesystem error: {exc}") from exc

    action = control["action"]
    return {
        "terminal_id": terminal_id,
        "symbol": symbol,
        "action_type": action_type.value,
        "action_id": action["id"],
        "timestamp": action["timestamp"],
    }
