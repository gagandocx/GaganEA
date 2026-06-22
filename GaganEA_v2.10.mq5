//+------------------------------------------------------------------+
//|                                        GaganEA v2.10 |
//|                           Reconstructed from UI + Backtest Data  |
//|                                                                  |
//| KEY FINDINGS FROM BACKTEST ANALYSIS:                             |
//|  - $1000 -> $8970 in 28 days (797% growth)                      |
//|  - 1246 trade events, consistent ~8.5% deposit load per trade    |
//|  - Each trade cycle: open -> T1 partial -> T2 partial -> T3/SL   |
//|  - 872 "FLAT" periods (no positions) = EA waits for clean signal |
//|  - 12 big SL hits (~$100-750 range) = basket SL events           |
//|  - 276 multi-close events = basket/partial close sequences       |
//|  - Deposit load always ~8.7% = risk-based lot sizing working     |
//|  - Tiny -$0.11 recurring losses = swap/commission on partials    |
//+------------------------------------------------------------------+
#property copyright "GaganEA v2.10"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_MASTER_MODE
{
   MODE_LAST_2           = 1,  // 1: Last 2 Trades
   MODE_LAST_3           = 2,  // 2: Last 3 Trades
   MODE_FIRST_2_LAST_1   = 3,  // 3: First 2 + Last 1
   MODE_FIRST_MID_LAST   = 4,  // 4: First 1 + Middle 1 + Last 1
   MODE_SEC_MID_LAST     = 5,  // 5: Second 1 + Middle 1 + Last 1
   MODE_ALL_SIMULTANEOUS = 6   // 6: All 5 Conditions Simultaneously
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== TRADE EXECUTION (M1) ==="
input ENUM_TIMEFRAMES Trade_Timeframe     = PERIOD_M1;    // Trading Timeframe (M1 recommended)


input group "=== LOT SIZE ==="
input double          Manual_LotSize      = 0.0;           // Manual Lot Size (0 = Auto)
input double          Risk_Percent        = 6.0;           // Auto Risk % per Trade
input double          Max_LotSize         = 10.0;          // Maximum Lot Size

input group "=== STOP LOSS & TARGETS ==="
input bool            Use_StopLoss        = true;          // Use Stop Loss? (ON/OFF)
input int             StopLoss_Pips       = 2500;          // Stop Loss (Pips)
input int             T1_Pips             = 800;           // Target 1 (Pips)
input int             T2_Pips             = 1200;          // Target 2 (Pips)
input int             T3_Pips             = 2000;          // Target 3 (Pips)
input double          T1_ClosePercent     = 65.0;          // T1 Close % of Position
input double          T2_ClosePercent     = 80.0;          // T2 Close % of Position
input double          T3_ClosePercent     = 100.0;         // T3 Close % (Full Close)

input group "=== TRAILING STOP (Individual) ==="
input int             Trail_Step_Pips     = 30;            // Trail Step After T2 (Pips)

input group "=== AMA TREND-FLIP EXIT & DIRECTION (M1) ==="
input bool             Use_AMA_Exit        = true;          // Use AMA 3-Candle Exit (ON/OFF)
input int              AMA_Period          = 21;             // AMA Period
input int              AMA_Fast_EMA        = 2;              // AMA Fast EMA Constant
input int              AMA_Slow_EMA        = 30;             // AMA Slow EMA Constant
input int              AMA_Shift           = 0;              // AMA Shift
input int              AMA_Confirm_Candles = 3;              // Consecutive M1 Closes to Confirm Flip

input group "=== AMA PULLBACK ENTRY FILTER (ADAPTIVE) ==="
input bool             Use_AMA_Pullback    = true;           // Only enter when price near AMA (ON/OFF)
input int              AMA_Pullback_Bars   = 50;             // Lookback bars to compute mean + std dev of AMA distance
input double           AMA_Pullback_Sigma  = 0.5;            // Zone width in std deviations above mean
// Threshold = Mean(dist) + Sigma × StdDev(dist)
// Sigma= 0.0 → enter only when dist ≤ mean  (average pullback)
// Sigma= 0.5 → enter when dist ≤ mean+½σ   (default, balanced)
// Sigma= 1.0 → enter when dist ≤ mean+1σ   (wide zone, more trades)
// Sigma=-0.5 → tighter than mean            (only very close pullbacks)
// Threshold auto-widens in volatile markets and tightens in calm markets

input group "=== AVERAGING BASKET TRAILING (Same-Side) ==="
input bool            Use_Basket_Trailing = true;          // Use Basket Trailing (ON/OFF)
input double          Basket_Lock_Pips    = 30.0;          // Profit Lock to Start Trailing (Combined Pips)
input double          Basket_Trail_Step   = 15.0;          // Basket Trail Step (Combined Pips)

input group "=== MULTI-TRADE SETTINGS ==="
input int             Min_Trade_Distance  = 20;            // Min Distance Between Trades (Pips)
input int             Max_Trade_Distance  = 40;            // Max Distance Between Trades (Pips)

input group "=== EQUITY PROTECTION (Global Close) ==="
input bool            Use_EP_Percent      = true;          // Equity Protection % (ON/OFF)
input double          EP_Max_DD_Percent   = 5.5;           // Max Drawdown % (Close All)
input bool            Use_EP_Money        = false;         // Equity Protection $ (ON/OFF)
input double          EP_Max_DD_Money     = 200.0;         // Max Drawdown $ (Close All)


input group "=== MASTER EQUITY PROTECTION ==="
input bool            Use_Master_EP                = true;                   // Master Safety Equity (ON/OFF)
input double          Master_Trigger_DD_Percent    = 1.5;                    // Trigger Drawdown %
input int             Master_Trigger_Min_Trades    = 3;                      // OR Trigger Min Trades Open
input ENUM_MASTER_MODE Master_Logic_Mode           = MODE_ALL_SIMULTANEOUS;  // Sub-trade Logic Mode
input double          Master_Lock_Pips             = 30.0;                   // Fast Profit Lock (Combined Pips)
input double          Master_Trail_Step            = 15.0;                   // Trail Step (Combined Pips)

input group "=== HIGH IMPACT NEWS FILTER ==="
input bool            News_Filter_Enable  = false;         // Enable High Impact News Filter
input int             News_Pause_Before   = 30;            // Pause before news (Mins)
input int             News_Pause_After    = 30;            // Pause after news (Mins)

input group "=== CANDLESTICK PATTERNS ==="
input bool            Use_Hammer         = true;           // Bullish: Hammer
input bool            Use_InvHammer      = true;           // Bullish: Inverted Hammer
input bool            Use_BullEngulf     = true;           // Bullish: Engulfing
input bool            Use_PiercingLine   = true;           // Bullish: Piercing Line
input bool            Use_MorningStar    = true;           // Bullish: Morning Star
input bool            Use_ThreeWhite     = true;           // Bullish: Three White Soldiers
input bool            Use_BullHarami     = true;           // Bullish: Harami
input bool            Use_Doji           = true;           // Bullish/Bearish: Doji
input bool            Use_ShootingStar   = true;           // Bearish: Shooting Star
input bool            Use_BearEngulf     = true;           // Bearish: Engulfing
input bool            Use_EveningStar    = true;           // Bearish: Evening Star
input bool            Use_ThreeBlack     = true;           // Bearish: Three Black Crows
input bool            Use_DarkCloud      = true;           // Bearish: Dark Cloud Cover
input bool            Use_BearHarami     = true;           // Bearish: Harami
input bool            Use_HangingMan     = true;           // Bearish: Hanging Man

input group "=== CHART PATTERNS ==="
input bool            Use_DoubleTop      = true;           // Chart: Double Top (Bearish)
input bool            Use_DoubleBottom   = true;           // Chart: Double Bottom (Bullish)
input bool            Use_HeadShoulders  = true;           // Chart: Head & Shoulders (Bearish)
input bool            Use_InvHeadShould  = true;           // Chart: Inv Head & Shoulders (Bullish)
input bool            Use_BearFlag       = true;           // Chart: Bear Flag
input bool            Use_BullFlag       = true;           // Chart: Bull Flag
input bool            Use_RisingWedge    = true;           // Chart: Rising Wedge (Bearish)
input bool            Use_FallingWedge   = true;           // Chart: Falling Wedge (Bullish)
input bool            Use_BearTriangle   = true;           // Chart: Descending Triangle (Bearish)
input bool            Use_BullTriangle   = true;           // Chart: Ascending Triangle (Bullish)

input group "=== NEWS FILTER ==="
input bool            News_FilterEnable  = false;          // Enable News Filter (No Trading)

input group "=== DASHBOARD & MAGIC ==="
input bool            Show_Dashboard     = true;           // Show Information Dashboard
input int             Dashboard_X        = 15;             // Dashboard X Position
input int             Dashboard_Y        = 30;             // Dashboard Y Position
input int             Magic_Number       = 202400;         // EA Magic Number
input int             Max_Slippage       = 10;             // Max Slippage (Points)
input int             Max_Spread_Pips    = 50;             // Max Spread to Allow Entry (Pips, 0=off)
input string          EA_Comment         = "GaganEA";      // Trade Comment


//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
double   pip;
double   point_size;

// AMA (Adaptive Moving Average) - M1: used for BOTH direction AND trend-flip exit
int      ama_handle;
double   ama_buf[];

// AMA-based trade direction (replaces HTF/CTF EMA trend logic)
bool     ama_bullish;   // last closed M1 bar closed ABOVE AMA  → only BUYs allowed
bool     ama_bearish;   // last closed M1 bar closed BELOW AMA  → only SELLs allowed

// AMA Pullback filter — updated every new bar
double   avg_ama_dist_pips = 0.0;  // mean AMA distance (pips) over lookback
double   cur_ama_dist_pips = 0.0;  // current bar's distance from AMA (pips)
double   ama_dist_stddev   = 0.0;  // std deviation of AMA distances — measures market volatility
double   ama_dist_thresh   = 0.0;  // adaptive threshold = mean + Sigma × stddev (auto-updates each bar)
bool     pullback_ok       = true; // true = price is near AMA → entry allowed

// State tracking per position ticket for T1/T2 hit flags
ulong    t1_hit_tickets[];
ulong    t2_hit_tickets[];

int      open_buy_count;
int      open_sell_count;
double   floating_pnl;
double   basket_buy_combined;
double   basket_sell_combined;

datetime last_bar_time;
bool     news_active = false;

// M1 bar tracking for AMA trend-flip exit
datetime last_m1_bar_time;

// Per-period P&L cache
double   pnl_today;
double   pnl_yesterday;
double   pnl_week;
double   pnl_month;
double   pnl_last_month;
datetime pnl_cache_time;

// Signal state
string   current_signal;
color    signal_color;

// Dashboard label prefix
string   lbl = "GEA_";


//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Determine pip size based on broker digits
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   pip = (digits == 3 || digits == 5) ? point_size * 10 : point_size;

   // Create AMA indicator handle (M1) — used for BOTH direction AND trend-flip exit
   ama_handle = iAMA(_Symbol, PERIOD_M1, AMA_Period, AMA_Fast_EMA, AMA_Slow_EMA, AMA_Shift, PRICE_CLOSE);
   if(ama_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create AMA handle. EA will not run.");
      return INIT_FAILED;
   }

   // Plot the AMA on the chart (sub-window 0 = main price chart)
   if(!ChartIndicatorAdd(0, 0, ama_handle))
      Print("WARNING: Could not attach AMA indicator to chart (non-fatal): ", GetLastError());

   ArraySetAsSeries(ama_buf, true);

   ArrayResize(t1_hit_tickets, 0);
   ArrayResize(t2_hit_tickets, 0);

   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Max_Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   if(Show_Dashboard) CreateDashboard();

   Print("GaganEA v2.10 initialized | Symbol: ", _Symbol,
         " | pip=", pip, " | Magic=", Magic_Number,
         " | AMA(", AMA_Period, ",", AMA_Fast_EMA, ",", AMA_Slow_EMA, ") on M1");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove the AMA plot from the chart
   int total = ChartIndicatorsTotal(0, 0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ChartIndicatorName(0, 0, i);
      if(StringFind(name, "AMA") >= 0)
         ChartIndicatorDelete(0, 0, name);
   }

   IndicatorRelease(ama_handle);
   DeleteDashboard();
}


//+------------------------------------------------------------------+
//| OnTick - Main logic                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ── AMA DIRECTION (every tick) ───────────────────────────────────
   // Compare the last CLOSED M1 bar's close price against the AMA value
   // at that same bar. This avoids repainting: bar[1] is fully formed.
   {
      double ama_dir_buf[];
      ArraySetAsSeries(ama_dir_buf, true);
      if(CopyBuffer(ama_handle, 0, 0, 2, ama_dir_buf) >= 2)
      {
         double last_close = iClose(_Symbol, PERIOD_M1, 1);
         double ama_val    = ama_dir_buf[1]; // AMA at last closed M1 bar
         ama_bullish = (last_close > ama_val); // price above AMA → BUY bias
         ama_bearish = (last_close < ama_val); // price below AMA → SELL bias
      }
   }

   // Refresh position counts and P&L
   CountOpenPositions();

   // ── PROTECTION (every tick) ──────────────────────────────────────
   if(CheckEquityProtection()) { UpdateDashboard(); return; }
   if(Use_Master_EP) CheckMasterEquityProtection();

   // ── POSITION MANAGEMENT (every tick) ────────────────────────────
   ManageTargets();           // Partial closes at T1, T2, T3
   ManageIndividualTrailing(); // Individual trail after T2
   if(Use_Basket_Trailing) ManageBasketTrailing(); // Basket trail
   if(Use_AMA_Exit) ManageAMAExit(); // M1 AMA 3-candle trend-flip exit

   // ── NEW BAR LOGIC ────────────────────────────────────────────────
   datetime current_bar = iTime(_Symbol, Trade_Timeframe, 0);
   bool new_bar = (current_bar != last_bar_time);

   if(new_bar)
   {
      last_bar_time = current_bar;

      // News filter
      if(News_Filter_Enable && IsNewsTime())
      {
         news_active    = true;
         current_signal = "NEWS PAUSE";
         signal_color   = clrOrange;
         if(Show_Dashboard) UpdateDashboard();
         return;
      }
      news_active = false;

      // ── TRADE DIRECTION: AMA-based ──────────────────────────────
      // BUY  only when last closed M1 bar is ABOVE the AMA
      // SELL only when last closed M1 bar is BELOW the AMA
      bool buy_trend_ok  = ama_bullish;
      bool sell_trend_ok = ama_bearish;

      // ── AMA PULLBACK FILTER ──────────────────────────────────────
      // ── AMA PULLBACK FILTER (ADAPTIVE) ──────────────────────────────
      // 1. Collect the close-to-AMA distance for each of the last N bars
      // 2. Compute mean and standard deviation of those distances
      // 3. Threshold = Mean + (Sigma × StdDev)
      //    → In a volatile trending market: StdDev is large → threshold widens
      //      automatically → EA doesn't become overly restrictive
      //    → In a calm ranging market: StdDev is small → threshold tightens
      //      automatically → EA only enters on genuine tight pullbacks
      pullback_ok = true;
      if(Use_AMA_Pullback)
      {
         int    pb_bars = MathMax(3, AMA_Pullback_Bars);
         double hist_ama[];
         ArraySetAsSeries(hist_ama, true);
         if(CopyBuffer(ama_handle, 0, 1, pb_bars, hist_ama) >= pb_bars)
         {
            // ── Pass 1: collect distances and compute mean ──────────
            double dists[];
            ArrayResize(dists, pb_bars);
            double sum_dist = 0;
            int    cnt      = 0;
            for(int i = 0; i < pb_bars; i++)
            {
               double ama_i = hist_ama[i];
               if(ama_i <= 0 || ama_i == EMPTY_VALUE) continue;
               double close_i   = iClose(_Symbol, PERIOD_M1, i + 1);
               dists[cnt]       = MathAbs(close_i - ama_i) / pip;
               sum_dist        += dists[cnt];
               cnt++;
            }

            if(cnt >= 3)
            {
               avg_ama_dist_pips = sum_dist / cnt;

               // ── Pass 2: std deviation ───────────────────────────
               double sum_sq = 0;
               for(int i = 0; i < cnt; i++)
                  sum_sq += (dists[i] - avg_ama_dist_pips) * (dists[i] - avg_ama_dist_pips);
               ama_dist_stddev = MathSqrt(sum_sq / cnt);

               // ── Adaptive threshold ──────────────────────────────
               ama_dist_thresh = avg_ama_dist_pips + AMA_Pullback_Sigma * ama_dist_stddev;
               ama_dist_thresh = MathMax(ama_dist_thresh, 1.0); // floor: at least 1 pip

               // ── Current bar distance ────────────────────────────
               double last_ama   = hist_ama[0];
               double last_close = iClose(_Symbol, PERIOD_M1, 1);
               cur_ama_dist_pips = (last_ama > 0 && last_ama != EMPTY_VALUE)
                                   ? MathAbs(last_close - last_ama) / pip : 0;

               pullback_ok = (cur_ama_dist_pips <= ama_dist_thresh);
            }
         }
      }

      // Pattern detection
      string bull_pattern_name = "";
      string bear_pattern_name = "";
      bool bull_signal = DetectBullishPattern(bull_pattern_name);
      bool bear_signal = DetectBearishPattern(bear_pattern_name);

      // Signal state for dashboard
      if(buy_trend_ok && bull_signal && pullback_ok)
      {
         current_signal = "BUY READY";
         signal_color   = clrLime;
      }
      else if(sell_trend_ok && bear_signal && pullback_ok)
      {
         current_signal = "SELL READY";
         signal_color   = clrRed;
      }
      else if(!pullback_ok)
      {
         current_signal = "EXTENDED - WAIT";
         signal_color   = clrOrange;
      }
      else if(buy_trend_ok || sell_trend_ok)
      {
         current_signal = "WAITING PATTERN";
         signal_color   = clrYellow;
      }
      else
      {
         current_signal = "AMA FLAT";
         signal_color   = clrGray;
      }

      // Entry conditions — pullback_ok gates all entries
      if(buy_trend_ok && bull_signal && pullback_ok && DistanceCheckOK(ORDER_TYPE_BUY))
      {
         OpenTrade(ORDER_TYPE_BUY, bull_pattern_name);
      }
      else if(sell_trend_ok && bear_signal && pullback_ok && DistanceCheckOK(ORDER_TYPE_SELL))
      {
         OpenTrade(ORDER_TYPE_SELL, bear_pattern_name);
      }
   }

   // Update dashboard every tick
   if(Show_Dashboard) UpdateDashboard();
}


//+------------------------------------------------------------------+
//| Open a new trade                                                  |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, string pattern_name = "")
{
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / pip;

   if(Max_Spread_Pips > 0 && spread > Max_Spread_Pips)
   {
      Print("Entry skipped: spread=", DoubleToString(spread,1), " pips > Max=", Max_Spread_Pips);
      return;
   }

   double lot    = CalcLotSize(spread);
   double sl     = 0;
   double tp     = 0;
   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;
   string comment = EA_Comment + "_" + pattern_name;

   if(type == ORDER_TYPE_BUY)
   {
      if(Use_StopLoss) sl = NormalizeDouble(price - (StopLoss_Pips + spread) * pip, _Digits);
      tp = NormalizeDouble(price + T3_Pips * pip, _Digits);
   }
   else
   {
      if(Use_StopLoss) sl = NormalizeDouble(price + (StopLoss_Pips + spread) * pip, _Digits);
      tp = NormalizeDouble(price - T3_Pips * pip, _Digits);
   }

   if(trade.PositionOpen(_Symbol, type, lot, price, sl, tp, comment))
   {
      Print("Trade opened: ", EnumToString(type), " lot=", lot,
            " price=", price, " sl=", sl, " tp=", tp,
            " spread=", DoubleToString(spread,1), " pips | pattern=", pattern_name);
   }
   else
   {
      Print("Trade open FAILED: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalcLotSize(double spread_pips = 0.0)
{
   if(Manual_LotSize > 0.0) return NormalizeLot(Manual_LotSize);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * Risk_Percent / 100.0;

   if(spread_pips <= 0.0)
      spread_pips = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / pip;
   double sl_distance = (StopLoss_Pips + spread_pips) * pip;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(sl_distance <= 0 || tick_value <= 0 || tick_size <= 0) return NormalizeLot(0.01);

   double lot = risk_money / (sl_distance / tick_size * tick_value);
   return NormalizeLot(MathMin(lot, Max_LotSize));
}

//+------------------------------------------------------------------+
//| Normalize lot to broker requirements                              |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step) * step;
   return NormalizeDouble(MathMax(minv, MathMin(lot, maxv)), 2);
}

//+------------------------------------------------------------------+
//| Count open positions and compute basket P&L                       |
//+------------------------------------------------------------------+
void CountOpenPositions()
{
   open_buy_count      = 0;
   open_sell_count     = 0;
   floating_pnl        = 0;
   basket_buy_combined = 0;
   basket_sell_combined= 0;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;

      double profit_swap = posInfo.Profit() + posInfo.Swap();
      floating_pnl += profit_swap;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         open_buy_count++;
         basket_buy_combined += (bid - posInfo.PriceOpen()) / pip;
      }
      else
      {
         open_sell_count++;
         basket_sell_combined += (posInfo.PriceOpen() - ask) / pip;
      }
   }
}

//+------------------------------------------------------------------+
//| Check distance from last trade of same type                       |
//+------------------------------------------------------------------+
bool DistanceCheckOK(ENUM_ORDER_TYPE type)
{
   double ref_price = -1;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
      if((type == ORDER_TYPE_BUY  && posInfo.PositionType() == POSITION_TYPE_BUY) ||
         (type == ORDER_TYPE_SELL && posInfo.PositionType() == POSITION_TYPE_SELL))
      {
         ref_price = posInfo.PriceOpen();
      }
   }

   if(ref_price < 0) return true;

   double dist_pips = MathAbs(((type == ORDER_TYPE_BUY) ? ask : bid) - ref_price) / pip;
   return (dist_pips >= Min_Trade_Distance && dist_pips <= Max_Trade_Distance);
}


//+------------------------------------------------------------------+
//| Manage T1 / T2 / T3 partial closes                               |
//+------------------------------------------------------------------+
void ManageTargets()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;

      ulong  ticket    = posInfo.Ticket();
      double open_px   = posInfo.PriceOpen();
      double vol       = posInfo.Volume();
      double min_vol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      bool   is_buy    = (posInfo.PositionType() == POSITION_TYPE_BUY);

      double cur_price   = is_buy ? bid : ask;
      double profit_pips = is_buy ? (cur_price - open_px) / pip
                                  : (open_px - cur_price) / pip;

      bool hit_t1 = TicketInArray(t1_hit_tickets, ticket);
      bool hit_t2 = TicketInArray(t2_hit_tickets, ticket);

      // T3: full close
      if(!hit_t2 && profit_pips >= T3_Pips)
      {
         if(!hit_t1) AddTicketToArray(t1_hit_tickets, ticket);
         AddTicketToArray(t2_hit_tickets, ticket);
         trade.PositionClose(ticket);
         continue;
      }

      // T2: close additional portion
      if(!hit_t2 && hit_t1 && profit_pips >= T2_Pips)
      {
         double additional_pct = (T2_ClosePercent - T1_ClosePercent) / (100.0 - T1_ClosePercent);
         double close_vol = NormalizeLot(vol * additional_pct);
         if(close_vol >= min_vol)
         {
            trade.PositionClosePartial(ticket, close_vol);
            AddTicketToArray(t2_hit_tickets, ticket);
         }
         else
         {
            trade.PositionClose(ticket);
            AddTicketToArray(t2_hit_tickets, ticket);
         }
         continue;
      }

      // T1: first partial close
      if(!hit_t1 && profit_pips >= T1_Pips)
      {
         double close_vol = NormalizeLot(vol * T1_ClosePercent / 100.0);
         if(close_vol >= min_vol)
         {
            trade.PositionClosePartial(ticket, close_vol);
            AddTicketToArray(t1_hit_tickets, ticket);
         }
         else
         {
            trade.PositionClose(ticket);
            AddTicketToArray(t1_hit_tickets, ticket);
            AddTicketToArray(t2_hit_tickets, ticket);
         }
      }
   }

   CleanTicketArrays();
}

//+------------------------------------------------------------------+
//| Individual trailing stop (activates after T2 hit)                 |
//+------------------------------------------------------------------+
void ManageIndividualTrailing()
{
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double trail_dist = Trail_Step_Pips * pip;
   double be_buffer  = 15 * pip;
   double t1_lock    = T1_Pips * pip;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;

      ulong  ticket   = posInfo.Ticket();
      double open_px  = posInfo.PriceOpen();
      double cur_sl   = posInfo.StopLoss();
      bool   is_buy   = (posInfo.PositionType() == POSITION_TYPE_BUY);
      bool   hit_t1   = TicketInArray(t1_hit_tickets, ticket);
      bool   hit_t2   = TicketInArray(t2_hit_tickets, ticket);

      // STAGE 1: T1 hit → move SL to break-even + buffer
      if(hit_t1 && !hit_t2)
      {
         if(is_buy)
         {
            double be_sl = NormalizeDouble(open_px + be_buffer, _Digits);
            if(cur_sl < be_sl - pip)
               trade.PositionModify(ticket, be_sl, posInfo.TakeProfit());
         }
         else
         {
            double be_sl = NormalizeDouble(open_px - be_buffer, _Digits);
            if(cur_sl < point_size || cur_sl > be_sl + pip)
               trade.PositionModify(ticket, be_sl, posInfo.TakeProfit());
         }
         continue;
      }

      // STAGE 2: T2 hit → trail with SL floor at T1 level
      if(!hit_t2) continue;

      if(is_buy)
      {
         double trail_sl  = NormalizeDouble(bid - trail_dist, _Digits);
         double floor_sl  = NormalizeDouble(open_px + t1_lock, _Digits);
         double target_sl = MathMax(trail_sl, floor_sl);
         if(target_sl > cur_sl + pip)
            trade.PositionModify(ticket, target_sl, posInfo.TakeProfit());
      }
      else
      {
         double trail_sl  = NormalizeDouble(ask + trail_dist, _Digits);
         double floor_sl  = NormalizeDouble(open_px - t1_lock, _Digits);
         double target_sl = MathMin(trail_sl, floor_sl);
         if(cur_sl < point_size || target_sl < cur_sl - pip)
            trade.PositionModify(ticket, target_sl, posInfo.TakeProfit());
      }
   }
}


//+------------------------------------------------------------------+
//| Basket trailing - same-side combined pips                         |
//+------------------------------------------------------------------+
void ManageBasketTrailing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // BUY basket
   if(open_buy_count > 0)
   {
      double vol_sum = 0, weighted_open = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
         if(posInfo.PositionType() != POSITION_TYPE_BUY) continue;
         vol_sum      += posInfo.Volume();
         weighted_open += posInfo.PriceOpen() * posInfo.Volume();
      }
      if(vol_sum > 0)
      {
         double avg_open  = weighted_open / vol_sum;
         double comb_pips = (bid - avg_open) / pip;
         if(comb_pips >= Basket_Lock_Pips)
         {
            double trail_sl  = NormalizeDouble(bid - Basket_Trail_Step * pip, _Digits);
            double floor_sl  = NormalizeDouble(avg_open + 5 * pip, _Digits);
            double target_sl = MathMax(trail_sl, floor_sl);
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(!posInfo.SelectByIndex(i)) continue;
               if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
               if(posInfo.PositionType() != POSITION_TYPE_BUY) continue;
               if(target_sl > posInfo.StopLoss() + pip)
                  trade.PositionModify(posInfo.Ticket(), target_sl, posInfo.TakeProfit());
            }
         }
      }
   }

   // SELL basket
   if(open_sell_count > 0)
   {
      double vol_sum = 0, weighted_open = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
         if(posInfo.PositionType() != POSITION_TYPE_SELL) continue;
         vol_sum      += posInfo.Volume();
         weighted_open += posInfo.PriceOpen() * posInfo.Volume();
      }
      if(vol_sum > 0)
      {
         double avg_open  = weighted_open / vol_sum;
         double comb_pips = (avg_open - ask) / pip;
         if(comb_pips >= Basket_Lock_Pips)
         {
            double trail_sl  = NormalizeDouble(ask + Basket_Trail_Step * pip, _Digits);
            double floor_sl  = NormalizeDouble(avg_open - 5 * pip, _Digits);
            double target_sl = MathMin(trail_sl, floor_sl);
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(!posInfo.SelectByIndex(i)) continue;
               if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
               if(posInfo.PositionType() != POSITION_TYPE_SELL) continue;
               if(posInfo.StopLoss() < point_size || target_sl < posInfo.StopLoss() - pip)
                  trade.PositionModify(posInfo.Ticket(), target_sl, posInfo.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| AMA Trend-Flip Exit (M1)                                          |
//| Closes a position fully once N consecutive CLOSED M1 candles      |
//| close on the wrong side of the AMA.                               |
//+------------------------------------------------------------------+
void ManageAMAExit()
{
   datetime m1_bar_now = iTime(_Symbol, PERIOD_M1, 0);
   if(m1_bar_now == last_m1_bar_time) return;
   last_m1_bar_time = m1_bar_now;

   if(open_buy_count == 0 && open_sell_count == 0) return;

   int need = MathMax(1, AMA_Confirm_Candles);

   if(CopyBuffer(ama_handle, 0, 1, need, ama_buf) < need) return;
   ArraySetAsSeries(ama_buf, true);

   bool all_below = true;
   bool all_above = true;

   for(int i = 0; i < need; i++)
   {
      double close_px = iClose(_Symbol, PERIOD_M1, i + 1);
      double ama_val  = ama_buf[i];

      if(ama_val == 0 || ama_val == EMPTY_VALUE) { all_below = false; all_above = false; break; }

      if(!(close_px < ama_val)) all_below = false;
      if(!(close_px > ama_val)) all_above = false;
   }

   if(all_below && open_buy_count > 0)
      CloseAllByType(POSITION_TYPE_BUY, "AMA_3Candle_Flip");

   if(all_above && open_sell_count > 0)
      CloseAllByType(POSITION_TYPE_SELL, "AMA_3Candle_Flip");
}

//+------------------------------------------------------------------+
//| Close all EA positions of one side                                |
//+------------------------------------------------------------------+
void CloseAllByType(ENUM_POSITION_TYPE type, string reason = "")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
      if(posInfo.PositionType() != type) continue;
      trade.PositionClose(posInfo.Ticket());
   }
   if(reason != "")
      Print("AMA Trend-Flip Exit: closed all ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
            " positions | reason=", reason);
}


//+------------------------------------------------------------------+
//| Equity Protection                                                 |
//+------------------------------------------------------------------+
bool CheckEquityProtection()
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_money = balance - equity;
   double dd_pct   = (balance > 0) ? dd_money / balance * 100.0 : 0;

   bool triggered = false;
   if(Use_EP_Percent && dd_pct   >= EP_Max_DD_Percent) triggered = true;
   if(Use_EP_Money   && dd_money >= EP_Max_DD_Money)   triggered = true;

   if(triggered)
   {
      Print("EQUITY PROTECTION triggered: DD=", dd_pct, "% ($", dd_money, ")");
      CloseAllPositions("EP_Global");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Master Equity Protection                                          |
//+------------------------------------------------------------------+
void CheckMasterEquityProtection()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_pct  = (balance > 0) ? (balance - equity) / balance * 100.0 : 0;
   int    total   = open_buy_count + open_sell_count;

   bool dd_trig    = (dd_pct >= Master_Trigger_DD_Percent);
   bool trade_trig = (total  >= Master_Trigger_Min_Trades);

   if(dd_trig || trade_trig)
      ApplyMasterTrailing();
}

//+------------------------------------------------------------------+
//| Apply master trailing based on logic mode                         |
//+------------------------------------------------------------------+
void ApplyMasterTrailing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double buy_sum = 0, sell_sum = 0;
   int    buy_cnt = 0, sell_cnt = 0;
   ulong  buy_tickets[];
   ulong  sell_tickets[];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != Magic_Number) continue;
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         buy_sum += posInfo.PriceOpen(); buy_cnt++;
         ArrayResize(buy_tickets, buy_cnt);
         buy_tickets[buy_cnt-1] = posInfo.Ticket();
      }
      else
      {
         sell_sum += posInfo.PriceOpen(); sell_cnt++;
         ArrayResize(sell_tickets, sell_cnt);
         sell_tickets[sell_cnt-1] = posInfo.Ticket();
      }
   }

   if(buy_cnt > 0)
   {
      double avg_open  = buy_sum / buy_cnt;
      double comb_pips = (bid - avg_open) / pip;
      if(comb_pips >= Master_Lock_Pips)
      {
         double trail_sl = NormalizeDouble(bid - Master_Trail_Step * pip, _Digits);
         ApplyTrailingToTickets(buy_tickets, trail_sl, true);
      }
   }

   if(sell_cnt > 0)
   {
      double avg_open  = sell_sum / sell_cnt;
      double comb_pips = (avg_open - ask) / pip;
      if(comb_pips >= Master_Lock_Pips)
      {
         double trail_sl = NormalizeDouble(ask + Master_Trail_Step * pip, _Digits);
         ApplyTrailingToTickets(sell_tickets, trail_sl, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Apply SL to a set of tickets                                      |
//+------------------------------------------------------------------+
void ApplyTrailingToTickets(ulong &tickets[], double new_sl, bool is_buy)
{
   for(int t = 0; t < ArraySize(tickets); t++)
   {
      if(!posInfo.SelectByTicket(tickets[t])) continue;
      double cur_sl = posInfo.StopLoss();
      if(is_buy)
      {
         if(new_sl > cur_sl + pip)
            trade.PositionModify(tickets[t], new_sl, posInfo.TakeProfit());
      }
      else
      {
         if(cur_sl < point_size || new_sl < cur_sl - pip)
            trade.PositionModify(tickets[t], new_sl, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Close all EA positions                                            |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason = "")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == Magic_Number)
            trade.PositionClose(posInfo.Ticket());
   }
   if(reason != "") Print("CloseAll: ", reason);
}

//+------------------------------------------------------------------+
//| TICKET TRACKING HELPERS                                           |
//+------------------------------------------------------------------+
bool TicketInArray(ulong &arr[], ulong ticket)
{
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == ticket) return true;
   return false;
}

void AddTicketToArray(ulong &arr[], ulong ticket)
{
   if(TicketInArray(arr, ticket)) return;
   int sz = ArraySize(arr);
   ArrayResize(arr, sz + 1);
   arr[sz] = ticket;
}

void CleanTicketArrays()
{
   ulong new_t1[], new_t2[];
   for(int i = 0; i < ArraySize(t1_hit_tickets); i++)
      if(posInfo.SelectByTicket(t1_hit_tickets[i]))
      {
         int sz = ArraySize(new_t1);
         ArrayResize(new_t1, sz+1);
         new_t1[sz] = t1_hit_tickets[i];
      }
   for(int i = 0; i < ArraySize(t2_hit_tickets); i++)
      if(posInfo.SelectByTicket(t2_hit_tickets[i]))
      {
         int sz = ArraySize(new_t2);
         ArrayResize(new_t2, sz+1);
         new_t2[sz] = t2_hit_tickets[i];
      }
   ArrayCopy(t1_hit_tickets, new_t1);
   ArrayCopy(t2_hit_tickets, new_t2);
   ArrayResize(t1_hit_tickets, ArraySize(new_t1));
   ArrayResize(t2_hit_tickets, ArraySize(new_t2));
}


//+------------------------------------------------------------------+
//| CANDLESTICK PATTERN DETECTION - BULLISH                           |
//| Doji context uses ama_bullish (replaces htf_bullish)              |
//+------------------------------------------------------------------+
bool DetectBullishPattern(string &pattern_name)
{
   double o1 = iOpen(_Symbol,  Trade_Timeframe, 1);
   double h1 = iHigh(_Symbol,  Trade_Timeframe, 1);
   double l1 = iLow(_Symbol,   Trade_Timeframe, 1);
   double c1 = iClose(_Symbol, Trade_Timeframe, 1);
   double o2 = iOpen(_Symbol,  Trade_Timeframe, 2);
   double h2 = iHigh(_Symbol,  Trade_Timeframe, 2);
   double l2 = iLow(_Symbol,   Trade_Timeframe, 2);
   double c2 = iClose(_Symbol, Trade_Timeframe, 2);
   double o3 = iOpen(_Symbol,  Trade_Timeframe, 3);
   double c3 = iClose(_Symbol, Trade_Timeframe, 3);

   double body1  = MathAbs(c1 - o1);
   double range1 = h1 - l1;
   double body2  = MathAbs(c2 - o2);

   // Hammer
   if(Use_Hammer && c1 > o1 && body1 > 0)
   {
      double lower = o1 - l1;
      double upper = h1 - c1;
      if(lower >= 2.0 * body1 && upper <= 0.3 * body1)
      { pattern_name = "Hammer"; return true; }
   }

   // Inverted Hammer
   if(Use_InvHammer && c1 > o1 && body1 > 0)
   {
      double upper = h1 - c1;
      double lower = o1 - l1;
      if(upper >= 2.0 * body1 && lower <= 0.3 * body1)
      { pattern_name = "InvHammer"; return true; }
   }

   // Bullish Engulfing
   if(Use_BullEngulf && c2 < o2 && c1 > o1 && o1 <= c2 && c1 >= o2)
   { pattern_name = "BullEngulf"; return true; }

   // Piercing Line
   if(Use_PiercingLine && c2 < o2 && c1 > o1 && o1 < c2 && c1 > (o2 + c2) / 2.0 && c1 < o2)
   { pattern_name = "PiercingLine"; return true; }

   // Morning Star
   if(Use_MorningStar)
   {
      double body3 = MathAbs(c3 - o3);
      if(c3 < o3 && body2 < 0.3 * body3 && c1 > o1 && c1 > (o3 + c3) / 2.0)
      { pattern_name = "MorningStar"; return true; }
   }

   // Three White Soldiers
   if(Use_ThreeWhite)
   {
      double o4 = iOpen(_Symbol, Trade_Timeframe, 4);
      double c4 = iClose(_Symbol, Trade_Timeframe, 4);
      if(c1>o1 && c2>o2 && c3>o3 && c1>c2 && c2>c3 && o1<c2 && o2<c3)
      { pattern_name = "ThreeWhite"; return true; }
   }

   // Bullish Harami
   if(Use_BullHarami && c2 < o2 && c1 > o1 && o1 > c2 && c1 < o2 && body1 < body2)
   { pattern_name = "BullHarami"; return true; }

   // Doji: use ama_bullish (price above AMA) as bullish context
   if(Use_Doji && range1 > 0 && body1 / range1 < 0.1 && ama_bullish)
   { pattern_name = "Doji"; return true; }

   // Chart Patterns
   if(Use_DoubleBottom && DetectDoubleBottom())
   { pattern_name = "DblBottom"; return true; }

   if(Use_InvHeadShould && DetectInvHeadShoulders())
   { pattern_name = "InvH&S"; return true; }

   if(Use_BullFlag && DetectBullFlag())
   { pattern_name = "BullFlag"; return true; }

   if(Use_FallingWedge && DetectFallingWedge())
   { pattern_name = "FallWedge"; return true; }

   if(Use_BullTriangle && DetectAscendingTriangle())
   { pattern_name = "AscTriangle"; return true; }

   pattern_name = "";
   return false;
}

//+------------------------------------------------------------------+
//| CANDLESTICK PATTERN DETECTION - BEARISH                           |
//| Doji context uses ama_bearish (replaces htf_bearish)              |
//+------------------------------------------------------------------+
bool DetectBearishPattern(string &pattern_name)
{
   double o1 = iOpen(_Symbol,  Trade_Timeframe, 1);
   double h1 = iHigh(_Symbol,  Trade_Timeframe, 1);
   double l1 = iLow(_Symbol,   Trade_Timeframe, 1);
   double c1 = iClose(_Symbol, Trade_Timeframe, 1);
   double o2 = iOpen(_Symbol,  Trade_Timeframe, 2);
   double h2 = iHigh(_Symbol,  Trade_Timeframe, 2);
   double l2 = iLow(_Symbol,   Trade_Timeframe, 2);
   double c2 = iClose(_Symbol, Trade_Timeframe, 2);
   double o3 = iOpen(_Symbol,  Trade_Timeframe, 3);
   double c3 = iClose(_Symbol, Trade_Timeframe, 3);

   double body1  = MathAbs(c1 - o1);
   double range1 = h1 - l1;
   double body2  = MathAbs(c2 - o2);

   // Shooting Star
   if(Use_ShootingStar && c1 < o1 && body1 > 0)
   {
      double upper = h1 - o1;
      double lower = c1 - l1;
      if(upper >= 2.0 * body1 && lower <= 0.3 * body1)
      { pattern_name = "ShootStar"; return true; }
   }

   // Bearish Engulfing
   if(Use_BearEngulf && c2 > o2 && c1 < o1 && o1 >= c2 && c1 <= o2)
   { pattern_name = "BearEngulf"; return true; }

   // Evening Star
   if(Use_EveningStar)
   {
      double body3 = MathAbs(c3 - o3);
      if(c3 > o3 && body2 < 0.3 * body3 && c1 < o1 && c1 < (o3 + c3) / 2.0)
      { pattern_name = "EveningStar"; return true; }
   }

   // Three Black Crows
   if(Use_ThreeBlack)
   {
      double o4 = iOpen(_Symbol, Trade_Timeframe, 4);
      double c4 = iClose(_Symbol, Trade_Timeframe, 4);
      if(c1<o1 && c2<o2 && c3<o3 && c1<c2 && c2<c3 && o1>c2 && o2>c3)
      { pattern_name = "ThreeBlack"; return true; }
   }

   // Dark Cloud Cover
   if(Use_DarkCloud && c2 > o2 && c1 < o1 && o1 > c2 && c1 < (o2 + c2) / 2.0 && c1 > o2)
   { pattern_name = "DarkCloud"; return true; }

   // Bearish Harami
   if(Use_BearHarami && c2 > o2 && c1 < o1 && o1 < c2 && c1 > o2 && body1 < body2)
   { pattern_name = "BearHarami"; return true; }

   // Hanging Man
   if(Use_HangingMan && c1 < o1 && body1 > 0)
   {
      double lower = o1 - l1;
      double upper = h1 - c1;
      if(lower >= 2.0 * body1 && upper <= 0.3 * body1)
      { pattern_name = "HangingMan"; return true; }
   }

   // Doji: use ama_bearish (price below AMA) as bearish context
   if(Use_Doji && range1 > 0 && body1 / range1 < 0.1 && ama_bearish)
   { pattern_name = "Doji"; return true; }

   // Chart patterns
   if(Use_DoubleTop && DetectDoubleTop())
   { pattern_name = "DblTop"; return true; }

   if(Use_HeadShoulders && DetectHeadShoulders())
   { pattern_name = "H&S"; return true; }

   if(Use_BearFlag && DetectBearFlag())
   { pattern_name = "BearFlag"; return true; }

   if(Use_RisingWedge && DetectRisingWedge())
   { pattern_name = "RisingWedge"; return true; }

   if(Use_BearTriangle && DetectDescendingTriangle())
   { pattern_name = "DescTriangle"; return true; }

   pattern_name = "";
   return false;
}


//+------------------------------------------------------------------+
//| CHART PATTERN HELPERS (price structure, 20-bar lookback)          |
//+------------------------------------------------------------------+
bool DetectDoubleTop()
{
   int lb = 20;
   double highs[];
   ArrayResize(highs, lb);
   for(int i = 0; i < lb; i++) highs[i] = iHigh(_Symbol, Trade_Timeframe, i+1);

   int peak1 = -1, peak2 = -1;
   for(int i = 2; i < lb-2; i++)
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1])
      { if(peak1 < 0) peak1 = i; else { peak2 = i; break; } }

   if(peak1 < 0 || peak2 < 0) return false;
   double pct_diff = MathAbs(highs[peak1] - highs[peak2]) / highs[peak1];
   return (pct_diff < 0.005);
}

bool DetectDoubleBottom()
{
   int lb = 20;
   double lows[];
   ArrayResize(lows, lb);
   for(int i = 0; i < lb; i++) lows[i] = iLow(_Symbol, Trade_Timeframe, i+1);

   int trough1 = -1, trough2 = -1;
   for(int i = 2; i < lb-2; i++)
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1])
      { if(trough1 < 0) trough1 = i; else { trough2 = i; break; } }

   if(trough1 < 0 || trough2 < 0) return false;
   double pct_diff = MathAbs(lows[trough1] - lows[trough2]) / lows[trough1];
   return (pct_diff < 0.005);
}

bool DetectHeadShoulders()
{
   int lb = 30;
   double highs[];
   ArrayResize(highs, lb);
   for(int i = 0; i < lb; i++) highs[i] = iHigh(_Symbol, Trade_Timeframe, i+1);
   double maxH = 0; int headIdx = -1;
   for(int i = 2; i < lb-2; i++)
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1] && highs[i] > maxH)
      { maxH = highs[i]; headIdx = i; }
   if(headIdx < 3 || headIdx > lb-4) return false;
   double ls = 0;
   for(int i = headIdx+2; i < lb-1; i++)
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1]) { ls = highs[i]; break; }
   double rs = 0;
   for(int i = headIdx-2; i > 0; i--)
      if(highs[i] > highs[i-1] && highs[i] > highs[i+1]) { rs = highs[i]; break; }
   if(ls <= 0 || rs <= 0) return false;
   return (maxH > ls * 1.01 && maxH > rs * 1.01 && MathAbs(ls - rs) / ls < 0.02);
}

bool DetectInvHeadShoulders()
{
   int lb = 30;
   double lows[];
   ArrayResize(lows, lb);
   for(int i = 0; i < lb; i++) lows[i] = iLow(_Symbol, Trade_Timeframe, i+1);
   double minL = DBL_MAX; int headIdx = -1;
   for(int i = 2; i < lb-2; i++)
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1] && lows[i] < minL)
      { minL = lows[i]; headIdx = i; }
   if(headIdx < 3 || headIdx > lb-4) return false;
   double ls = DBL_MAX;
   for(int i = headIdx+2; i < lb-1; i++)
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1]) { ls = lows[i]; break; }
   double rs = DBL_MAX;
   for(int i = headIdx-2; i > 0; i--)
      if(lows[i] < lows[i-1] && lows[i] < lows[i+1]) { rs = lows[i]; break; }
   if(ls >= DBL_MAX || rs >= DBL_MAX) return false;
   return (minL < ls * 0.99 && minL < rs * 0.99 && MathAbs(ls - rs) / ls < 0.02);
}

bool DetectBullFlag()
{
   double c5  = iClose(_Symbol, Trade_Timeframe, 5);
   double c1  = iClose(_Symbol, Trade_Timeframe, 1);
   double flagpole     = (iClose(_Symbol, Trade_Timeframe, 10) - c5) / pip;
   double consolidation = MathAbs(c1 - c5) / pip;
   return (flagpole > 50 && consolidation < flagpole * 0.4);
}

bool DetectBearFlag()
{
   double c5  = iClose(_Symbol, Trade_Timeframe, 5);
   double c10 = iClose(_Symbol, Trade_Timeframe, 10);
   double c1  = iClose(_Symbol, Trade_Timeframe, 1);
   double flagpole      = (c5 - c10) / pip;
   double consolidation = MathAbs(c1 - c5) / pip;
   return (flagpole > 50 && consolidation < flagpole * 0.4);
}

bool DetectRisingWedge()
{
   int lb = 15;
   double h1 = iHigh(_Symbol, Trade_Timeframe, 1);
   double hN = iHigh(_Symbol, Trade_Timeframe, lb);
   double l1 = iLow(_Symbol,  Trade_Timeframe, 1);
   double lN = iLow(_Symbol,  Trade_Timeframe, lb);
   bool rising   = (h1 > hN && l1 > lN);
   bool narrowing = ((h1 - l1) < (hN - lN) * 0.7);
   return (rising && narrowing);
}

bool DetectFallingWedge()
{
   int lb = 15;
   double h1 = iHigh(_Symbol, Trade_Timeframe, 1);
   double hN = iHigh(_Symbol, Trade_Timeframe, lb);
   double l1 = iLow(_Symbol,  Trade_Timeframe, 1);
   double lN = iLow(_Symbol,  Trade_Timeframe, lb);
   bool falling  = (h1 < hN && l1 < lN);
   bool narrowing = ((h1 - l1) < (hN - lN) * 0.7);
   return (falling && narrowing);
}

bool DetectAscendingTriangle()
{
   int lb = 15;
   double h_avg_early = (iHigh(_Symbol, Trade_Timeframe, lb)   + iHigh(_Symbol, Trade_Timeframe, lb-1)) / 2;
   double h_avg_late  = (iHigh(_Symbol, Trade_Timeframe, 2)    + iHigh(_Symbol, Trade_Timeframe, 1))    / 2;
   double l_early     = iLow(_Symbol,   Trade_Timeframe, lb);
   double l_late      = iLow(_Symbol,   Trade_Timeframe, 1);
   return (MathAbs(h_avg_early - h_avg_late) / h_avg_early < 0.003 && l_late > l_early * 1.005);
}

bool DetectDescendingTriangle()
{
   int lb = 15;
   double l_avg_early = (iLow(_Symbol, Trade_Timeframe, lb)   + iLow(_Symbol, Trade_Timeframe, lb-1)) / 2;
   double l_avg_late  = (iLow(_Symbol, Trade_Timeframe, 2)    + iLow(_Symbol, Trade_Timeframe, 1))    / 2;
   double h_early     = iHigh(_Symbol, Trade_Timeframe, lb);
   double h_late      = iHigh(_Symbol, Trade_Timeframe, 1);
   return (MathAbs(l_avg_early - l_avg_late) / l_avg_early < 0.003 && h_late < h_early * 0.995);
}

//+------------------------------------------------------------------+
//| News filter placeholder                                           |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   return false;
}

//+------------------------------------------------------------------+
//| Get P&L for a period                                              |
//+------------------------------------------------------------------+
double GetPeriodPnL(datetime from_time, datetime to_time)
{
   double pnl = 0;
   if(!HistorySelect(from_time, to_time)) return 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL)  != _Symbol) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != Magic_Number) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  == DEAL_ENTRY_OUT)
         pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
               + HistoryDealGetDouble(ticket, DEAL_SWAP)
               + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl;
}

void RefreshPnLCache()
{
   datetime now = TimeCurrent();
   if(now - pnl_cache_time < 60) return;
   pnl_cache_time = now;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today_start = StructToTime(dt);

   dt.day--;
   datetime yesterday_start = StructToTime(dt);

   dt.day = dt.day - dt.day_of_week + 1;
   datetime week_start = StructToTime(dt);

   dt.day = 1;
   datetime month_start = StructToTime(dt);

   dt.mon--;
   if(dt.mon < 1) { dt.mon = 12; dt.year--; }
   datetime last_month_start = StructToTime(dt);

   pnl_today      = GetPeriodPnL(today_start,      now);
   pnl_yesterday  = GetPeriodPnL(yesterday_start,   today_start);
   pnl_week       = GetPeriodPnL(week_start,        now);
   pnl_month      = GetPeriodPnL(month_start,       now);
   pnl_last_month = GetPeriodPnL(last_month_start,  month_start);
}


//+------------------------------------------------------------------+
//| DASHBOARD                                                         |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DeleteDashboard();
   int x = Dashboard_X, y = Dashboard_Y;

   color bg_col     = C'22,30,45';
   color border_col = C'45,55,90';
   color lbl_col    = clrSilver;
   color val_col    = clrWhite;
   int   lfs        = 8;
   int   vx         = x + 110;
   int   row        = 14;

   ObjRect(lbl+"bg", x-8, y-8, 325, 420, bg_col, border_col, 1);

   ObjLabel(lbl+"bullet", "\x25A0", x, y+2, C'255,140,0', 10, true);
   ObjLabel(lbl+"title",  " GaganEA v2.10", x+12, y+2, clrWhite, 9, true);
   ObjLine(lbl+"d0", x, y+18, 305);

   // --- Symbol / TF block ---
   int r = y+28;
   ObjLabel(lbl+"l_sym",  "Symbol",    x,  r,        lbl_col, lfs);
   ObjLabel(lbl+"v_sym",  _Symbol,     vx, r,        val_col, lfs);
   ObjLabel(lbl+"l_ttf",  "Trade TF",  x,  r+row,    lbl_col, lfs);
   ObjLabel(lbl+"v_ttf",  TFStr(Trade_Timeframe), vx, r+row, val_col, lfs);
   ObjLabel(lbl+"l_htf",  "AMA TF",    x,  r+row*2,  lbl_col, lfs);
   ObjLabel(lbl+"v_htf",  "M1",        vx, r+row*2,  val_col, lfs);
   ObjLine(lbl+"d1", x, r+row*3+2, 305);

   // --- AMA Direction block (replaces HTF Trend / CTF EMA / Distance) ---
   r = y+28 + row*3 + 12;
   ObjLabel(lbl+"l_trend", "AMA Direction", x,  r,        lbl_col, lfs);
   ObjLabel(lbl+"v_trend", "---",           vx, r,        val_col, lfs);
   ObjLabel(lbl+"l_ctf",   "AMA Value",     x,  r+row,    lbl_col, lfs);
   ObjLabel(lbl+"v_ctf",   "---",           vx, r+row,    val_col, lfs);
   ObjLabel(lbl+"l_dist",  "Pullback",       x,  r+row*2,  lbl_col, lfs);
   ObjLabel(lbl+"v_dist",  "---",           vx, r+row*2,  val_col, lfs);
   ObjLabel(lbl+"l_sig",   "Signal",        x,  r+row*3,  lbl_col, lfs);
   ObjLabel(lbl+"v_sig",   "---",           vx, r+row*3,  val_col, lfs);
   ObjLabel(lbl+"l_sprd",  "Spread",        x,  r+row*4,  lbl_col, lfs);
   ObjLabel(lbl+"v_sprd",  "---",           vx, r+row*4,  val_col, lfs);
   ObjLine(lbl+"d2", x, r+row*5+2, 305);

   // --- Trade block ---
   r = r + row*5 + 12;
   ObjLabel(lbl+"l_open", "Open Trades",  x,  r,        lbl_col, lfs);
   ObjLabel(lbl+"v_open", "0",            vx, r,        val_col, lfs);
   ObjLabel(lbl+"l_lot",  "Lot Size",     x,  r+row,    lbl_col, lfs);
   ObjLabel(lbl+"v_lot",  "---",          vx, r+row,    val_col, lfs);
   ObjLabel(lbl+"l_fpnl", "Floating P/L", x,  r+row*2,  lbl_col, lfs);
   ObjLabel(lbl+"v_fpnl", "---",          vx, r+row*2,  val_col, lfs);
   ObjLine(lbl+"d3", x, r+row*3+2, 305);

   // SL/T info + Lot Mode
   r = r + row*3 + 10;
   ObjLabel(lbl+"l_slinfo", StringFormat("SL: %d  |  T1:%d  |  T2:%d  |  T3:%d",
            StopLoss_Pips, T1_Pips, T2_Pips, T3_Pips), x, r, lbl_col, lfs);
   ObjLabel(lbl+"l_lm",  "Lot Mode",  x,   r+row,  lbl_col, lfs);
   ObjLabel(lbl+"v_lm",  Manual_LotSize > 0
            ? StringFormat("Manual %.2f", Manual_LotSize)
            : StringFormat("Auto %.1f%%", Risk_Percent), vx, r+row, val_col, lfs);
   ObjLine(lbl+"d4", x, r+row*2+4, 305);

   // --- P&L block ---
   r = r + row*2 + 14;
   ObjLabel(lbl+"l_today", "Today :",     x,       r,       lbl_col, lfs);
   ObjLabel(lbl+"v_today", "---",         x+55,    r,       val_col, lfs);
   ObjLabel(lbl+"l_yest",  "| Yest :",    x+150,   r,       lbl_col, lfs);
   ObjLabel(lbl+"v_yest",  "---",         x+210,   r,       val_col, lfs);

   ObjLabel(lbl+"l_week",  "This Week :", x,       r+row,   lbl_col, lfs);
   ObjLabel(lbl+"v_week",  "---",         x+75,    r+row,   val_col, lfs);
   ObjLabel(lbl+"l_mo",    "| This Mo :", x+150,   r+row,   lbl_col, lfs);
   ObjLabel(lbl+"v_mo",    "---",         x+215,   r+row,   val_col, lfs);

   ObjLabel(lbl+"l_lmo",   "Last Month :",x,       r+row*2, lbl_col, lfs);
   ObjLabel(lbl+"v_lmo",   "---",         x+80,    r+row*2, val_col, lfs);
   ObjLine(lbl+"d5", x, r+row*3+2, 305);

   // --- News + Last Bar block ---
   r = r + row*3 + 12;
   ObjLabel(lbl+"l_news", "News Filter",  x,  r,       lbl_col, lfs);
   ObjLabel(lbl+"v_news", "OFF",          vx, r,       clrLime,  lfs);
   ObjLabel(lbl+"l_bar",  "Last Bar",     x,  r+row,   lbl_col, lfs);
   ObjLabel(lbl+"v_bar",  "---",          vx, r+row,   val_col, lfs);
   ObjLine(lbl+"d6", x, r+row*2+4, 305);

   // --- AMA Exit block ---
   r = r + row*2 + 12;
   ObjLabel(lbl+"l_ama",   "AMA Exit (M1)",  x,  r,       lbl_col, lfs);
   ObjLabel(lbl+"v_ama",   Use_AMA_Exit ? "ON" : "OFF", vx, r, Use_AMA_Exit ? clrLime : clrGray, lfs);
   ObjLabel(lbl+"l_amast", "Flip Status",    x,  r+row,   lbl_col, lfs);
   ObjLabel(lbl+"v_amast", "---",            vx, r+row,   val_col, lfs);
   ObjLine(lbl+"d7", x, r+row*2+4, 305);

   // --- Status ---
   r = r + row*2 + 12;
   ObjLabel(lbl+"l_sta", "Status",  x,  r, lbl_col, lfs);
   ObjLabel(lbl+"v_sta", "RUNNING", vx, r, clrLime,  lfs);

   ChartRedraw(0);
}


void UpdateDashboard()
{
   if(!Show_Dashboard) return;

   // ── AMA Direction (replaces HTF trend) ──────────────────────────
   string trend_str = ama_bullish ? "▲ ABOVE AMA (BUY)"
                    : (ama_bearish ? "▼ BELOW AMA (SELL)" : "ON AMA");
   color  trend_col = ama_bullish ? clrLime : (ama_bearish ? clrTomato : clrWhite);
   ObjSetText(lbl+"v_trend", trend_str, trend_col);

   // ── AMA Value (last closed M1 bar) ──────────────────────────────
   double ama_disp_buf[];
   ArraySetAsSeries(ama_disp_buf, true);
   double ama_val_display = 0;
   if(CopyBuffer(ama_handle, 0, 0, 2, ama_disp_buf) >= 2)
      ama_val_display = ama_disp_buf[1];
   ObjSetText(lbl+"v_ctf", DoubleToString(ama_val_display, _Digits), clrWhite);

   // ── Pullback filter: adaptive display ───────────────────────────
   if(Use_AMA_Pullback)
   {
      string pb_str;
      color  pb_col;
      if(avg_ama_dist_pips <= 0)
      {
         pb_str = "Calculating...";
         pb_col = clrGray;
      }
      else
      {
         // Volatility regime label based on coefficient of variation
         double cv = (avg_ama_dist_pips > 0) ? ama_dist_stddev / avg_ama_dist_pips : 0;
         string regime = (cv < 0.30) ? "CALM" : (cv < 0.60) ? "NORMAL" : "VOLATILE";
         if(pullback_ok)
         {
            pb_str = StringFormat("%.1fp ≤ %.1fp [%s]", cur_ama_dist_pips, ama_dist_thresh, regime);
            pb_col = clrLime;
         }
         else
         {
            pb_str = StringFormat("%.1fp > %.1fp [%s]", cur_ama_dist_pips, ama_dist_thresh, regime);
            pb_col = clrOrange;
         }
      }
      ObjSetText(lbl+"v_dist", pb_str, pb_col);
   }
   else
   {
      // ama_val_display already computed above — reuse it, no second CopyBuffer needed
      double bid_now2   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double dist_pips2 = (ama_val_display > 0) ? MathAbs(bid_now2 - ama_val_display) / pip : 0;
      ObjSetText(lbl+"v_dist",
                 StringFormat("%.1f pips %s", dist_pips2, ama_bullish ? "above" : "below"),
                 ama_bullish ? clrLime : clrTomato);
   }

   // ── Signal ───────────────────────────────────────────────────────
   ObjSetText(lbl+"v_sig", current_signal, signal_color);

   // ── Live spread ──────────────────────────────────────────────────
   double bid_now     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double live_spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - bid_now) / pip;
   color  sprd_col    = (Max_Spread_Pips > 0 && live_spread > Max_Spread_Pips) ? clrTomato : clrLime;
   ObjSetText(lbl+"v_sprd",
              StringFormat("%.1f pips%s", live_spread,
              (Max_Spread_Pips > 0 && live_spread > Max_Spread_Pips) ? " WIDE!" : " OK"),
              sprd_col);

   // ── Open trades ──────────────────────────────────────────────────
   ObjSetText(lbl+"v_open",
              StringFormat("%d (B:%d S:%d)", open_buy_count + open_sell_count,
              open_buy_count, open_sell_count), clrWhite);

   // ── Lot size ─────────────────────────────────────────────────────
   ObjSetText(lbl+"v_lot", StringFormat("%.2f", CalcLotSize()), clrWhite);

   // ── Floating P&L ─────────────────────────────────────────────────
   ObjSetText(lbl+"v_fpnl", StringFormat("%.2f", floating_pnl),
              floating_pnl >= 0 ? clrLime : clrTomato);

   // ── Period P&L ───────────────────────────────────────────────────
   RefreshPnLCache();
   ObjSetText(lbl+"v_today", StringFormat("USD %.2f", pnl_today),      pnl_today  >= 0 ? clrLime : clrTomato);
   ObjSetText(lbl+"v_yest",  StringFormat("USD %.2f", pnl_yesterday),  clrWhite);
   ObjSetText(lbl+"v_week",  StringFormat("USD %.2f", pnl_week),       pnl_week   >= 0 ? clrLime : clrTomato);
   ObjSetText(lbl+"v_mo",    StringFormat("USD %.2f", pnl_month),      pnl_month  >= 0 ? clrLime : clrTomato);
   ObjSetText(lbl+"v_lmo",   StringFormat("USD %.2f", pnl_last_month), clrWhite);

   // ── News ─────────────────────────────────────────────────────────
   string news_str = News_Filter_Enable ? (news_active ? "ACTIVE!" : "ON") : "OFF";
   ObjSetText(lbl+"v_news", news_str, news_active ? clrOrange : clrLime);

   // ── Last bar ─────────────────────────────────────────────────────
   ObjSetText(lbl+"v_bar", TimeToString(last_bar_time, TIME_DATE|TIME_MINUTES), clrWhite);

   // ── AMA flip-confirmation progress ───────────────────────────────
   UpdateAMADashboard();

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Dashboard: show live AMA flip-confirmation progress               |
//+------------------------------------------------------------------+
void UpdateAMADashboard()
{
   if(!Use_AMA_Exit) { ObjSetText(lbl+"v_amast", "DISABLED", clrGray); return; }
   if(open_buy_count == 0 && open_sell_count == 0) { ObjSetText(lbl+"v_amast", "No Position", clrGray); return; }

   int need = MathMax(1, AMA_Confirm_Candles);
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(ama_handle, 0, 1, need, buf) < need)
   {
      ObjSetText(lbl+"v_amast", "---", clrGray);
      return;
   }

   if(open_buy_count > 0)
   {
      int count_against = 0;
      for(int i = 0; i < need; i++)
      {
         double close_px = iClose(_Symbol, PERIOD_M1, i + 1);
         if(close_px < buf[i]) count_against++;
         else break;
      }
      ObjSetText(lbl+"v_amast",
                 StringFormat("BUY %d/%d below", count_against, need),
                 count_against >= need ? clrTomato : clrYellow);
   }
   else if(open_sell_count > 0)
   {
      int count_against = 0;
      for(int i = 0; i < need; i++)
      {
         double close_px = iClose(_Symbol, PERIOD_M1, i + 1);
         if(close_px > buf[i]) count_against++;
         else break;
      }
      ObjSetText(lbl+"v_amast",
                 StringFormat("SELL %d/%d above", count_against, need),
                 count_against >= need ? clrTomato : clrYellow);
   }
}


//+------------------------------------------------------------------+
//| Dashboard object helpers                                          |
//+------------------------------------------------------------------+
void ObjLabel(string name, string text, int x, int y, color clr, int fs=8, bool bold=false)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetString(0,  name, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}

void ObjSetText(string name, string text, color clr)
{
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void ObjLine(string name, int x, int y, int width)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   string dashes = "";
   int count = (int)(width / 5.5);
   for(int i = 0; i < count; i++) dashes += "-";
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT,      dashes);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     C'45,55,90');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  6);
   ObjectSetString(0,  name, OBJPROP_FONT,      "Arial");
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}

void ObjRect(string name, int x, int y, int w, int h, color bg, color border, int bwidth)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       bwidth);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
}

void DeleteDashboard() { ObjectsDeleteAll(0, lbl); }

string TFStr(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";  case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15"; case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";  case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";  case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";  default:         return "?";
   }
}
//+------------------------------------------------------------------+
