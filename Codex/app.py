import streamlit as st
from requests import RequestException

from api_client import get_terminals, send_action_to_terminals


st.markdown('<div class="main-title">Manual Execution Panel</div>', unsafe_allow_html=True)

if "global_results" not in st.session_state:
    st.session_state.global_results = []

try:
    terminals_response = get_terminals()
    terminals = terminals_response.get("terminals", [])
except RequestException as exc:
    st.error(f"Failed to fetch terminals: {exc}")
    terminals = []

global_tab, multibroker_tab, metrics_tab = st.tabs(["GLOBAL", "MULTIBROKER", "METRICS"])

with global_tab:
    if not terminals:
        st.warning("No terminals available")
    else:
        global_trading_enabled = True
        st.markdown("""
    <style>
                    
    /* TITULO GRADIENT */
    .main-title {
        font-size: 3rem;
        font-weight: 800;
        background: linear-gradient(90deg, #ff7a18, #ff3c3c);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
    }

    /* GLOBAL EXECUTION + STATUS */
    .section-accent {
        color: #ff7a18 !important;
        font-weight: 600;
    }

    /* BOTONES BASE */
    div[data-testid="stButton"] > button {
        width: 100%;
        border-radius: 12px;
        padding: 0.8rem 0.3rem;
        min-height: 50px;
        font-weight: 700;
        color: white;
        border: none;
        transition: all 0.15s ease;
    }

    /* BUY (1er botón) → naranja fondo, texto negro */
    div[data-testid="stHorizontalBlock"] > div:nth-child(1) button {
        background: #ff7a18 !important;
        color: black !important;
        box-shadow: 0 0 12px rgba(255,122,24,0.35);
    }

    /* SELL (2do) */
    div[data-testid="stHorizontalBlock"] > div:nth-child(2) button {
        background: black !important;
        color: #ff7a18 !important;
        border: 2px solid #ff7a18 !important;
        box-shadow: 0 0 12px rgba(255,122,24,0.35);
    }

    /* BE (3ro) */
    div[data-testid="stHorizontalBlock"] > div:nth-child(3) button {
        background: transparent !important;
        color: white !important;
        border: 2px solid #6b7280 !important;
    }

    /* CANCEL (4to) → sin cambio */
    div[data-testid="stHorizontalBlock"] > div:nth-child(4) button {
        background: #6b7280 !important;
    }

    /* CLOSE (5to) */
    div[data-testid="stHorizontalBlock"] > div:nth-child(5) button {
        background: transparent !important;
        color: white !important;
        border: 2px solid #6b7280 !important;
    }

    /* HOVER */
    div[data-testid="stButton"] > button:hover {
        filter: brightness(1.15);
    }
    </style>
    """,
            unsafe_allow_html=True,
        )

        for terminal_id in terminals:
            toggle_key = f"terminal_toggle_{terminal_id}"
            if toggle_key not in st.session_state:
                st.session_state[toggle_key] = True

        selected_terminals = [
            terminal_id
            for terminal_id in terminals
            if st.session_state.get(f"terminal_toggle_{terminal_id}", True)
        ]

        header_col1, header_col2 = st.columns([3, 1.2])
        with header_col1:
            st.markdown('<p class="global-header-title">GLOBAL EXECUTION</p>', unsafe_allow_html=True)
        with header_col2:
            status_class = "enabled" if global_trading_enabled else "suspended"
            status_text = "TRADING: ENABLED" if global_trading_enabled else "TRADING: SUSPENDED (NEWS)"
            st.markdown(
            f'<div class="global-status section-accent {status_class}">{status_text}</div>',
            unsafe_allow_html=True,
        )

        asset_tabs = st.tabs(["XAUUSD", "EURUSD"])
        actions = [
            ("buy", "BUY", "buy-btn"),
            ("sell", "SELL", "sell-btn"),
            ("be", "BE", "be-btn"),
            ("cancel", "CANCEL", "cancel-btn"),
            ("close", "CLOSE", "close-btn"),
        ]

        for asset_tab, symbol in zip(asset_tabs, ["XAUUSD", "EURUSD"]):
            with asset_tab:
                with st.container(border=True):
                    st.markdown(f'<div class="asset-label">{symbol}</div>', unsafe_allow_html=True)
                    button_cols = st.columns(len(actions))
                    for col, (action, label, style_class) in zip(button_cols, actions):
                        with col:
                            st.markdown(f'<div class="{style_class}">', unsafe_allow_html=True)
                            clicked = st.button(label, key=f"global_{symbol}_{action}", use_container_width=True)
                            st.markdown('</div>', unsafe_allow_html=True)
                    
                            if clicked:
                                if not selected_terminals:
                                    st.warning("Select at least one terminal")
                                elif not global_trading_enabled:
                                    st.warning("Trading is suspended")
                                else:
                                    st.session_state.global_results = send_action_to_terminals(
                                        selected_terminals,
                                        symbol,
                                        action,
                                    )

        st.markdown('<div class="active-accounts-label"><strong>Active Accounts</strong></div>', unsafe_allow_html=True)
        for terminal_id in terminals:
            toggle_key = f"terminal_toggle_{terminal_id}"
            col1, col2 = st.columns([3, 1])
        
            with col1:
                status_icon = "🟢" if st.session_state[toggle_key] else "🔴"
                st.markdown(f"{terminal_id} {status_icon}")
        
            with col2:
                st.toggle(
                    "ON/OFF",
                    key=toggle_key,
                    label_visibility="collapsed",
                )
                

        if st.session_state.global_results:
            st.markdown("<div style='height: 0.35rem;'></div>", unsafe_allow_html=True)
            st.subheader("Execution Results")
            for result in st.session_state.global_results:
                terminal_id = result.get("terminal_id", "unknown")
                status = "SUCCESS" if result.get("success") else "FAILURE"
                details = []

                if result.get("action_id"):
                    details.append(f"action_id={result.get('action_id')}")
                if result.get("timestamp"):
                    details.append(f"timestamp={result.get('timestamp')}")
                if result.get("error"):
                    details.append(f"error={result.get('error')}")

                detail_text = " | ".join(details)
                line = f"{terminal_id}: {status}"
                if detail_text:
                    line += f" | {detail_text}"

                if result.get("success"):
                    st.success(line)
                else:
                    st.error(line)

with multibroker_tab:
    st.info("Coming in next phase")

with metrics_tab:
    st.info("Coming in next phase")
