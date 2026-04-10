// MQL5\Include\Vtun_Mom\Vturn_StrategyVTurn.mqh
#ifndef VTURN_MOM_VTURN_STRATEGY_MQH
#define VTURN_MOM_VTURN_STRATEGY_MQH

// --- Minimal VTurn strategy module (NAS100)
// Philosophy: trade only on CLOSED bar (shift=1). No lookahead.

struct VTurnCfg
{
   // Core params
   int    bb_period;          // Bollinger period
   double bb_dev;             // Bollinger deviation
   int    mom_short_period;   // Momentum short lookback
   int    mom_long_period;    // Momentum long lookback (optional)

   // Stops
   double stop_pct;           // SL % from entry
   double take_pct;           // TP % from entry

   // Direction
   bool   allow_buy;
   bool   allow_sell;         // allow sell: keep false; this is long-only strategy
};

struct VTurnState
{
   int hBands;   // iBands handle
   bool ready;
};

static VTurnCfg   gVTurnCfg;
static VTurnState gVTurnSt;

// --- Helpers
static int VTurn_MinBarsNeeded()
{
   // We evaluate at shifts 4,3,1 and need iClose(shift + mom_period)
   // Worst case: shift=4 + mom_short_period.
   int need_short = 4 + gVTurnCfg.mom_short_period + 5; // +5 margin
   int need_long  = 4 + gVTurnCfg.mom_long_period  + 5; // +5 margin
   int need = (need_short > need_long ? need_short : need_long);
   if(need < 100) need = 100; // defensive floor
   return need;
}

static bool VTurn_HasEnoughBars()
{
   int bars = Bars(_Symbol, _Period);
   return (bars >= VTurn_MinBarsNeeded());
}

// Momentum on CLOSED bar: close[shift] - close[shift + momLen]
static bool VTurn_MomentumAtShift(const int shift, const int momLen, double &outMom)
{
   outMom = 0.0;
   if(momLen <= 0) return false;

   double c0 = iClose(_Symbol, _Period, shift);
   double c1 = iClose(_Symbol, _Period, shift + momLen);

   if(c0 == 0.0 || c1 == 0.0) return false;
   outMom = (c0 - c1);
   return true;
}

// Bollinger mid (buffer=1) at shift (CLOSED bar)
static bool VTurn_BBMidAtShift(const int shift, double &outMid)
{
   outMid = 0.0;
   if(gVTurnSt.hBands == INVALID_HANDLE) return false;

   double mid[];
   ArrayResize(mid, 1);
   ArraySetAsSeries(mid, true);

   // MT5 iBands buffers: 0=upper, 1=middle, 2=lower
   int got = CopyBuffer(gVTurnSt.hBands, 1, shift, 1, mid);
   if(got != 1) return false;

   outMid = mid[0];
   return (outMid != 0.0);
}

// --- Public API
static bool VTurn_Init(const VTurnCfg &cfg)
{
   gVTurnCfg = cfg;

   gVTurnSt.ready  = false;
   gVTurnSt.hBands = INVALID_HANDLE;

   gVTurnSt.hBands = iBands(_Symbol, _Period, gVTurnCfg.bb_period, 0, gVTurnCfg.bb_dev, PRICE_CLOSE);
   if(gVTurnSt.hBands == INVALID_HANDLE)
      return false;

   gVTurnSt.ready = true;
   return true;
}

static void VTurn_Deinit()
{
   if(gVTurnSt.hBands != INVALID_HANDLE)
      IndicatorRelease(gVTurnSt.hBands);

   gVTurnSt.hBands = INVALID_HANDLE;
   gVTurnSt.ready  = false;
}

// Compute fixed SL/TP by % (same spirit you already use)
static void VTurn_ComputeFixedSLTP_Pct(const bool isBuy, const double entry, double &sl, double &tp)
{
   sl = 0.0; tp = 0.0;
   if(entry <= 0.0) return;

   double sp  = gVTurnCfg.stop_pct / 100.0;
   double tpp = gVTurnCfg.take_pct / 100.0;

   if(isBuy)
   {
      sl = entry * (1.0 - sp);
      tp = entry * (1.0 + tpp);
   }
   else
   {
      sl = entry * (1.0 + sp);
      tp = entry * (1.0 - tpp);
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
}

// Signal evaluation (CLOSED bar). Output: longSignal/shortSignal.
static bool VTurn_EvaluateSignals(bool &longSignal, bool &shortSignal)
{
   longSignal  = false;
   shortSignal = false;

   if(!gVTurnSt.ready) return false;
   if(!VTurn_HasEnoughBars()) return false;

   // We evaluate on closed bar shift=1.
   // V-turn condition uses three points: i-3, i-2, i (on the same time axis).
   // Mapping with closed bars:
   //   i     -> shift=1
   //   i-2   -> shift=3
   //   i-3   -> shift=4
   double mom_i   = 0.0;  // mom at shift=1
   double mom_i2  = 0.0;  // mom at shift=3
   double mom_i3  = 0.0;  // mom at shift=4
   double bbmid_i = 0.0;  // bb mid at shift=1
   double c_i     = 0.0;  // close at shift=1

   // Momentum short is the core of V-turn
   if(!VTurn_MomentumAtShift(1, gVTurnCfg.mom_short_period, mom_i))  return false;
   if(!VTurn_MomentumAtShift(3, gVTurnCfg.mom_short_period, mom_i2)) return false;
   if(!VTurn_MomentumAtShift(4, gVTurnCfg.mom_short_period, mom_i3)) return false;

   // Bollinger mid + close
   if(!VTurn_BBMidAtShift(1, bbmid_i)) return false;
   c_i = iClose(_Symbol, _Period, 1);
   if(c_i == 0.0) return false;

   // V-turn: mom[i-3] > mom[i-2] and mom[i-2] < mom[i] and close[i] > bb_mid[i]
   bool vturn_up = (mom_i3 > mom_i2) && (mom_i2 < mom_i) && (c_i > bbmid_i);

   if(vturn_up && gVTurnCfg.allow_buy)
      longSignal = true;

   // If later you want shorts: define the mirrored condition here.
   if(gVTurnCfg.allow_sell)
   {
      // minimal conservative: disabled by default unless you explicitly implement
      shortSignal = false;
   }

   return true;
}

#endif // VTURN_MOM_VTURN_STRATEGY_MQH
