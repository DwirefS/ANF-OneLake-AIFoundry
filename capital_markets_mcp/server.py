#!/usr/bin/env python3
"""
Capital Markets MCP Server
===========================
Live market data tools for the ANF-OneLake-AIFoundry Capital Markets Agent.

Provides real-time stock quotes, options chains, earnings history, macroeconomic
indicators, sector performance, and portfolio analytics via yfinance + FRED API.

Transport: stdio (for local Claude Desktop / Cowork) or HTTP (for Foundry Agent)

Installation:
    pip install fastmcp yfinance httpx pydantic

Run (stdio):
    python server.py

Run (HTTP for Foundry Agent Actions):
    python server.py --http --port 8000

Author: ANF-OneLake-AIFoundry Capital Markets Lab
"""

import json
import asyncio
from typing import Optional, List, Dict, Any
from enum import Enum
from datetime import datetime, date, timedelta
import httpx
from pydantic import BaseModel, Field, field_validator, ConfigDict
from mcp.server.fastmcp import FastMCP

# ── Server Init ────────────────────────────────────────────────────────────────
mcp = FastMCP(
    "capital_markets_mcp",
    instructions=(
        "You are a capital markets data assistant. Use these tools to fetch LIVE "
        "market data: stock quotes, options chains, earnings, macro indicators, and "
        "sector performance. Combine with the RAG knowledge base (static documents) "
        "to answer comprehensive capital markets questions."
    )
)

# ── Constants ──────────────────────────────────────────────────────────────────
FRED_BASE = "https://api.stlouisfed.org/fred/series/observations"
FRED_API_KEY = "your-fred-api-key"   # Replace with real key from https://fred.stlouisfed.org/docs/api/api_key.html (free)

SECTOR_ETFS = {
    "Technology": "XLK", "Financials": "XLF", "Healthcare": "XLV",
    "Energy": "XLE", "Industrials": "XLI", "Consumer Discretionary": "XLY",
    "Consumer Staples": "XLP", "Materials": "XLB", "Real Estate": "XLRE",
    "Utilities": "XLU", "Communication Services": "XLC",
}

FRED_SERIES = {
    "fed_funds_rate": "FEDFUNDS",
    "cpi_yoy": "CPIAUCSL",
    "gdp_growth": "A191RL1Q225SBEA",
    "unemployment": "UNRATE",
    "10y_treasury": "GS10",
    "2y_treasury": "GS2",
    "vix": "VIXCLS",
    "usd_index": "DTWEXBGS",
    "m2_money_supply": "M2SL",
    "corp_bond_spread": "BAMLH0A0HYM2",
}


# ── Shared Utilities ───────────────────────────────────────────────────────────

def _fmt_num(v, prefix="$", decimals=2, suffix="") -> str:
    """Format a number with K/M/B/T suffixes."""
    if v is None:
        return "N/A"
    try:
        v = float(v)
        if abs(v) >= 1e12:
            return f"{prefix}{v/1e12:.{decimals}f}T{suffix}"
        if abs(v) >= 1e9:
            return f"{prefix}{v/1e9:.{decimals}f}B{suffix}"
        if abs(v) >= 1e6:
            return f"{prefix}{v/1e6:.{decimals}f}M{suffix}"
        if abs(v) >= 1e3:
            return f"{prefix}{v/1e3:.{decimals}f}K{suffix}"
        return f"{prefix}{v:.{decimals}f}{suffix}"
    except (TypeError, ValueError):
        return "N/A"


def _safe(d: dict, *keys, default="N/A"):
    """Safely traverse nested dict keys."""
    for k in keys:
        if not isinstance(d, dict):
            return default
        d = d.get(k, default)
    return d if d not in (None, "") else default


def _handle_error(e: Exception, context: str = "") -> str:
    msg = f"Error{f' in {context}' if context else ''}: "
    if isinstance(e, httpx.TimeoutException):
        return msg + "Request timed out. Try again shortly."
    if isinstance(e, httpx.HTTPStatusError):
        if e.response.status_code == 404:
            return msg + "Ticker not found. Check the symbol and try again."
        if e.response.status_code == 429:
            return msg + "Rate limit hit. Wait a few seconds and retry."
        return msg + f"HTTP {e.response.status_code}: {e.response.text[:200]}"
    return msg + f"{type(e).__name__}: {str(e)[:300]}"


async def _yf_fetch(path: str, params: dict = None) -> dict:
    """Fetch from Yahoo Finance v8 API (no key required)."""
    base = "https://query1.finance.yahoo.com"
    async with httpx.AsyncClient(
        headers={"User-Agent": "Mozilla/5.0 (compatible; CapMarketsBot/1.0)"},
        timeout=20.0
    ) as client:
        r = await client.get(f"{base}{path}", params=params or {})
        r.raise_for_status()
        return r.json()


async def _yf_quote(ticker: str) -> dict:
    """Get full quote summary for a ticker from Yahoo Finance."""
    data = await _yf_fetch(
        f"/v8/finance/spark",
        {"symbols": ticker, "range": "1d", "interval": "5m"}
    )
    # Also get quote detail
    quote_data = await _yf_fetch(
        f"/v7/finance/quote",
        {"symbols": ticker, "fields": ",".join([
            "symbol","longName","shortName","regularMarketPrice",
            "regularMarketChange","regularMarketChangePercent",
            "regularMarketVolume","marketCap","trailingPE","forwardPE",
            "fiftyTwoWeekHigh","fiftyTwoWeekLow","averageVolume",
            "dividendYield","beta","epsTrailingTwelveMonths","currency",
            "regularMarketOpen","regularMarketDayHigh","regularMarketDayLow",
            "regularMarketPreviousClose","priceToBook","earningsTimestamp"
        ])}
    )
    results = quote_data.get("quoteResponse", {}).get("result", [])
    return results[0] if results else {}


# ── Pydantic Input Models ──────────────────────────────────────────────────────

class TickerInput(BaseModel):
    """Single ticker input."""
    model_config = ConfigDict(str_strip_whitespace=True, validate_assignment=True)
    ticker: str = Field(..., description="Stock ticker symbol (e.g. 'AAPL', 'MSFT', 'SPY')", min_length=1, max_length=10)

    @field_validator("ticker")
    @classmethod
    def upper_ticker(cls, v: str) -> str:
        return v.upper().strip()


class MultiTickerInput(BaseModel):
    """Multiple tickers for comparison."""
    model_config = ConfigDict(str_strip_whitespace=True)
    tickers: List[str] = Field(..., description="List of ticker symbols to compare (e.g. ['AAPL','MSFT','GOOGL'])", min_length=1, max_length=10)

    @field_validator("tickers")
    @classmethod
    def upper_tickers(cls, v: List[str]) -> List[str]:
        return [t.upper().strip() for t in v]


class OptionsInput(BaseModel):
    """Options chain input."""
    model_config = ConfigDict(str_strip_whitespace=True)
    ticker: str = Field(..., description="Underlying stock ticker (e.g. 'SPY', 'AAPL', 'QQQ')", min_length=1, max_length=10)
    option_type: Optional[str] = Field(default="both", description="'call', 'put', or 'both' (default: 'both')")
    expiry_index: Optional[int] = Field(default=0, description="Index of expiry date to fetch (0=nearest, 1=next, etc.)", ge=0, le=10)

    @field_validator("ticker")
    @classmethod
    def upper_ticker(cls, v: str) -> str:
        return v.upper().strip()

    @field_validator("option_type")
    @classmethod
    def validate_opt_type(cls, v: str) -> str:
        v = v.lower()
        if v not in ("call", "put", "both"):
            raise ValueError("option_type must be 'call', 'put', or 'both'")
        return v


class MacroInput(BaseModel):
    """Macroeconomic indicator input."""
    model_config = ConfigDict(str_strip_whitespace=True)
    indicator: str = Field(
        ...,
        description=(
            "Economic indicator key. Choose from: "
            "'fed_funds_rate', 'cpi_yoy', 'gdp_growth', 'unemployment', "
            "'10y_treasury', '2y_treasury', 'vix', 'usd_index', "
            "'m2_money_supply', 'corp_bond_spread'"
        )
    )
    lookback_months: Optional[int] = Field(default=24, description="How many months of history to return (default: 24, max: 120)", ge=1, le=120)

    @field_validator("indicator")
    @classmethod
    def validate_indicator(cls, v: str) -> str:
        v = v.lower().strip()
        if v not in FRED_SERIES:
            raise ValueError(f"Unknown indicator '{v}'. Valid: {list(FRED_SERIES.keys())}")
        return v


class EarningsInput(BaseModel):
    """Earnings history input."""
    model_config = ConfigDict(str_strip_whitespace=True)
    ticker: str = Field(..., description="Stock ticker (e.g. 'AAPL', 'MSFT')", min_length=1, max_length=10)
    quarters: Optional[int] = Field(default=8, description="Number of recent quarters to return (default: 8, max: 20)", ge=1, le=20)

    @field_validator("ticker")
    @classmethod
    def upper_ticker(cls, v: str) -> str:
        return v.upper().strip()


class PortfolioInput(BaseModel):
    """Portfolio analytics input."""
    model_config = ConfigDict(str_strip_whitespace=True)
    holdings: Dict[str, float] = Field(
        ...,
        description=(
            "Dict mapping ticker -> weight (0-1). Weights should sum to ~1.0. "
            "Example: {'AAPL': 0.30, 'MSFT': 0.25, 'GOOGL': 0.20, 'JPM': 0.25}"
        )
    )

    @field_validator("holdings")
    @classmethod
    def validate_holdings(cls, v: Dict[str, float]) -> Dict[str, float]:
        if not v:
            raise ValueError("Holdings dict cannot be empty")
        if len(v) > 30:
            raise ValueError("Max 30 holdings per portfolio")
        return {k.upper(): float(w) for k, w in v.items()}


# ── Tools ──────────────────────────────────────────────────────────────────────

@mcp.tool(
    name="market_get_quote",
    annotations={
        "title": "Get Live Stock Quote",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_get_quote(params: TickerInput) -> str:
    """Get a comprehensive real-time stock quote for a single ticker.

    Returns price, change, P/E, market cap, 52-week range, volume, dividend
    yield, beta, EPS, and next earnings date. Data sourced from Yahoo Finance.

    Args:
        params (TickerInput):
            - ticker (str): Stock symbol (e.g. 'AAPL', 'SPY', 'BRK.B')

    Returns:
        str: Markdown-formatted quote with key metrics

    Examples:
        - "What is NVDA trading at right now?" -> market_get_quote(ticker='NVDA')
        - "Give me a full quote for Tesla" -> market_get_quote(ticker='TSLA')
        - "What's the current S&P 500 ETF price?" -> market_get_quote(ticker='SPY')
    """
    try:
        q = await _yf_quote(params.ticker)
        if not q:
            return f"No data found for ticker '{params.ticker}'. Verify the symbol is correct."

        name = _safe(q, "longName") or _safe(q, "shortName", default=params.ticker)
        price = _safe(q, "regularMarketPrice")
        chg = _safe(q, "regularMarketChange")
        chg_pct = _safe(q, "regularMarketChangePercent")
        prev_close = _safe(q, "regularMarketPreviousClose")
        open_p = _safe(q, "regularMarketOpen")
        day_high = _safe(q, "regularMarketDayHigh")
        day_low = _safe(q, "regularMarketDayLow")
        volume = _safe(q, "regularMarketVolume")
        avg_vol = _safe(q, "averageVolume")
        mkt_cap = _safe(q, "marketCap")
        pe = _safe(q, "trailingPE")
        fwd_pe = _safe(q, "forwardPE")
        w52h = _safe(q, "fiftyTwoWeekHigh")
        w52l = _safe(q, "fiftyTwoWeekLow")
        eps = _safe(q, "epsTrailingTwelveMonths")
        div_yield = _safe(q, "dividendYield")
        beta = _safe(q, "beta")
        pb = _safe(q, "priceToBook")
        currency = _safe(q, "currency", default="USD")

        direction = "▲" if isinstance(chg, float) and chg >= 0 else "▼"
        chg_str = f"{direction} {abs(chg):.2f} ({abs(chg_pct):.2f}%)" if isinstance(chg, float) else "N/A"

        # 52-week position
        if isinstance(price, float) and isinstance(w52h, float) and isinstance(w52l, float) and w52h > w52l:
            pct_range = (price - w52l) / (w52h - w52l) * 100
            range_bar = "█" * int(pct_range / 10) + "░" * (10 - int(pct_range / 10))
            range_str = f"[{range_bar}] {pct_range:.0f}% of 52W range"
        else:
            range_str = "N/A"

        lines = [
            f"# {name} ({params.ticker}) — Live Quote",
            f"**Price**: {currency} {price:.2f}  {chg_str}",
            "",
            "## Price Action",
            f"| Metric | Value |",
            f"|--------|-------|",
            f"| Open | {open_p:.2f} |" if isinstance(open_p, float) else "| Open | N/A |",
            f"| Day High | {day_high:.2f} |" if isinstance(day_high, float) else "| Day High | N/A |",
            f"| Day Low | {day_low:.2f} |" if isinstance(day_low, float) else "| Day Low | N/A |",
            f"| Prev Close | {prev_close:.2f} |" if isinstance(prev_close, float) else "| Prev Close | N/A |",
            f"| 52W High | {w52h:.2f} |" if isinstance(w52h, float) else "| 52W High | N/A |",
            f"| 52W Low | {w52l:.2f} |" if isinstance(w52l, float) else "| 52W Low | N/A |",
            f"| 52W Position | {range_str} |",
            "",
            "## Fundamentals",
            f"| Metric | Value |",
            f"|--------|-------|",
            f"| Market Cap | {_fmt_num(mkt_cap)} |",
            f"| Trailing P/E | {pe:.1f}x |" if isinstance(pe, float) else "| Trailing P/E | N/A |",
            f"| Forward P/E | {fwd_pe:.1f}x |" if isinstance(fwd_pe, float) else "| Forward P/E | N/A |",
            f"| P/B Ratio | {pb:.2f}x |" if isinstance(pb, float) else "| P/B Ratio | N/A |",
            f"| EPS (TTM) | ${eps:.2f} |" if isinstance(eps, float) else "| EPS (TTM) | N/A |",
            f"| Dividend Yield | {div_yield*100:.2f}% |" if isinstance(div_yield, float) else "| Dividend Yield | None |",
            f"| Beta | {beta:.2f} |" if isinstance(beta, float) else "| Beta | N/A |",
            "",
            "## Volume",
            f"| Metric | Value |",
            f"|--------|-------|",
            f"| Volume | {_fmt_num(volume, prefix='')} shares |",
            f"| Avg Volume | {_fmt_num(avg_vol, prefix='')} shares |",
            "",
            f"*Data from Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*"
        ]
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, f"market_get_quote({params.ticker})")


@mcp.tool(
    name="market_get_options_chain",
    annotations={
        "title": "Get Options Chain",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_get_options_chain(params: OptionsInput) -> str:
    """Fetch the live options chain for a ticker — strikes near the money with Greeks proxy.

    Returns calls and/or puts for the selected expiry: strike, bid, ask, last,
    volume, open interest, implied volatility, and in/out-of-the-money status.

    Args:
        params (OptionsInput):
            - ticker (str): Underlying symbol (e.g. 'SPY', 'AAPL', 'QQQ')
            - option_type (str): 'call', 'put', or 'both' (default: 'both')
            - expiry_index (int): Which expiry date to use, 0=nearest (default: 0)

    Returns:
        str: Markdown table of the options chain with 10 near-the-money strikes
    """
    try:
        # Get available expiry dates
        exp_data = await _yf_fetch(f"/v7/finance/options/{params.ticker}")
        result = exp_data.get("optionChain", {}).get("result", [])
        if not result:
            return f"No options data for '{params.ticker}'. Check the symbol."

        all_dates = result[0].get("expirationDates", [])
        if not all_dates:
            return f"No expiry dates found for '{params.ticker}'."

        idx = min(params.expiry_index, len(all_dates) - 1)
        expiry_ts = all_dates[idx]
        expiry_str = datetime.fromtimestamp(expiry_ts).strftime("%Y-%m-%d")

        # Fetch chain for chosen expiry
        chain_data = await _yf_fetch(
            f"/v7/finance/options/{params.ticker}",
            {"date": str(expiry_ts)}
        )
        chain_result = chain_data.get("optionChain", {}).get("result", [])
        if not chain_result:
            return f"Could not load chain for {params.ticker} expiry {expiry_str}."

        spot = chain_result[0].get("quote", {}).get("regularMarketPrice", 0)
        calls = chain_result[0].get("options", [{}])[0].get("calls", [])
        puts  = chain_result[0].get("options", [{}])[0].get("puts", [])

        def _fmt_chain(contracts, ctype):
            if not contracts:
                return f"No {ctype}s data available.\n"
            # Sort by proximity to spot price
            contracts.sort(key=lambda x: abs(x.get("strike", 0) - spot))
            near_money = contracts[:12]
            near_money.sort(key=lambda x: x.get("strike", 0))

            lines = [f"\n### {ctype.title()}s  (expiry {expiry_str})\n"]
            lines.append("| Strike | Bid | Ask | Last | IV% | Vol | OI | ITM |")
            lines.append("|--------|-----|-----|------|-----|-----|----|-----|")
            for c in near_money:
                strike = c.get("strike", 0)
                bid    = c.get("bid", 0)
                ask    = c.get("ask", 0)
                last   = c.get("lastPrice", 0)
                iv     = c.get("impliedVolatility", 0) * 100
                vol    = c.get("volume", 0) or 0
                oi     = c.get("openInterest", 0) or 0
                itm    = "✓" if c.get("inTheMoney") else ""
                lines.append(f"| {strike:.1f} | {bid:.2f} | {ask:.2f} | {last:.2f} | {iv:.1f}% | {vol:,} | {oi:,} | {itm} |")
            return "\n".join(lines)

        lines = [
            f"# {params.ticker} Options Chain",
            f"**Spot Price**: ${spot:.2f}  |  **Expiry**: {expiry_str}  |  "
            f"**All expirations**: {', '.join(datetime.fromtimestamp(d).strftime('%b %d') for d in all_dates[:6])}",
        ]
        if params.option_type in ("call", "both"):
            lines.append(_fmt_chain(calls, "call"))
        if params.option_type in ("put", "both"):
            lines.append(_fmt_chain(puts, "put"))

        lines.append(f"\n*Data from Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*")
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, f"market_get_options_chain({params.ticker})")


@mcp.tool(
    name="market_get_earnings",
    annotations={
        "title": "Get Earnings History & Estimates",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_get_earnings(params: EarningsInput) -> str:
    """Get quarterly earnings history: EPS estimates vs actuals, surprise %, and revenue.

    Shows beat/miss/in-line streak, average surprise, and next earnings date.
    Useful for fundamental analysis and earnings momentum strategies.

    Args:
        params (EarningsInput):
            - ticker (str): Company ticker (e.g. 'AAPL', 'MSFT', 'NVDA')
            - quarters (int): How many recent quarters to show (default: 8)

    Returns:
        str: Markdown table of quarterly earnings results with surprise analysis
    """
    try:
        data = await _yf_fetch(
            f"/v10/finance/quoteSummary/{params.ticker}",
            {"modules": "earningsHistory,earningsTrend,calendarEvents"}
        )
        summary = data.get("quoteSummary", {}).get("result", [{}])[0]

        # Historical quarters
        history = summary.get("earningsHistory", {}).get("history", [])
        history = sorted(history, key=lambda x: x.get("quarter", {}).get("raw", 0), reverse=True)
        history = history[:params.quarters]

        # Next earnings date
        calendar = summary.get("calendarEvents", {}).get("earnings", {})
        next_dates = calendar.get("earningsDate", [])
        next_date_str = ""
        if next_dates:
            ts = next_dates[0].get("raw", 0)
            next_date_str = datetime.fromtimestamp(ts).strftime("%Y-%m-%d") if ts else ""

        # Trend / analyst estimates
        trend = summary.get("earningsTrend", {}).get("trend", [{}])
        curr_quarter = next((t for t in trend if t.get("period") == "0q"), {})
        est_eps = curr_quarter.get("earningsEstimate", {}).get("avg", {}).get("raw", None)
        est_rev = curr_quarter.get("revenueEstimate", {}).get("avg", {}).get("raw", None)

        lines = [
            f"# {params.ticker} — Earnings History & Estimates",
        ]
        if next_date_str:
            lines.append(f"**Next Earnings**: {next_date_str}")
        if est_eps is not None:
            lines.append(f"**Current Quarter EPS Estimate**: ${est_eps:.2f}")
        if est_rev is not None:
            lines.append(f"**Current Quarter Revenue Estimate**: {_fmt_num(est_rev)}")
        lines.append("")

        if not history:
            lines.append("No earnings history available for this ticker.")
            return "\n".join(lines)

        lines.append("## Quarterly Results\n")
        lines.append("| Quarter | EPS Est | EPS Actual | Surprise | Surprise% | Rev Est | Rev Actual |")
        lines.append("|---------|---------|------------|----------|-----------|---------|------------|")

        beats = 0
        misses = 0
        surprises = []

        for q in history:
            period = q.get("quarter", {}).get("fmt", "N/A")
            eps_est = q.get("epsEstimate", {}).get("raw")
            eps_act = q.get("epsActual", {}).get("raw")
            surp    = q.get("epsDifference", {}).get("raw")
            surp_pct= q.get("surprisePercent", {}).get("raw")
            rev_est = q.get("revenueEstimate", {}).get("raw")
            rev_act = q.get("revenueActual",  {}).get("raw")

            if surp_pct is not None:
                surprises.append(surp_pct)
                if surp_pct > 1:
                    beats += 1
                    badge = "✅ Beat"
                elif surp_pct < -1:
                    misses += 1
                    badge = "❌ Miss"
                else:
                    badge = "➖ In-line"
            else:
                badge = "N/A"

            lines.append(
                f"| {period} "
                f"| {'N/A' if eps_est is None else f'${eps_est:.2f}'} "
                f"| {'N/A' if eps_act is None else f'${eps_act:.2f}'} "
                f"| {badge} "
                f"| {'N/A' if surp_pct is None else f'{surp_pct:+.1f}%'} "
                f"| {_fmt_num(rev_est) if rev_est else 'N/A'} "
                f"| {_fmt_num(rev_act) if rev_act else 'N/A'} |"
            )

        total = beats + misses + (len(history) - beats - misses)
        avg_surp = sum(surprises) / len(surprises) if surprises else 0
        lines.append(f"\n**Beat Rate**: {beats}/{total} quarters ({beats/total*100:.0f}%)  |  **Avg EPS Surprise**: {avg_surp:+.1f}%")
        lines.append(f"\n*Data from Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*")
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, f"market_get_earnings({params.ticker})")


@mcp.tool(
    name="market_get_macro",
    annotations={
        "title": "Get Macroeconomic Indicator",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_get_macro(params: MacroInput) -> str:
    """Fetch macroeconomic time-series data from the Federal Reserve (FRED).

    Available indicators: Fed Funds Rate, CPI (inflation), GDP growth, Unemployment,
    2Y/10Y Treasury yields, VIX, USD Index, M2 Money Supply, HY Credit Spreads.

    Args:
        params (MacroInput):
            - indicator (str): One of: fed_funds_rate, cpi_yoy, gdp_growth, unemployment,
              10y_treasury, 2y_treasury, vix, usd_index, m2_money_supply, corp_bond_spread
            - lookback_months (int): Months of history (default: 24, max: 120)

    Returns:
        str: Markdown table of monthly values with trend analysis and current reading

    Note:
        Get a free FRED API key at https://fred.stlouisfed.org/docs/api/api_key.html
        and update FRED_API_KEY in server.py (line ~34).
    """
    try:
        series_id = FRED_SERIES[params.indicator]
        obs_start = (date.today() - timedelta(days=params.lookback_months * 31)).isoformat()

        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.get(FRED_BASE, params={
                "series_id": series_id,
                "api_key": FRED_API_KEY,
                "file_type": "json",
                "observation_start": obs_start,
                "sort_order": "desc",
                "limit": params.lookback_months
            })
            r.raise_for_status()
            data = r.json()

        observations = data.get("observations", [])
        if not observations:
            return (
                f"No data for '{params.indicator}'. If you see auth errors, "
                f"update FRED_API_KEY in server.py with your free key from "
                f"https://fred.stlouisfed.org/docs/api/api_key.html"
            )

        valid_obs = [(o["date"], o["value"]) for o in observations if o["value"] != "."]
        if not valid_obs:
            return f"No valid observations found for '{params.indicator}'."

        labels = {
            "fed_funds_rate": ("Fed Funds Rate", "%"),
            "cpi_yoy": ("CPI Year-over-Year", "%"),
            "gdp_growth": ("Real GDP Growth (QoQ Ann.)", "%"),
            "unemployment": ("Unemployment Rate", "%"),
            "10y_treasury": ("10-Year Treasury Yield", "%"),
            "2y_treasury": ("2-Year Treasury Yield", "%"),
            "vix": ("VIX (Volatility Index)", "pts"),
            "usd_index": ("USD Index (Broad)", ""),
            "m2_money_supply": ("M2 Money Supply", "B USD"),
            "corp_bond_spread": ("HY Corp Bond Spread", "%"),
        }
        label, unit = labels.get(params.indicator, (params.indicator, ""))

        current_val = float(valid_obs[0][1])
        oldest_val  = float(valid_obs[-1][1])
        trend = "▲ Rising" if current_val > oldest_val else "▼ Falling"
        change = current_val - oldest_val

        lines = [
            f"# {label} — FRED Data",
            f"**Current** ({valid_obs[0][0]}): **{current_val:.2f}{unit}**  |  "
            f"Trend vs {valid_obs[-1][0]}: {trend} ({change:+.2f}{unit})",
            "",
            f"## Monthly History (last {len(valid_obs)} readings)\n",
            f"| Date | Value |",
            f"|------|-------|",
        ]
        for dt, val in valid_obs[:24]:
            lines.append(f"| {dt} | {float(val):.2f}{unit} |")

        lines.append(f"\n*Source: Federal Reserve Bank of St. Louis (FRED) · Series: {series_id}*")
        return "\n".join(lines)

    except Exception as e:
        if "api_key" in str(e).lower() or "403" in str(e) or "400" in str(e):
            return (
                f"FRED API authentication failed. Get your free key at "
                f"https://fred.stlouisfed.org/docs/api/api_key.html and update "
                f"FRED_API_KEY in server.py"
            )
        return _handle_error(e, f"market_get_macro({params.indicator})")


@mcp.tool(
    name="market_compare_stocks",
    annotations={
        "title": "Compare Multiple Stocks",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_compare_stocks(params: MultiTickerInput) -> str:
    """Fetch and compare live quotes for 2-10 stocks side by side.

    Returns a comparison table with price, change, P/E, market cap, 52W
    performance, beta, and analyst rating context. Ideal for peer analysis.

    Args:
        params (MultiTickerInput):
            - tickers (List[str]): 2-10 ticker symbols (e.g. ['AAPL','MSFT','GOOGL'])

    Returns:
        str: Markdown comparison table with all tickers side by side
    """
    try:
        quotes = await asyncio.gather(*[_yf_quote(t) for t in params.tickers])

        lines = [
            f"# Stock Comparison: {' vs '.join(params.tickers)}",
            "",
            "| Ticker | Price | Change | Mkt Cap | P/E | Fwd P/E | Beta | Div Yield | 52W High | 52W Low |",
            "|--------|-------|--------|---------|-----|---------|------|-----------|----------|---------|",
        ]

        for ticker, q in zip(params.tickers, quotes):
            if not q:
                lines.append(f"| {ticker} | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A |")
                continue
            price    = _safe(q, "regularMarketPrice")
            chg_pct  = _safe(q, "regularMarketChangePercent")
            mkt_cap  = _safe(q, "marketCap")
            pe       = _safe(q, "trailingPE")
            fwd_pe   = _safe(q, "forwardPE")
            beta     = _safe(q, "beta")
            div      = _safe(q, "dividendYield")
            w52h     = _safe(q, "fiftyTwoWeekHigh")
            w52l     = _safe(q, "fiftyTwoWeekLow")

            chg_str  = f"{chg_pct:+.2f}%" if isinstance(chg_pct, float) else "N/A"
            cap_str  = _fmt_num(mkt_cap) if isinstance(mkt_cap, (int, float)) else "N/A"
            pe_str   = f"{pe:.1f}x" if isinstance(pe, float) else "N/A"
            fpe_str  = f"{fwd_pe:.1f}x" if isinstance(fwd_pe, float) else "N/A"
            beta_str = f"{beta:.2f}" if isinstance(beta, float) else "N/A"
            div_str  = f"{div*100:.2f}%" if isinstance(div, float) else "—"
            h52_str  = f"${w52h:.2f}" if isinstance(w52h, float) else "N/A"
            l52_str  = f"${w52l:.2f}" if isinstance(w52l, float) else "N/A"

            lines.append(
                f"| **{ticker}** | ${price:.2f} | {chg_str} | {cap_str} | "
                f"{pe_str} | {fpe_str} | {beta_str} | {div_str} | {h52_str} | {l52_str} |"
                if isinstance(price, float) else
                f"| **{ticker}** | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A |"
            )

        lines.append(f"\n*Data from Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*")
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, f"market_compare_stocks({params.tickers})")


@mcp.tool(
    name="market_get_sector_performance",
    annotations={
        "title": "Get Sector ETF Performance",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_get_sector_performance() -> str:
    """Get real-time performance for all 11 GICS sector ETFs (XLK, XLF, XLV, etc.).

    Returns current price, day change, and YTD performance for each sector.
    Useful for sector rotation analysis and macro positioning decisions.

    Returns:
        str: Ranked sector performance table sorted by day change
    """
    try:
        etf_tickers = list(SECTOR_ETFS.values())
        quotes = await asyncio.gather(*[_yf_quote(t) for t in etf_tickers])

        sector_data = []
        for (sector, etf), q in zip(SECTOR_ETFS.items(), quotes):
            if not q:
                continue
            price   = _safe(q, "regularMarketPrice")
            chg_pct = _safe(q, "regularMarketChangePercent")
            w52h    = _safe(q, "fiftyTwoWeekHigh")
            w52l    = _safe(q, "fiftyTwoWeekLow")

            # Approximate YTD from 52W data
            ytd_approx = ""
            if isinstance(price, float) and isinstance(w52l, float):
                ytd_approx = f"~{((price - w52l)/w52l*100):.1f}% (from 52W low)"

            sector_data.append({
                "sector": sector, "etf": etf,
                "price": price, "chg_pct": chg_pct, "ytd": ytd_approx
            })

        # Sort by day change descending
        sector_data.sort(
            key=lambda x: x["chg_pct"] if isinstance(x["chg_pct"], float) else -999,
            reverse=True
        )

        lines = [
            "# Sector ETF Performance (Ranked by Day Change)",
            "",
            "| Rank | Sector | ETF | Price | Day Change | vs 52W Low |",
            "|------|--------|-----|-------|------------|------------|",
        ]
        for i, s in enumerate(sector_data, 1):
            price_str = f"${s['price']:.2f}" if isinstance(s['price'], float) else "N/A"
            chg_str   = f"{s['chg_pct']:+.2f}%" if isinstance(s['chg_pct'], float) else "N/A"
            medal     = "🥇" if i == 1 else "🥈" if i == 2 else "🥉" if i == 3 else f"#{i}"
            lines.append(f"| {medal} | {s['sector']} | {s['etf']} | {price_str} | {chg_str} | {s['ytd']} |")

        best  = sector_data[0]["sector"] if sector_data else "N/A"
        worst = sector_data[-1]["sector"] if sector_data else "N/A"
        lines.append(f"\n**Leader**: {best}  |  **Laggard**: {worst}")
        lines.append(f"\n*Data from Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*")
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, "market_get_sector_performance")


@mcp.tool(
    name="market_portfolio_snapshot",
    annotations={
        "title": "Portfolio Snapshot & Analytics",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": True
    }
)
async def market_portfolio_snapshot(params: PortfolioInput) -> str:
    """Compute a live portfolio snapshot: weighted metrics, sector exposure, and risk summary.

    Fetches live quotes for each holding and computes weighted P/E, beta,
    dividend yield, sector breakdown, and total market cap exposure.

    Args:
        params (PortfolioInput):
            - holdings (Dict[str, float]): Ticker -> weight mapping.
              Example: {'AAPL': 0.30, 'MSFT': 0.25, 'NVDA': 0.25, 'JPM': 0.20}

    Returns:
        str: Portfolio analytics with weighted metrics and sector decomposition
    """
    try:
        tickers = list(params.holdings.keys())
        weights = list(params.holdings.values())
        total_weight = sum(weights)

        quotes = await asyncio.gather(*[_yf_quote(t) for t in tickers])

        # Compute weighted metrics
        w_pe = w_fpe = w_beta = w_div = 0.0
        pe_count = fpe_count = beta_count = div_count = 0
        positions = []

        for ticker, weight, q in zip(tickers, weights, quotes):
            norm_w = weight / total_weight  # normalize
            pe    = _safe(q, "trailingPE")
            fpe   = _safe(q, "forwardPE")
            beta  = _safe(q, "beta")
            div   = _safe(q, "dividendYield")
            price = _safe(q, "regularMarketPrice")
            chg   = _safe(q, "regularMarketChangePercent")
            name  = _safe(q, "shortName", default=ticker)

            if isinstance(pe, float):
                w_pe += pe * norm_w;  pe_count += 1
            if isinstance(fpe, float):
                w_fpe += fpe * norm_w;  fpe_count += 1
            if isinstance(beta, float):
                w_beta += beta * norm_w;  beta_count += 1
            if isinstance(div, float):
                w_div += div * norm_w;  div_count += 1

            positions.append({
                "ticker": ticker, "name": name, "weight": norm_w,
                "price": price, "chg": chg, "pe": pe, "beta": beta
            })

        lines = [
            f"# Portfolio Snapshot ({len(tickers)} holdings)",
            f"*Note: Weights normalized to sum to 100%*",
            "",
            "## Holdings\n",
            "| Ticker | Name | Weight | Price | Day Chg | P/E | Beta |",
            "|--------|------|--------|-------|---------|-----|------|",
        ]
        for p in sorted(positions, key=lambda x: -x["weight"]):
            price_s = f"${p['price']:.2f}" if isinstance(p['price'], float) else "N/A"
            chg_s   = f"{p['chg']:+.2f}%" if isinstance(p['chg'], float) else "N/A"
            pe_s    = f"{p['pe']:.1f}x" if isinstance(p['pe'], float) else "N/A"
            beta_s  = f"{p['beta']:.2f}" if isinstance(p['beta'], float) else "N/A"
            lines.append(f"| {p['ticker']} | {p['name'][:25]} | {p['weight']*100:.1f}% | {price_s} | {chg_s} | {pe_s} | {beta_s} |")

        lines += [
            "",
            "## Weighted Portfolio Metrics\n",
            "| Metric | Value | Interpretation |",
            "|--------|-------|----------------|",
            f"| Weighted P/E | {w_pe:.1f}x | {'Expensive vs S&P ~22x' if w_pe > 25 else 'Near-market valuation' if w_pe > 18 else 'Value-tilted'} |",
            f"| Weighted Fwd P/E | {w_fpe:.1f}x | {'Growth premium' if w_fpe > 22 else 'Reasonable'} |",
            f"| Weighted Beta | {w_beta:.2f} | {'Aggressive vs market' if w_beta > 1.2 else 'Roughly market-neutral' if w_beta > 0.85 else 'Defensive'} |",
            f"| Weighted Div Yield | {w_div*100:.2f}% | {'Income-oriented' if w_div > 0.02 else 'Growth-oriented'} |",
            "",
            f"*Data from Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*"
        ]
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, "market_portfolio_snapshot")


@mcp.tool(
    name="market_get_news",
    annotations={
        "title": "Get Latest Financial News for Ticker",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True
    }
)
async def market_get_news(params: TickerInput) -> str:
    """Fetch the latest financial news headlines for a stock ticker from Yahoo Finance.

    Returns up to 10 recent news items: title, publisher, time, and summary.

    Args:
        params (TickerInput):
            - ticker (str): Stock symbol (e.g. 'AAPL', 'TSLA', 'SPY')

    Returns:
        str: Markdown list of recent news headlines with timestamps
    """
    try:
        data = await _yf_fetch(
            f"/v1/finance/search",
            {"q": params.ticker, "newsCount": 10, "quotesCount": 0}
        )
        news = data.get("news", [])
        if not news:
            return f"No recent news found for '{params.ticker}'."

        lines = [f"# Latest News: {params.ticker}", ""]
        for i, article in enumerate(news[:10], 1):
            title     = article.get("title", "No title")
            publisher = article.get("publisher", "Unknown")
            ts        = article.get("providerPublishTime", 0)
            pub_time  = datetime.fromtimestamp(ts).strftime("%b %d %H:%M") if ts else "N/A"
            url       = article.get("link", "#")
            lines.append(f"{i}. **{title}**")
            lines.append(f"   *{publisher} · {pub_time}*  [{url}]({url})")
            lines.append("")

        lines.append(f"*Source: Yahoo Finance · {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}*")
        return "\n".join(lines)

    except Exception as e:
        return _handle_error(e, f"market_get_news({params.ticker})")


# ── Entry Point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    if "--http" in sys.argv:
        port = 8000
        for i, arg in enumerate(sys.argv):
            if arg == "--port" and i + 1 < len(sys.argv):
                port = int(sys.argv[i + 1])
        print(f"Starting Capital Markets MCP Server on HTTP port {port}...")
        mcp.run(transport="streamable-http", host="0.0.0.0", port=port)
    else:
        mcp.run()  # stdio for Claude Desktop / Cowork
