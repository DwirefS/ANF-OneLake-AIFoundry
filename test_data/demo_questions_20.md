# Capital Markets Financial Agent: 20 High-Impact Demo Questions
**Azure AI Foundry | RAG + Live Market Data | March 2026**

---

## Category 1: Pure RAG (Questions 1-5)
*Questions that ONLY use the indexed documents (Financial Sample, NASDAQ data, invoices, portfolios, etc.)*

### Question 1
**Text:** "Which products generated the most revenue in the Midmarket segment, and what was the geographic breakdown of sales by country?"

**Data Sources:** RAG — Financial Sample.xlsx (Midmarket segment, product sales breakdown, country analysis)

**Why It's a Good Demo:** Demonstrates complex multi-dimensional filtering and aggregation across a large Excel dataset with multiple pivot dimensions (segment, product, geography).

---

### Question 2
**Text:** "Analyze our Q1 vs Q2 2025 expense trends. Which expense categories saw the biggest percentage increase, and which invoices (INV-001 through INV-010) contributed most to Q2 spending?"

**Data Sources:** RAG — Q1_2025_Expenses.csv, Q2_2025_Expenses.csv, 10 invoices (Invoice_INV-001 through INV-010)

**Why It's a Good Demo:** Showcases time-series comparative analysis with drill-down capability from aggregate expense categories to individual invoice line items.

---

### Question 3
**Text:** "From the equities watchlist, identify which 5 stocks have the highest forward P/E ratios and are closest to their analyst price targets. What is the implied upside/downside for each?"

**Data Sources:** RAG — equities_watchlist.csv (P/E, analyst targets, market cap, EPS)

**Why It's a Good Demo:** Tests ranking, filtering, and calculation logic (upside/downside math) within a structured financial dataset.

---

### Question 4
**Text:** "In our bond portfolio, which bonds are trading below par value and have a YTM of 4% or higher? Calculate the duration-weighted risk for each credit rating tier (UST, IG, HY, Munis)."

**Data Sources:** RAG — bond_portfolio.csv (duration, YTM, rating, par value)

**Why It's a Good Demo:** Exercises numerical filtering, risk aggregation, and financial metric calculations (duration weighting) on fixed-income data.

---

### Question 5
**Text:** "Based on Q1 2025 earnings data, which 5 companies beat estimates by the largest percentage, and what was their average EPS surprise?"

**Data Sources:** RAG — earnings_calendar_q1_2025.csv (EPS estimates vs actuals, beat/miss)

**Why It's a Good Demo:** Demonstrates sorting, filtering, and calculation of financial surprises (beat/miss percentages and averages) from a time-specific earnings dataset.

---

## Category 2: Pure Live Data (Questions 6-10)
*Questions that ONLY use the live market data tools (no RAG)*

### Question 6
**Text:** "What is the current price, 52-week range, and P/E ratio for Apple (AAPL), Microsoft (MSFT), and Nvidia (NVDA)? Which has the lowest forward P/E?"

**Data Sources:** Live Tools — market_get_quote (3 calls for AAPL, MSFT, NVDA)

**Why It's a Good Demo:** Shows the agent's ability to call live data tools in parallel, compare results, and identify the minimum value across a set.

---

### Question 7
**Text:** "Show me the current implied volatility skew for SPY options at the nearest monthly expiration. Which strike prices have IV crush, and which have elevated IV?"

**Data Sources:** Live Tools — market_get_options_chain (SPY at nearest expiry, IV analysis)

**Why It's a Good Demo:** Requires understanding of derivatives (IV, skew, IV crush terminology) and ability to interpret and rank options data by a derived metric.

---

### Question 8
**Text:** "What are the current Fed Funds rate, CPI (YoY), unemployment rate, and VIX level? How do these compare to values from 12 months ago?"

**Data Sources:** Live Tools — market_get_macro (Fed Funds, CPI, unemployment, VIX; historical comparison)

**Why It's a Good Demo:** Exercises the macro data tool with temporal comparison logic and demonstrates understanding of key economic indicators.

---

### Question 9
**Text:** "Compare Tesla (TSLA) and Rivian (RIVN) side-by-side: price, market cap, P/E, 52-week performance, and analyst sentiment. Which is more expensive on a valuation basis?"

**Data Sources:** Live Tools — market_compare_stocks (TSLA vs RIVN), market_get_quote, analyst sentiment (if available in compare tool)

**Why It's a Good Demo:** Tests multi-metric comparison and the agent's ability to synthesize live data into a comparative analysis that answers a specific valuation question.

---

### Question 10
**Text:** "Which GICS sector is currently outperforming, and what are the top 3 stocks in that sector? What is the sector's YTD return?"

**Data Sources:** Live Tools — market_get_sector_performance (all 11 GICS sectors, YTD returns)

**Why It's a Good Demo:** Requires identifying the maximum-performing sector from 11 options and synthesizing sector-level performance data into an actionable market insight.

---

## Category 3: Hybrid RAG + Live Data (Questions 11-16)
*Questions that require BOTH the knowledge base AND live market data tools*

### Question 11
**Text:** "Compare the yield and duration of our bond portfolio (from the RAG data) against the current 10-year Treasury yield and 30-year Treasury yield from live market data. Are we getting adequate compensation for the extra duration and credit risk?"

**Data Sources:**
- RAG — bond_portfolio.csv (duration, YTM, ratings, bond details)
- Live Tools — market_get_macro (Treasury yields via FRED data)

**Why It's a Good Demo:** Combines internal portfolio data with live market benchmarks to assess relative value and risk compensation—a classic portfolio management question.

---

### Question 12
**Text:** "From our equities watchlist, identify which stocks are trading at a discount to their analyst price targets AND have a P/E below their sector average. Use live data to get current sector P/E ratios."

**Data Sources:**
- RAG — equities_watchlist.csv (watchlist symbols, analyst targets, P/E)
- Live Tools — market_get_sector_performance (sector P/E averages), market_get_quote (current prices)

**Why It's a Good Demo:** Exercises filtering and ranking logic that requires merging RAG portfolio data with live sector benchmark data.

---

### Question 13
**Text:** "Cross-reference our Q1 2025 earnings calendar with the latest earnings news. For companies that beat expectations in Q1, what is their current stock price versus their post-earnings price target from analysts?"

**Data Sources:**
- RAG — earnings_calendar_q1_2025.csv (Q1 earnings beat/miss data)
- Live Tools — market_get_news (latest earnings-related headlines), market_get_quote (current prices), analyst recommendations

**Why It's a Good Demo:** Requires matching historical RAG earnings data with live news and current pricing, showing real-time impact of earnings surprises on valuations.

---

### Question 14
**Text:** "Which companies from our NASDAQ dataset have options trading in our SPY options chain? For those that are in both, compare their implied volatility from the RAG options data to live options IV levels."

**Data Sources:**
- RAG — NASDAQ.csv, options_chain_SPY.csv
- Live Tools — market_get_options_chain (live SPY options, IV levels)

**Why It's a Good Demo:** Demonstrates the ability to join datasets across RAG and live data, and to track changes in a derived metric (IV) over time.

---

### Question 15
**Text:** "From our macro economic indicators RAG data (5 years of history), identify the period where Fed Funds were highest and VIX was lowest (risk-on environment). What were the best-performing sectors during that period from our sector rotation analysis?"

**Data Sources:**
- RAG — macro_economic_indicators.csv (5 years: Fed Funds, VIX, GDP, CPI, unemployment), sector_rotation_analysis.xlsx (sector performance data)
- Live Tools — market_get_sector_performance (for current context and comparison)

**Why It's a Good Demo:** Combines historical macro regime analysis with sector rotation patterns, requiring multi-dimensional filtering and comparative analysis.

---

### Question 16
**Text:** "Use our credit risk dashboard to identify which companies have CDS spreads indicating rising default risk (wide spreads, low Altman Z). Cross-check with live news to see if there are recent negative headlines about these firms."

**Data Sources:**
- RAG — credit_risk_dashboard.csv (CDS spreads, ratings, default probabilities, Altman Z)
- Live Tools — market_get_news (search for company-specific negative news)

**Why It's a Good Demo:** Bridges quantitative risk metrics from RAG with real-time sentiment/news, showing how to validate risk models against current information flow.

---

## Category 4: Complex Multi-Hop (Questions 17-20)
*Advanced questions requiring reasoning across multiple documents AND multiple tool calls*

### Question 17
**Text:** "Analyze our 2024 trade blotter performance by desk (Equities, FI, Derivatives). For the best-performing desk, identify which product categories they traded (using Financial Sample.xlsx) and assess whether those products are currently in favor by checking live sector performance and analyst sentiment."

**Data Sources:**
- RAG — trade_blotter_2024.csv (120 trades, desk breakdown, PnL), Financial Sample.xlsx (products: Paseo, VTT, Montana, Amarilla, Velo, Carretera)
- Live Tools — market_get_sector_performance (sector momentum), market_get_news (sentiment analysis), analyst_recommendations.csv (analyst views)

**Why It's a Good Demo:** Requires five logical steps: (1) parse and aggregate blotter by desk, (2) identify best performer, (3) cross-reference to product categories, (4) validate with live sector data, (5) assess forward outlook with sentiment.

---

### Question 18
**Text:** "From the IPO pipeline, select the 3 IPOs with the highest expected valuations (Databricks, Klarna, Stripe, Waymo, SpaceX Starlink, etc.). For each, identify peer comparables from our equities watchlist and NASDAQ data, then get live P/E and market cap data to assess relative valuation and IPO pricing fairness."

**Data Sources:**
- RAG — ipo_pipeline_2025.csv (10 IPOs with expected valuation ranges), equities_watchlist.csv, NASDAQ.csv
- Live Tools — market_get_quote (live quotes for peer comparables), market_compare_stocks (peer analysis)

**Why It's a Good Demo:** Involves multi-step reasoning: identify IPOs, find comps, fetch live data, and synthesize a valuation fairness opinion—a core M&A/capital markets exercise.

---

### Question 19
**Text:** "Build a risk-adjusted portfolio recommendation combining our bond portfolio and equities watchlist with current market conditions. Factor in live Treasury yields, sector performance, VIX, and our internal credit risk dashboard. Which asset class allocation is optimal given current macro conditions and relative valuation?"

**Data Sources:**
- RAG — bond_portfolio.csv (current holdings, duration, YTM), equities_watchlist.csv (stock holdings, P/E, analyst targets), macro_economic_indicators.csv (historical context), credit_risk_dashboard.csv (credit metrics), sector_rotation_analysis.xlsx (historical factor performance)
- Live Tools — market_get_macro (Fed Funds, CPI, VIX, GDP), market_get_sector_performance (sector momentum), market_get_quote (equity valuations)

**Why It's a Good Demo:** Synthesizes portfolio theory with live market data to produce a forward-looking allocation recommendation—demonstrates the agent's ability to integrate 10+ data sources into a single coherent investment decision.

---

### Question 20
**Text:** "Create a trade idea: identify a sector that is outperforming on a 6-month basis (using sector rotation analysis and live sector performance) and a company within that sector from our NASDAQ data that has beaten earnings (from Q1 earnings calendar), is trading below analyst targets (from equities watchlist), and has positive analyst sentiment. Size the position using portfolio risk metrics and current VIX. Validate the trade thesis with latest news."

**Data Sources:**
- RAG — sector_rotation_analysis.xlsx (6-month sector performance), NASDAQ.csv, earnings_calendar_q1_2025.csv (beat/miss), equities_watchlist.csv (analyst targets, sentiment), macro_economic_indicators.csv (VIX levels), trade_blotter_2024.csv (position sizing patterns), analyst_recommendations.csv
- Live Tools — market_get_sector_performance (current momentum), market_get_quote (current price vs target), market_get_news (validation headlines), market_get_macro (VIX for position sizing)

**Why It's a Good Demo:** The most comprehensive question—requires filtering across 8+ RAG sources, 4 live tools, multi-criteria ranking, position sizing logic, and thesis validation; demonstrates the agent as a true investment decision-support system.

---

## Summary

| Category | Questions | Complexity | RAG Focus | Live Tools Focus | Best For Demonstrating |
|----------|-----------|-----------|-----------|------------------|----------------------|
| Pure RAG | 1-5 | Medium | 100% | 0% | Document parsing, multi-dimensional analysis, financial calculations |
| Pure Live | 6-10 | Medium | 0% | 100% | API integration, real-time data fetching, market awareness |
| Hybrid | 11-16 | High | 50% | 50% | Portfolio analytics, benchmarking, value assessment |
| Multi-Hop | 17-20 | Very High | 70% | 30% | End-to-end workflows, investment decision support, complex reasoning |

**Total Questions: 20** | **Estimated Demo Time: 45-60 minutes** | **Target Audience: Capital Markets Professionals, Trading Teams, Risk Management, Wealth Management**
