from __future__ import annotations

import json
from configparser import ConfigParser
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any
from uuid import uuid4


BASE_DIR = Path(r"C:\Users\carfe\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files")
RUNTIME_DIR = BASE_DIR / "runtime" / "terminals"


def create_terminal(terminal_id: str) -> Path:
    terminal_dir = _terminal_dir(terminal_id)
    terminal_dir.mkdir(parents=True, exist_ok=True)

    control_path = terminal_dir / "control.json"
    broker_path = terminal_dir / "broker.ini"
    asset_path = terminal_dir / "asset.ini"
    risk_limits_path = terminal_dir / "risk_limits.ini"
    state_path = terminal_dir / "state.json"

    if not control_path.exists():
        _write_json_atomic(control_path, _default_control(terminal_id))
    if not broker_path.exists():
        _write_ini_atomic(broker_path, _default_broker())
    if not asset_path.exists():
        _write_ini_atomic(asset_path, _default_asset())
    if not risk_limits_path.exists():
        _write_ini_atomic(risk_limits_path, _default_risk_limits())
    if not state_path.exists():
        _write_json_atomic(state_path, _default_state(terminal_id))

    return terminal_dir


def write_action(terminal_id: str, symbol: str, action_type: str) -> dict[str, Any]:
    terminal_dir = create_terminal(terminal_id)
    control_path = terminal_dir / "control.json"
    control = json.loads(control_path.read_text(encoding="utf-8"))

    control["action"] = {
        "id": f"act_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}_{uuid4().hex[:8]}",
        "symbol": symbol,
        "type": action_type,
        "timestamp": _utc_now_iso(),
        "consumed": False,
    }

    _write_json_atomic(control_path, control)
    return control


def read_state(terminal_id: str) -> dict[str, Any]:
    state_path = create_terminal(terminal_id) / "state.json"
    return json.loads(state_path.read_text(encoding="utf-8"))


def _terminal_dir(terminal_id: str) -> Path:
    clean_terminal_id = terminal_id.strip()
    if not clean_terminal_id:
        raise ValueError("terminal_id cannot be empty")
    return RUNTIME_DIR / clean_terminal_id


def _default_control(terminal_id: str) -> dict[str, Any]:
    return {
        "terminal_id": terminal_id,
        "global_switch": {
            "enabled": True,
        },
        "symbols": {
            "XAUUSD": {
                "enabled": True,
                "mode": "trend",
                "risk": {
                    "base_volume": 0.10,
                    "counter_multiplier": 0.50,
                },
            },
            "EURUSD": {
                "enabled": False,
                "mode": "counter",
                "risk": {
                    "base_volume": 0.20,
                    "counter_multiplier": 0.75,
                },
            },
        },
        "action": {
            "id": f"act_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}_init",
            "symbol": "XAUUSD",
            "type": "buy",
            "timestamp": _utc_now_iso(),
            "consumed": True,
        },
        "execution": {
            "max_random_delay_sec": 2,
        },
    }


def _default_broker() -> dict[str, dict[str, str]]:
    return {
        "broker": {
            "login": "12345678",
            "server": "ICMarketsSC-Demo",
            "env": "demo",
            "size_multiplier": "1.00",
        }
    }


def _default_asset() -> dict[str, dict[str, str]]:
    return {
        "asset": {
            "sl_pts": "250",
            "max_spread_pts": "45",
            "entry_offset_pts": "10",
            "min_sl_pts": "150",
            "max_sl_pts": "500",
            "slippage": "20",
            "be_protect_pts": "120",
        }
    }


def _default_risk_limits() -> dict[str, dict[str, str]]:
    return {
        "risk": {
            "max_daily_loss_pct": "3.0",
            "max_total_drawdown_pct": "8.0",
        },
        "blocks": {
            "manual_block": "false",
            "daily_loss_block": "false",
            "drawdown_block": "false",
        },
    }


def _default_state(terminal_id: str) -> dict[str, Any]:
    return {
        "terminal": {
            "id": terminal_id,
            "broker": "ICMarketsSC-Demo",
            "login": 12345678,
            "env": "demo",
        },
        "heartbeat": {
            "last_seen": _utc_now_iso(),
            "ea_version": "TradeAssistantMASTERCONTROL",
            "status": "online",
        },
        "symbol_config": {
            "symbol": "XAUUSD",
            "enabled": True,
            "mode": "trend",
            "risk": {
                "base_volume": 0.10,
                "counter_multiplier": 0.50,
            },
        },
        "execution": {
            "position_open": False,
            "pending_orders": 0,
            "last_action_id": "",
            "last_action_type": "",
            "last_action_status": "idle",
            "last_error": "",
        },
        "risk": {
            "risk_blocked": False,
            "daily_loss_pct": 0.0,
            "drawdown_pct": 0.0,
        },
        "schedule": {
            "blocked": False,
        },
    }


def _write_json_atomic(path: Path, data: dict[str, Any]) -> None:
    content = json.dumps(data, indent=2, ensure_ascii=True) + "\n"
    _write_text_atomic(path, content)


def _write_ini_atomic(path: Path, sections: dict[str, dict[str, str]]) -> None:
    config = ConfigParser()
    config.optionxform = str
    for section, values in sections.items():
        config[section] = values

    with NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        delete=False,
        newline="\n",
    ) as temp_file:
        config.write(temp_file)
        temp_path = Path(temp_file.name)

    temp_path.replace(path)


def _write_text_atomic(path: Path, content: str) -> None:
    with NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        delete=False,
        newline="\n",
    ) as temp_file:
        temp_file.write(content)
        temp_path = Path(temp_file.name)

    temp_path.replace(path)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
