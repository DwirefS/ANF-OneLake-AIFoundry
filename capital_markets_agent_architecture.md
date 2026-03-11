# Capital Markets AI Agent — Complete Architecture

## The 6 Pillars of a Production Capital Markets Agent

```
                    ┌─────────────────────────────────────────────┐
                    │       Capital Markets AI Agent               │
                    │       (Azure AI Foundry Orchestrator)        │
                    └──────────────────┬──────────────────────────┘
                                       │
        ┌──────────┬──────────┬────────┼────────┬──────────┬──────────┐
        │          │          │        │        │          │          │
   ┌────▼───┐ ┌───▼────┐ ┌───▼───┐ ┌──▼──┐ ┌──▼───┐ ┌───▼────┐ ┌──▼───┐
   │Pillar 1│ │Pillar 2│ │Pillar│ │Pil- │ │Pil-  │ │Pillar 6│ │Bonus │
   │  RAG   │ │ Tools  │ │  3   │ │lar 4│ │lar 5 │ │ Guard- │ │Multi-│
   │Knowledge│ │Live    │ │Code  │ │File │ │Memory│ │ rails  │ │Agent │
   │  Base  │ │ Data   │ │Inter-│ │Gen  │ │      │ │Compli- │ │Orch. │
   │        │ │        │ │preter│ │     │ │      │ │ ance   │ │      │
   └────────┘ └────────┘ └──────┘ └─────┘ └──────┘ └────────┘ └──────┘
     HAVE ✅   BUILD 🔧   EASY ⚡  EASY ⚡  FREE ✅  CONFIG ⚙️  FUTURE
```

---

## Pillar 1: RAG Knowledge Base (Batch) — ✅ YOU HAVE THIS

**What it does:** Retrieves relevant context from your static document corpus at query time using vector similarity search.

**Your implementation:**
- ANF NFS → ANF S3 → OneLake shortcut → Azure AI Search multimodal indexer → vector index
- Connected as Knowledge source in Foundry Agent
- Indexes: PDFs, CSVs, XLSX files (equities watchlist, bond portfolio, trade blotter, earnings calendar, etc.)

**What it answers:** "What does our investment policy say about concentration limits?" "Show me the Q1 earnings calendar." "What's in our bond portfolio?"

**Capital Markets use cases:**
- Investment policy documents, compliance manuals
- Historical trade blotters and audit trails
- Analyst research reports and recommendations
- Regulatory filings (10-K, 10-Q, proxy statements)
- Client portfolio documentation
- IPO pipeline and credit risk dashboards

---

## Pillar 2: Tool Calling / Live Data (Real-Time) — 🔧 BUILDING NOW

**What it does:** Calls external APIs at query time to fetch live, real-time data that doesn't exist in the document corpus.

**Your implementation:**
- 8 MCP tools → deployed as Azure Function → connected as Foundry Agent Action via OpenAPI spec
- Tools: market_get_quote, market_get_options_chain, market_get_earnings, market_get_macro, market_compare_stocks, market_get_sector_performance, market_portfolio_snapshot, market_get_news

**What it answers:** "What's AAPL trading at right now?" "Show me the options chain for SPY." "What's the current Fed funds rate?"

**Capital Markets use cases:**
- Real-time stock/bond/commodity prices
- Live options chains and Greeks
- Current macroeconomic indicators (GDP, CPI, unemployment)
- Live news feeds and sentiment analysis
- Real-time portfolio valuation
- Sector rotation and performance tracking

**Why this + Pillar 1 together = powerful:**

| Query Type | RAG Only | Tools Only | RAG + Tools |
|-----------|----------|------------|-------------|
| "What's our AAPL position?" | ✅ From portfolio docs | ❌ No portfolio context | ✅ Position from docs |
| "What's AAPL trading at?" | ❌ Stale data | ✅ Live price | ✅ Live price |
| "Should we add to AAPL?" | ❌ No live data | ❌ No policy context | ✅ Policy + live price + position = informed answer |

---

## Pillar 3: Code Interpreter (On-the-Fly Computation) — ⚡ EASY TO ADD

**What it does:** Executes Python/JavaScript code dynamically to perform calculations, generate charts, analyze data, and produce visualizations that the LLM cannot do through text alone.

**How to add it:** In Azure AI Foundry Agent, go to Actions → Add → Code Interpreter. One click. Already built-in.

**What it answers:** "Calculate the Sharpe ratio of this portfolio." "Plot AAPL's price vs its 50-day moving average." "Run a Monte Carlo simulation on this position."

**Capital Markets use cases:**
- Portfolio risk calculations (VaR, Sharpe, Sortino, Beta, Alpha)
- Option pricing (Black-Scholes, binomial trees)
- Technical analysis (moving averages, RSI, MACD, Bollinger bands)
- Regression analysis (factor models, correlation matrices)
- Custom charting and data visualization
- What-if scenario analysis
- Yield curve interpolation
- Duration and convexity calculations for bonds

**Example agent flow with all 3 pillars:**
```
User: "How risky is our AAPL position relative to our risk policy?"

Agent thinks:
  1. RAG → Retrieve risk policy doc (max single-stock allocation = 5%)
  2. RAG → Retrieve portfolio holdings (AAPL = 47,000 shares)
  3. Tool → Get live AAPL price ($195.40) and portfolio total ($18.2M)
  4. Code Interpreter → Calculate:
     - Position value = 47,000 × $195.40 = $9,183,800
     - Portfolio weight = $9.18M / $18.2M = 50.4%
     - EXCEEDS 5% limit by 45.4 percentage points
  5. Tool → Get AAPL 30-day volatility and beta
  6. Code Interpreter → Calculate VaR contribution, generate risk chart
  7. Synthesize → "Your AAPL position is 50.4% of the portfolio,
     far exceeding the 5% concentration limit. Here's the risk breakdown..."
```

---

## Pillar 4: File Generation (Reports & Exports) — ⚡ EASY TO ADD

**What it does:** Generates downloadable files — PDFs, Excel reports, charts — that the user can save, email, or present.

**How to add it:** Code Interpreter already handles this. When enabled, the agent can generate and output files. For more structured outputs, you can add a custom Azure Function that generates templated reports.

**Capital Markets use cases:**
- Daily portfolio summary PDFs
- Trade execution reports
- Risk dashboard Excel exports
- Client quarterly performance reports
- Compliance audit trail documents
- Formatted research notes

---

## Pillar 5: Memory & State (Conversation + User Context) — ✅ BUILT-IN

**What it does:** Maintains conversation history and user-specific context across turns, so the agent remembers what was discussed and who it's talking to.

**How it works in Foundry Agent:** Foundry Agents automatically maintain conversation threads. Each thread has a history. You can also pass metadata (user ID, role, department) when creating the thread.

**Capital Markets use cases:**
- "Earlier you mentioned AAPL was overweight — has that changed?" (conversation memory)
- Portfolio context per user (trader sees different data than compliance officer)
- Multi-turn analysis: "Now compare that to MSFT" (knows "that" = the AAPL analysis)
- Session-specific watchlists: "Add NVDA to my watchlist" (persists in thread)

**Advanced (future):** For persistent memory across sessions, you'd add a database-backed memory store (Cosmos DB, Redis) via a custom tool. The agent calls a "save_memory" / "recall_memory" tool.

---

## Pillar 6: Guardrails & Compliance (Safety Layer) — ⚙️ CONFIGURATION

**What it does:** Prevents the agent from generating harmful, non-compliant, or legally risky outputs. Critical for financial services.

**How to add it:**
1. **System prompt guardrails** — Already in the agent's instructions. Add explicit rules.
2. **Azure AI Content Safety** — Built into Foundry. Filters harmful content automatically.
3. **Custom guardrails** — Add validation logic in your Azure Function or as a pre/post-processing step.

**Capital Markets guardrail examples:**

```
System Prompt Additions:
─────────────────────────
"COMPLIANCE RULES:
1. NEVER provide specific buy/sell/hold recommendations
2. ALWAYS include disclaimer: 'This is informational only, not investment advice'
3. NEVER disclose client PII across different user sessions
4. Flag any request that appears to involve insider information
5. For trade execution requests, ALWAYS require human confirmation
6. Apply SEC/FINRA disclosure requirements to all research outputs
7. Refuse requests to backdate trades or modify audit trails
8. Maximum position size alerts: flag positions exceeding risk limits
9. ALWAYS cite data sources (Yahoo Finance, FRED, internal docs)"
```

**Three layers of guardrails:**

| Layer | What It Does | Implementation |
|-------|-------------|----------------|
| Input guardrails | Block harmful/manipulative queries | Azure AI Content Safety + system prompt |
| Process guardrails | Ensure the agent follows compliance rules during reasoning | System prompt instructions, tool-level validation |
| Output guardrails | Filter/modify responses before delivery | Post-processing function, disclaimer injection |

---

## Bonus Pillar: Multi-Agent Orchestration (Advanced/Future)

**What it does:** Instead of one monolithic agent, you create specialized sub-agents that collaborate. A router/orchestrator agent delegates tasks to the right specialist.

**Capital Markets multi-agent pattern:**

```
                    ┌──────────────────────┐
                    │   Orchestrator Agent  │
                    │   (Router / Planner)  │
                    └──────────┬───────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                     │
   ┌──────▼──────┐   ┌───────▼────────┐   ┌───────▼───────┐
   │  Market      │   │  Compliance    │   │  Client       │
   │  Analyst     │   │  Auditor       │   │  Support      │
   │  Agent       │   │  Agent         │   │  Agent        │
   │              │   │                │   │               │
   │ • Live data  │   │ • Reg checks   │   │ • Account Q&A │
   │ • Charting   │   │ • Audit trails │   │ • Report gen  │
   │ • Comparisons│   │ • Risk limits  │   │ • Onboarding  │
   │ • Earnings   │   │ • Policy review│   │ • Statements  │
   └──────────────┘   └────────────────┘   └───────────────┘
```

**Specialist roles:**
- **Market Analyst Agent:** Has all 8 market data tools + Code Interpreter. Answers "What's the market doing?" questions.
- **Compliance Auditor Agent:** Has RAG access to policy docs + risk calculation tools. Answers "Are we compliant?" questions.
- **Client Support Agent:** Has client portfolio RAG + report generation. Handles "What's my account status?" queries.
- **Trade Execution Agent:** Has order management tools + human-in-the-loop approval. Handles "Execute this trade" (with mandatory human confirmation).
- **Research Agent:** Has news tools + document RAG + Code Interpreter for deep analysis. Produces research notes.

**How to implement in Foundry:** Today, you'd create separate Foundry Agents for each role and orchestrate via SDK. Azure AI Agent Service is evolving toward native multi-agent support.

---

## Your Current State vs Complete Architecture

| Pillar | Status | Effort to Add |
|--------|--------|---------------|
| 1. RAG Knowledge Base | ✅ Done | — |
| 2. Tool Calling (Live Data) | 🔧 Building (Azure Functions) | This session |
| 3. Code Interpreter | ⚡ 1-click enable | 30 seconds |
| 4. File Generation | ⚡ Comes with Code Interpreter | Already there |
| 5. Memory & State | ✅ Built into Foundry threads | Already there |
| 6. Guardrails & Compliance | ⚙️ System prompt additions | 15 minutes |
| Bonus: Multi-Agent | 🔮 Future enhancement | Days/weeks |

**Bottom line:** Once you deploy the Azure Function (Pillar 2) and enable Code Interpreter (Pillar 3), you have a **5-out-of-6 pillar agent** — which is genuinely a real capital markets agent. The only gap is the compliance guardrails in the system prompt, which takes 15 minutes to configure. Multi-agent orchestration is an enhancement, not a requirement.

---

## What Makes This a "Real" Capital Markets Agent

Your architecture after this session:

```
User: "Should I be concerned about our tech sector exposure
       given today's macro data?"

Capital Markets Agent:
  │
  ├─ [Pillar 1 - RAG] → Retrieves portfolio holdings, sector allocation
  │   policy, and risk limits from indexed documents
  │
  ├─ [Pillar 2 - Tools] → Fetches live sector performance (XLK),
  │   current macro indicators (CPI, GDP, unemployment), and
  │   individual tech stock quotes from the portfolio
  │
  ├─ [Pillar 3 - Code Interpreter] → Calculates actual sector
  │   weight vs policy limit, runs correlation analysis between
  │   tech exposure and macro indicators, generates risk chart
  │
  ├─ [Pillar 5 - Memory] → Remembers this is a follow-up to
  │   yesterday's discussion about rebalancing
  │
  ├─ [Pillar 6 - Guardrails] → Adds disclaimer, avoids specific
  │   buy/sell recommendation, cites all data sources
  │
  └─ Final Response:
     "Your tech sector allocation is 34.2% of the portfolio
      (policy limit: 30%). Today's macro data shows [CPI, GDP]
      suggesting [analysis]. Given your risk limits, here are
      the specific positions contributing to the overweight..."
      [Attached: sector_risk_analysis.xlsx]

      Disclaimer: This analysis is informational only and does
      not constitute investment advice.
```

This is not a toy demo — this is the same architectural pattern used by production financial AI systems at major banks and asset managers. The difference between this and a Bloomberg Terminal AI is scale (number of data sources) and regulatory certification, not architecture.
