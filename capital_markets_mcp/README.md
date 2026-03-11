# Capital Markets MCP Server

Live market data tools for the **ANF-OneLake-AIFoundry Capital Markets Agent**.

Connects to your `ANF-Multimodal-RAG-Agent` in Azure AI Foundry as an **Actions** source,
giving it real-time market intelligence on top of the static RAG knowledge base.

---

## Tools

| Tool | Description | Data Source |
|------|-------------|-------------|
| `market_get_quote` | Full real-time quote for any ticker | Yahoo Finance |
| `market_get_options_chain` | Live options chain with Greeks | Yahoo Finance |
| `market_get_earnings` | Earnings history, beat/miss streak, next date | Yahoo Finance |
| `market_get_macro` | Fed rate, CPI, GDP, unemployment, VIX, yields | FRED (Fed Reserve) |
| `market_compare_stocks` | Side-by-side comparison of 2-10 tickers | Yahoo Finance |
| `market_get_sector_performance` | All 11 GICS sectors ranked by performance | Yahoo Finance |
| `market_portfolio_snapshot` | Live portfolio analytics + weighted metrics | Yahoo Finance |
| `market_get_news` | Latest headlines for any ticker | Yahoo Finance |

---

## Quick Start

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. (Optional) Get free FRED API key for macro data
#    → https://fred.stlouisfed.org/docs/api/api_key.html
#    → Update FRED_API_KEY in server.py line ~34

# 3a. Run as stdio (for Claude Desktop / Cowork MCP)
python server.py

# 3b. Run as HTTP server (for Azure AI Foundry Agent Actions)
python server.py --http --port 8000
```

---

## Connect to Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "capital_markets": {
      "command": "python",
      "args": ["/path/to/capital_markets_mcp/server.py"]
    }
  }
}
```

---

## Connect to Azure AI Foundry Agent (Actions)

1. Run the server in HTTP mode: `python server.py --http --port 8000`
2. Expose via Azure App Service, Container App, or ngrok for public access
3. In AI Foundry → Your Agent → **Actions** → **+ Add** → **OpenAPI**
4. Point to `http://your-server:8000/openapi.json`
5. The agent will now call live market data tools alongside RAG retrieval

---

## Example Hybrid Queries

Once connected, your agent handles both RAG + live data in one response:

- *"Compare NVDA's current P/E to the tech sector average — is it overvalued vs the analyst reports in our knowledge base?"*
- *"What's the current yield curve shape and how does it compare to the macro trends in our macro_economic_indicators.csv?"*
- *"AAPL just reported earnings — how does this quarter compare to their historical beat rate?"*
- *"Show me the sector rotation today and overlay against our sector_rotation_analysis.xlsx recommendations"*

---

## Architecture

```
User Query
    ↓
Azure AI Foundry Agent (gpt-4.1)
    ↙                    ↘
RAG Knowledge          Live Data
(AI Search vector      (This MCP server)
 index — static docs)   ↓
    ↓                  yfinance + FRED API
    ↘                 ↙
     Synthesized Answer
     with citations from both
```

---

## Static Test Data (in test_data/capital_markets/)

These files are indexed in the RAG pipeline for historical context:

| File | Contents |
|------|----------|
| `equities_watchlist.csv` | 25 stocks with full fundamentals |
| `bond_portfolio.csv` | 15 bonds: ratings, duration, YTM |
| `options_chain_SPY.csv` | SPY options across 5 expiries |
| `macro_economic_indicators.csv` | 5Y macro history (Fed, CPI, GDP, VIX) |
| `earnings_calendar_q1_2025.csv` | Q1 2025 earnings beats/misses |
| `trade_blotter_2024.csv` | 120 trade records with PnL |
| `ipo_pipeline_2025.csv` | 2025 IPO pipeline with valuations |
| `credit_risk_dashboard.csv` | CDS spreads, ratings, Altman Z-scores |
| `sector_rotation_analysis.xlsx` | Sector ratings + factor analysis |
| `analyst_recommendations.csv` | Buy/Hold/Sell ratings with price targets |
