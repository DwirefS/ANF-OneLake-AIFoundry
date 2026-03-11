"""
Capital Markets Azure Functions — Tool Calling API for Azure AI Foundry Agent
=============================================================================
Exposes 8 financial data endpoints as Azure Functions (HTTP triggers).
Designed to be connected as "OpenAPI 3.0 specified tool" Actions in
Azure AI Foundry Agent Service.

Data Sources:
  - Yahoo Finance (yfinance library) — stocks, options, earnings, news
  - FRED (Federal Reserve) — macroeconomic indicators

Deployment:
  az functionapp create ... --runtime python --runtime-version 3.11
  func azure functionapp publish <app-name>

Author: ANF-OneLake-AIFoundry Capital Markets Lab
"""

import azure.functions as func
import json
import asyncio
import logging
from typing import Optional, List, Dict, Any
from datetime import datetime, date, timedelta
from functools import lru_cache

import httpx
import yfinance as yf

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# ── Configuration ─────────────────────────────────────────────────────────────
FRED_BASE = "https://api.stlouisfed.org/fred/series/observations"
FRED_API_KEY = "your-fred-api-key"  # Replace with your free key from https://fred.stlouisfed.org/docs/api/api_key.html

SECTOR_ETFS = {
    "Technology": "XLK", "Financials": "XLF", "Healthcare": "XLV",
    "Energy": "XLE", "Industrials": "XLI", "Consumer Discretionary": "XLY",
    "Consumer Staples": "XLP", "Materials": "XLB", "Real Estate": "XLRE",
    "Utilities": "XLU", "Communication Services": "XLC",
}

FRED_SERIES = {
    "fed_funds_rate": "FEDFUNDS", "cpi_yoy": "CPIAUCSL",
    "gdp_growth": "A191RL1Q225SBEA", "unemployment": "UNRATE",
    "10y_treasury": "GS10", "2y_treasury": "GS2", "vix": "VIXCLS",
    "usd_index": "DTWEXBGS", "m2_money_supply": "M2SL",
    "corp_bond_spread": "BAMLH0A0HYM2",
}


# ── Shared Utilities ──────────────────────────────────────────────────────────

def _fmt_num(v, prefix="$", decimals=2, suffix="") -> str:
    if v is None:
        return "N/A"
    try:
        v = float(v)
        if abs(v) >= 1e12: return f"{prefix}{v/1e12:.{decimals}f}T{suffix}"
        if abs(v) >= 1e9:  return f"{prefix}{v/1e9:.{decimals}f}B{suffix}"
        if abs(v) >= 1e6:  return f"{prefix}{v/1e6:.{decimals}f}M{suffix}"
        if abs(v) >= 1e3:  return f"{prefix}{v/1e3:.{decimals}f}K{suffix}"
        return f"{prefix}{v:.{decimals}f}{suffix}"
    except (TypeError, ValueError):
        return "N/A"


def _safe(d: dict, *keys, default="N/A"):
    for k in keys:
        if not isinstance(d, dict): return default
        d = d.get(k, default)
    return d if d not in (None, "") else default


def _error_response(e: Exception, context: str = "") -> func.HttpResponse:
    msg = f"Error{f' in {context}' if context else ''}: {type(e).__name__}: {str(e)[:300]}"
    logging.error(msg)
    return func.HttpResponse(
        json.dumps({"error": msg}),
        status_code=500,
        mimetype="application/json"
    )


def _json_response(data: Any, status_code: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(data, default=str),
        status_code=status_code,
        mimetype="application/json"
    )


# ── yfinance helpers (synchronous — wrapped with asyncio.to_thread) ──────────

def _yf_get_info(ticker: str) -> dict:
    """Get ticker info dict via yfinance (handles Yahoo auth internally)."""
    t = yf.Ticker(ticker)
    return t.info or {}


def _yf_get_fast_info(ticker: str) -> dict:
    """Get fast_info for price data — lighter weight than full .info."""
    t = yf.Ticker(ticker)
    info = t.info or {}
    return info


def _yf_get_options_data(ticker: str, expiry_index: int = 0):
    """Get options chain data via yfinance."""
    t = yf.Ticker(ticker)
    expiry_dates = t.options  # tuple of date strings
    if not expiry_dates:
        return None, [], None, None
    idx = min(expiry_index, len(expiry_dates) - 1)
    expiry_str = expiry_dates[idx]
    chain = t.option_chain(expiry_str)
    spot = (t.info or {}).get("regularMarketPrice", 0) or (t.info or {}).get("currentPrice", 0)
    return expiry_str, list(expiry_dates[:8]), chain, spot


def _yf_get_earnings(ticker: str, quarters: int = 8):
    """Get earnings history via yfinance."""
    t = yf.Ticker(ticker)
    # earnings_history is a DataFrame
    hist = t.earnings_history
    calendar = t.calendar
    return hist, calendar, t.info or {}


def _yf_get_news(ticker: str) -> list:
    """Get news for a ticker via yfinance."""
    t = yf.Ticker(ticker)
    return t.news or []


def _yf_get_multiple_info(tickers: list) -> list:
    """Get info for multiple tickers efficiently."""
    results = []
    for ticker in tickers:
        try:
            t = yf.Ticker(ticker)
            results.append(t.info or {})
        except Exception:
            results.append({})
    return results


# ── Tool 1: Get Stock Quote ──────────────────────────────────────────────────

@app.route(route="tools/market_get_quote", methods=["POST"])
async def market_get_quote(req: func.HttpRequest) -> func.HttpResponse:
    """Get comprehensive real-time stock quote for a single ticker."""
    try:
        body = req.get_json()
        ticker = body.get("ticker", "").upper().strip()
        if not ticker:
            return _json_response({"error": "ticker is required"}, 400)

        q = await asyncio.to_thread(_yf_get_info, ticker)
        if not q or "regularMarketPrice" not in q:
            return _json_response({"error": f"No data found for '{ticker}'"}, 404)

        price = q.get("regularMarketPrice") or q.get("currentPrice")
        chg = q.get("regularMarketChange")
        chg_pct = q.get("regularMarketChangePercent")
        w52h = q.get("fiftyTwoWeekHigh")
        w52l = q.get("fiftyTwoWeekLow")

        result = {
            "ticker": ticker,
            "name": q.get("longName") or q.get("shortName", ticker),
            "price": price,
            "change": round(chg, 2) if isinstance(chg, (int, float)) else None,
            "change_percent": round(chg_pct, 2) if isinstance(chg_pct, (int, float)) else None,
            "currency": q.get("currency", "USD"),
            "open": q.get("regularMarketOpen") or q.get("open"),
            "day_high": q.get("regularMarketDayHigh") or q.get("dayHigh"),
            "day_low": q.get("regularMarketDayLow") or q.get("dayLow"),
            "prev_close": q.get("regularMarketPreviousClose") or q.get("previousClose"),
            "volume": q.get("regularMarketVolume") or q.get("volume"),
            "avg_volume": q.get("averageVolume"),
            "market_cap": q.get("marketCap"),
            "market_cap_formatted": _fmt_num(q.get("marketCap")),
            "trailing_pe": round(q.get("trailingPE"), 2) if isinstance(q.get("trailingPE"), (int, float)) else None,
            "forward_pe": round(q.get("forwardPE"), 2) if isinstance(q.get("forwardPE"), (int, float)) else None,
            "eps_ttm": q.get("trailingEps"),
            "dividend_yield": round(q.get("dividendYield", 0) * 100, 2) if isinstance(q.get("dividendYield"), (int, float)) else None,
            "beta": round(q.get("beta"), 2) if isinstance(q.get("beta"), (int, float)) else None,
            "price_to_book": round(q.get("priceToBook"), 2) if isinstance(q.get("priceToBook"), (int, float)) else None,
            "fifty_two_week_high": w52h,
            "fifty_two_week_low": w52l,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "source": "Yahoo Finance"
        }
        return _json_response(result)

    except Exception as e:
        return _error_response(e, "market_get_quote")


# ── Tool 2: Get Options Chain ────────────────────────────────────────────────

@app.route(route="tools/market_get_options_chain", methods=["POST"])
async def market_get_options_chain(req: func.HttpRequest) -> func.HttpResponse:
    """Fetch live options chain for a ticker — strikes near the money."""
    try:
        body = req.get_json()
        ticker = body.get("ticker", "").upper().strip()
        option_type = body.get("option_type", "both").lower()
        expiry_index = int(body.get("expiry_index", 0))

        if not ticker:
            return _json_response({"error": "ticker is required"}, 400)

        expiry_str, all_expiries, chain, spot = await asyncio.to_thread(
            _yf_get_options_data, ticker, expiry_index
        )

        if chain is None:
            return _json_response({"error": f"No options data for '{ticker}'"}, 404)

        def _format_df_contracts(df, spot_price):
            """Format a pandas DataFrame of options contracts to list of dicts."""
            if df is None or df.empty:
                return []
            # Sort by distance from spot
            df = df.copy()
            df["_dist"] = (df["strike"] - spot_price).abs()
            df = df.nsmallest(12, "_dist").sort_values("strike")
            result = []
            for _, row in df.iterrows():
                result.append({
                    "strike": row.get("strike"),
                    "bid": row.get("bid", 0),
                    "ask": row.get("ask", 0),
                    "last_price": row.get("lastPrice", 0),
                    "implied_volatility": round(row.get("impliedVolatility", 0) * 100, 1),
                    "volume": int(row.get("volume", 0) or 0),
                    "open_interest": int(row.get("openInterest", 0) or 0),
                    "in_the_money": bool(row.get("inTheMoney", False))
                })
            return result

        response = {
            "ticker": ticker, "spot_price": spot, "expiry_date": expiry_str,
            "available_expiries": all_expiries,
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Yahoo Finance"
        }
        if option_type in ("call", "both"):
            response["calls"] = _format_df_contracts(chain.calls, spot)
        if option_type in ("put", "both"):
            response["puts"] = _format_df_contracts(chain.puts, spot)

        return _json_response(response)

    except Exception as e:
        return _error_response(e, "market_get_options_chain")


# ── Tool 3: Get Earnings ─────────────────────────────────────────────────────

@app.route(route="tools/market_get_earnings", methods=["POST"])
async def market_get_earnings(req: func.HttpRequest) -> func.HttpResponse:
    """Get quarterly earnings history: EPS estimates vs actuals, surprise %."""
    try:
        body = req.get_json()
        ticker = body.get("ticker", "").upper().strip()
        quarters = int(body.get("quarters", 8))

        if not ticker:
            return _json_response({"error": "ticker is required"}, 400)

        hist, calendar, info = await asyncio.to_thread(_yf_get_earnings, ticker, quarters)

        # Process earnings history DataFrame
        earnings_data = []
        beats = misses = 0
        surprises = []

        if hist is not None and not hist.empty:
            # earnings_history DataFrame has columns like:
            # Surprise(%), EPS Estimate, Reported EPS, Quarter
            for idx, row in hist.head(quarters).iterrows():
                eps_est = row.get("epsEstimate") if "epsEstimate" in hist.columns else row.get("EPS Estimate")
                eps_act = row.get("epsActual") if "epsActual" in hist.columns else row.get("Reported EPS")
                surp_pct = row.get("surprisePercent") if "surprisePercent" in hist.columns else row.get("Surprise(%)")

                # Convert to float safely
                try: eps_est = float(eps_est) if eps_est is not None else None
                except (ValueError, TypeError): eps_est = None
                try: eps_act = float(eps_act) if eps_act is not None else None
                except (ValueError, TypeError): eps_act = None
                try: surp_pct = float(surp_pct) if surp_pct is not None else None
                except (ValueError, TypeError): surp_pct = None

                if surp_pct is not None:
                    surprises.append(surp_pct)
                    if surp_pct > 1: beats += 1
                    elif surp_pct < -1: misses += 1

                # Format quarter label from index
                quarter_label = str(idx)[:10] if idx is not None else "N/A"

                earnings_data.append({
                    "quarter": quarter_label,
                    "eps_estimate": eps_est,
                    "eps_actual": eps_act,
                    "surprise_percent": round(surp_pct, 1) if surp_pct is not None else None,
                    "beat": surp_pct > 1 if surp_pct is not None else None
                })

        # Get next earnings date
        next_date = None
        if calendar is not None:
            if isinstance(calendar, dict):
                ed = calendar.get("Earnings Date")
                if ed:
                    if isinstance(ed, list) and len(ed) > 0:
                        next_date = str(ed[0])[:10]
                    else:
                        next_date = str(ed)[:10]
            elif hasattr(calendar, "get"):
                ed = calendar.get("Earnings Date")
                if ed is not None:
                    next_date = str(ed)[:10]

        total = len(earnings_data)
        response = {
            "ticker": ticker, "next_earnings_date": next_date,
            "quarters": earnings_data,
            "summary": {
                "beat_rate": f"{beats}/{total}" if total else "N/A",
                "beat_percentage": round(beats / total * 100, 0) if total else 0,
                "avg_surprise_percent": round(sum(surprises) / len(surprises), 1) if surprises else 0,
                "beats": beats, "misses": misses, "in_line": total - beats - misses
            },
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Yahoo Finance"
        }
        return _json_response(response)

    except Exception as e:
        return _error_response(e, "market_get_earnings")


# ── Tool 4: Get Macro Indicators ─────────────────────────────────────────────

@app.route(route="tools/market_get_macro", methods=["POST"])
async def market_get_macro(req: func.HttpRequest) -> func.HttpResponse:
    """Fetch macroeconomic time-series data from FRED."""
    try:
        body = req.get_json()
        indicator = body.get("indicator", "").lower().strip()
        lookback_months = int(body.get("lookback_months", 24))

        if indicator not in FRED_SERIES:
            return _json_response({
                "error": f"Unknown indicator '{indicator}'",
                "valid_indicators": list(FRED_SERIES.keys())
            }, 400)

        series_id = FRED_SERIES[indicator]
        obs_start = (date.today() - timedelta(days=lookback_months * 31)).isoformat()

        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.get(FRED_BASE, params={
                "series_id": series_id, "api_key": FRED_API_KEY,
                "file_type": "json", "observation_start": obs_start,
                "sort_order": "desc", "limit": lookback_months
            })
            r.raise_for_status()
            data = r.json()

        observations = data.get("observations", [])
        valid_obs = [(o["date"], float(o["value"])) for o in observations if o["value"] != "."]

        if not valid_obs:
            return _json_response({"error": f"No data for '{indicator}'"}, 404)

        labels = {
            "fed_funds_rate": "Fed Funds Rate (%)", "cpi_yoy": "CPI Year-over-Year (%)",
            "gdp_growth": "Real GDP Growth QoQ Annualized (%)", "unemployment": "Unemployment Rate (%)",
            "10y_treasury": "10-Year Treasury Yield (%)", "2y_treasury": "2-Year Treasury Yield (%)",
            "vix": "VIX Volatility Index", "usd_index": "USD Index (Broad)",
            "m2_money_supply": "M2 Money Supply (Billions USD)", "corp_bond_spread": "HY Corporate Bond Spread (%)",
        }

        current = valid_obs[0][1]
        oldest = valid_obs[-1][1]

        response = {
            "indicator": indicator, "label": labels.get(indicator, indicator),
            "fred_series_id": series_id,
            "current_value": current, "current_date": valid_obs[0][0],
            "trend": "rising" if current > oldest else "falling",
            "change_from_start": round(current - oldest, 2),
            "observations": [{"date": d, "value": v} for d, v in valid_obs[:24]],
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Federal Reserve (FRED)"
        }
        return _json_response(response)

    except Exception as e:
        return _error_response(e, "market_get_macro")


# ── Tool 5: Compare Stocks ──────────────────────────────────────────────────

@app.route(route="tools/market_compare_stocks", methods=["POST"])
async def market_compare_stocks(req: func.HttpRequest) -> func.HttpResponse:
    """Compare 2-10 stocks side by side with live data."""
    try:
        body = req.get_json()
        tickers = [t.upper().strip() for t in body.get("tickers", [])]
        if not tickers or len(tickers) < 2:
            return _json_response({"error": "Provide at least 2 tickers"}, 400)
        if len(tickers) > 10:
            return _json_response({"error": "Maximum 10 tickers"}, 400)

        quotes = await asyncio.to_thread(_yf_get_multiple_info, tickers)

        comparisons = []
        for ticker, q in zip(tickers, quotes):
            if not q or "regularMarketPrice" not in q:
                comparisons.append({"ticker": ticker, "error": "No data found"})
                continue
            comparisons.append({
                "ticker": ticker,
                "name": q.get("longName") or q.get("shortName", ticker),
                "price": q.get("regularMarketPrice") or q.get("currentPrice"),
                "change_percent": round(q.get("regularMarketChangePercent", 0), 2) if isinstance(q.get("regularMarketChangePercent"), (int, float)) else None,
                "market_cap": q.get("marketCap"),
                "market_cap_formatted": _fmt_num(q.get("marketCap")),
                "trailing_pe": round(q.get("trailingPE"), 1) if isinstance(q.get("trailingPE"), (int, float)) else None,
                "forward_pe": round(q.get("forwardPE"), 1) if isinstance(q.get("forwardPE"), (int, float)) else None,
                "beta": round(q.get("beta"), 2) if isinstance(q.get("beta"), (int, float)) else None,
                "dividend_yield": round(q.get("dividendYield", 0) * 100, 2) if isinstance(q.get("dividendYield"), (int, float)) else None,
                "fifty_two_week_high": q.get("fiftyTwoWeekHigh"),
                "fifty_two_week_low": q.get("fiftyTwoWeekLow"),
            })

        return _json_response({
            "comparisons": comparisons,
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Yahoo Finance"
        })

    except Exception as e:
        return _error_response(e, "market_compare_stocks")


# ── Tool 6: Sector Performance ───────────────────────────────────────────────

@app.route(route="tools/market_get_sector_performance", methods=["POST"])
async def market_get_sector_performance(req: func.HttpRequest) -> func.HttpResponse:
    """Get real-time performance for all 11 GICS sector ETFs."""
    try:
        etf_tickers = list(SECTOR_ETFS.values())
        quotes = await asyncio.to_thread(_yf_get_multiple_info, etf_tickers)

        sectors = []
        for (sector, etf), q in zip(SECTOR_ETFS.items(), quotes):
            if not q:
                continue
            price = q.get("regularMarketPrice") or q.get("currentPrice")
            chg_pct = q.get("regularMarketChangePercent")
            sectors.append({
                "sector": sector, "etf": etf, "price": price,
                "change_percent": round(chg_pct, 2) if isinstance(chg_pct, (int, float)) else None,
                "fifty_two_week_high": q.get("fiftyTwoWeekHigh"),
                "fifty_two_week_low": q.get("fiftyTwoWeekLow"),
            })

        sectors.sort(key=lambda x: x.get("change_percent") or -999, reverse=True)

        return _json_response({
            "sectors": sectors,
            "leader": sectors[0]["sector"] if sectors else None,
            "laggard": sectors[-1]["sector"] if sectors else None,
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Yahoo Finance"
        })

    except Exception as e:
        return _error_response(e, "market_get_sector_performance")


# ── Tool 7: Portfolio Snapshot ───────────────────────────────────────────────

@app.route(route="tools/market_portfolio_snapshot", methods=["POST"])
async def market_portfolio_snapshot(req: func.HttpRequest) -> func.HttpResponse:
    """Compute live portfolio snapshot with weighted metrics."""
    try:
        body = req.get_json()
        holdings = body.get("holdings", {})
        if not holdings:
            return _json_response({"error": "holdings dict is required (ticker -> weight)"}, 400)

        holdings = {k.upper(): float(v) for k, v in holdings.items()}
        tickers = list(holdings.keys())
        weights = list(holdings.values())
        total_weight = sum(weights)

        quotes = await asyncio.to_thread(_yf_get_multiple_info, tickers)

        w_pe = w_fpe = w_beta = w_div = 0.0
        positions = []

        for ticker, weight, q in zip(tickers, weights, quotes):
            norm_w = weight / total_weight
            pe = q.get("trailingPE")
            fpe = q.get("forwardPE")
            beta = q.get("beta")
            div_y = q.get("dividendYield")

            if isinstance(pe, (int, float)):  w_pe += pe * norm_w
            if isinstance(fpe, (int, float)): w_fpe += fpe * norm_w
            if isinstance(beta, (int, float)): w_beta += beta * norm_w
            if isinstance(div_y, (int, float)): w_div += div_y * norm_w

            positions.append({
                "ticker": ticker,
                "name": q.get("shortName", ticker),
                "weight_percent": round(norm_w * 100, 1),
                "price": q.get("regularMarketPrice") or q.get("currentPrice"),
                "change_percent": round(q.get("regularMarketChangePercent", 0), 2) if isinstance(q.get("regularMarketChangePercent"), (int, float)) else None,
                "trailing_pe": round(pe, 1) if isinstance(pe, (int, float)) else None,
                "beta": round(beta, 2) if isinstance(beta, (int, float)) else None,
            })

        positions.sort(key=lambda x: -x["weight_percent"])

        return _json_response({
            "portfolio": {
                "holdings_count": len(tickers),
                "positions": positions,
                "weighted_metrics": {
                    "trailing_pe": round(w_pe, 1), "forward_pe": round(w_fpe, 1),
                    "beta": round(w_beta, 2), "dividend_yield_percent": round(w_div * 100, 2),
                },
            },
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Yahoo Finance"
        })

    except Exception as e:
        return _error_response(e, "market_portfolio_snapshot")


# ── Tool 8: Get News ─────────────────────────────────────────────────────────

@app.route(route="tools/market_get_news", methods=["POST"])
async def market_get_news(req: func.HttpRequest) -> func.HttpResponse:
    """Fetch latest financial news headlines for a ticker."""
    try:
        body = req.get_json()
        ticker = body.get("ticker", "").upper().strip()
        if not ticker:
            return _json_response({"error": "ticker is required"}, 400)

        news_items = await asyncio.to_thread(_yf_get_news, ticker)

        articles = []
        for article in news_items[:10]:
            # yfinance news format: dict with 'title', 'publisher', 'link', 'providerPublishTime' or 'publish_time'
            ts = article.get("providerPublishTime") or article.get("publish_time", 0)
            pub_time = None
            if ts:
                try:
                    if isinstance(ts, (int, float)):
                        pub_time = datetime.fromtimestamp(ts).isoformat() + "Z"
                    else:
                        pub_time = str(ts)
                except Exception:
                    pub_time = None

            # Handle nested content structure in newer yfinance versions
            content = article.get("content", article)
            title = content.get("title") or article.get("title", "No title")
            publisher = content.get("provider", {}).get("displayName") if isinstance(content.get("provider"), dict) else article.get("publisher", "Unknown")
            link = article.get("link") or article.get("url", "")
            if not link and isinstance(content.get("clickThroughUrl"), dict):
                link = content["clickThroughUrl"].get("url", "")

            articles.append({
                "title": title,
                "publisher": publisher or "Unknown",
                "published_at": pub_time,
                "url": link,
            })

        return _json_response({
            "ticker": ticker, "articles": articles,
            "count": len(articles),
            "timestamp": datetime.utcnow().isoformat() + "Z", "source": "Yahoo Finance"
        })

    except Exception as e:
        return _error_response(e, "market_get_news")


# ── Health Check ─────────────────────────────────────────────────────────────

@app.route(route="health", methods=["GET"])
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint for monitoring."""
    return _json_response({
        "status": "healthy",
        "service": "Capital Markets Tool Calling API",
        "version": "2.0.0",
        "engine": "yfinance",
        "tools": [
            "market_get_quote", "market_get_options_chain", "market_get_earnings",
            "market_get_macro", "market_compare_stocks", "market_get_sector_performance",
            "market_portfolio_snapshot", "market_get_news"
        ],
        "timestamp": datetime.utcnow().isoformat() + "Z"
    })
