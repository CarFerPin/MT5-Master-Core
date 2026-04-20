import requests


BASE_URL = "http://127.0.0.1:8000"


def get_terminals():
    response = requests.get(f"{BASE_URL}/terminals")
    response.raise_for_status()
    return response.json()


def get_state(terminal_id: str):
    response = requests.get(f"{BASE_URL}/terminals/{terminal_id}/state")
    response.raise_for_status()
    return response.json()


def send_action(terminal_id: str, symbol: str, action: str):
    response = requests.post(
        f"{BASE_URL}/terminals/{terminal_id}/symbols/{symbol}/actions/{action}"
    )
    response.raise_for_status()
    return response.json()


def send_action_to_terminals(terminal_ids: list[str], symbol: str, action: str):
    results = []

    for terminal_id in terminal_ids:
        try:
            response = send_action(terminal_id, symbol, action)
            results.append(
                {
                    "terminal_id": terminal_id,
                    "success": True,
                    "action_id": response.get("action_id"),
                    "timestamp": response.get("timestamp"),
                }
            )
        except requests.RequestException as exc:
            results.append(
                {
                    "terminal_id": terminal_id,
                    "success": False,
                    "error": str(exc),
                }
            )

    return results
