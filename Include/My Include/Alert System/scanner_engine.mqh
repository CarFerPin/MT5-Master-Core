#ifndef SCANNER_ENGINE_MQH
#define SCANNER_ENGINE_MQH

#include "detector_basics.mqh"
#include "detector_structure.mqh"

namespace ScannerEngine
{

//==============================================================
// SIGNAL STRUCT
//==============================================================

struct MarketSignal
{
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   string type;
   int direction;
   double price;
   datetime time;
   double score;
};

//==============================================================
// SCANNER CONFIG
//==============================================================

static const string MONITORED_SYMBOLS[] =
{
   "US500.cash",
   "US100.cash",
   "XAUUSD",
   "EURUSD",
   "BTCUSD",
   "ETHUSD",
   "USOIL.cash",
   "COFFEE.c",
   "XAGUSD",
   "DXY.cash"
};

static const ENUM_TIMEFRAMES MONITORED_TIMEFRAMES[] =
{
   PERIOD_M5,
   PERIOD_M15,
   PERIOD_H1
};

static datetime last_signal_bar[20][5];


//==============================================================
// ATR HANDLE CACHE
//==============================================================

struct AtrHandleSlot
{
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   int handle;
   bool initialized;
};

static AtrHandleSlot g_atr_slots[30];

//--------------------------------------------------------------

int GetAtrHandle(const string symbol,const ENUM_TIMEFRAMES timeframe)
{
   for(int i=0;i<30;i++)
   {
      if(g_atr_slots[i].initialized &&
         g_atr_slots[i].symbol == symbol &&
         g_atr_slots[i].timeframe == timeframe)
      {
         return g_atr_slots[i].handle;
      }
   }

   for(int j=0;j<30;j++)
   {
      if(!g_atr_slots[j].initialized)
      {
         g_atr_slots[j].symbol = symbol;
         g_atr_slots[j].timeframe = timeframe;
         g_atr_slots[j].handle = iATR(symbol,timeframe,14);
         g_atr_slots[j].initialized = true;
         return g_atr_slots[j].handle;
      }
   }

   return INVALID_HANDLE;
}

//--------------------------------------------------------------

void ReleaseScannerHandles()
{
   for(int i=0;i<30;i++)
   {
      if(g_atr_slots[i].initialized)
      {
         if(g_atr_slots[i].handle != INVALID_HANDLE)
            IndicatorRelease(g_atr_slots[i].handle);

         g_atr_slots[i].handle = INVALID_HANDLE;
         g_atr_slots[i].initialized = false;
         g_atr_slots[i].symbol = "";
         g_atr_slots[i].timeframe = PERIOD_CURRENT;
      }
   }
}

//==============================================================
// SIGNAL BUILDER
//==============================================================

bool FillSignal(const string symbol,
                const ENUM_TIMEFRAMES timeframe,
                const string type,
                const int direction,
                const MqlRates &rates[],
                MarketSignal &signal)
{
   if(direction != 1 && direction != -1)
      return false;

   signal.symbol = symbol;
   signal.timeframe = timeframe;
   signal.type = type;
   signal.direction = direction;
   signal.price = rates[1].close;
   signal.time = rates[1].time;

   return true;
}

//==============================================================
// SCORING FUCTION
//==============================================================

double ComputeBaseScore(const string signal_type)
{
   double score = 0;

   if(StringFind(signal_type,"LIQUIDITY_SWEEP")>=0) score += 42;
   else if(StringFind(signal_type,"MSS")>=0) score += 40;
   else if(StringFind(signal_type,"BREAKOUT")>=0) score += 36;
   else if(StringFind(signal_type,"VECTOR_CANDLE")>=0) score += 32;
   else if(StringFind(signal_type,"FVG_HQ")>=0) score += 30;
   else if(StringFind(signal_type,"FVG")>=0) score += 24;

   if(StringFind(signal_type,"RANGE_EXP")>=0) score += 22;
   if(StringFind(signal_type,"BB_EXP")>=0) score += 20;
   if(StringFind(signal_type,"ATR_REGIME_EXP")>=0) score += 20;
   if(StringFind(signal_type,"VOL_SPIKE")>=0) score += 18;

   return score;
}

double ApplyMTFMultiplier(double score,int tf_count)
{
   double multiplier=1.0;

   if(tf_count==2)
      multiplier=1.30;

   if(tf_count>=3)
      multiplier=1.65;

   score*=multiplier;

   if(score>100)
      score=100;

   return score;
}
//==============================================================
// MAIN SCANNER
//==============================================================

bool ScanSymbolTimeframe(string symbol,
                         ENUM_TIMEFRAMES timeframe,
                         MarketSignal &signal)
{
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   
   if(CopyRates(symbol,timeframe,0,60,rates) < 60)
      return false;
   
   datetime current_bar = rates[1].time;

   //=========================================================
   // CORE STRUCTURE EVENTS
   //=========================================================

   int sweep    = DetectorsStructure::DetectLiquiditySweep(rates);
   int mss      = DetectorsStructure::DetectMSS(rates);
   int breakout = DetectorsStructure::DetectBreakout(rates);
   int vector_signal = DetectorsBasic::DetectVectorCandle(rates);
   int fvg      = DetectorsStructure::DetectFVG(rates,true);

   int direction = 0;
   string type = "";

   if(sweep != 0)
   {
      type = "LIQUIDITY_SWEEP";
      direction = sweep;
   }
   else if(mss != 0)
   {
      type = "MSS";
      direction = mss;
   }
   else if(breakout != 0)
   {
      type = "BREAKOUT";
      direction = breakout;
   }
   else if(vector_signal != 0)
   {
      type = "VECTOR_CANDLE";
      direction = vector_signal;
   }
   else if(fvg != 0)
   {
      direction = fvg;
      type = "FVG";
   }

   if(direction == 0)
      return false;

   //=========================================================
   // CONFIRMATIONS
   //=========================================================

   bool volume_spike = DetectorsBasic::DetectActivityConfirmationVolumeSpike(rates);
   bool bb_expansion = DetectorsBasic::DetectBollingerVolatilityExpansion(rates);

   int atr_handle = GetAtrHandle(symbol,timeframe);

   bool range_expansion = false;
   bool atr_regime_expansion = false;

   if(atr_handle != INVALID_HANDLE)
   {
      double atr[6];

      if(CopyBuffer(atr_handle,0,1,6,atr) >= 6)
      {
         range_expansion =
            DetectorsBasic::DetectRangeExpansion(rates,atr[0]);

         atr_regime_expansion =
            DetectorsBasic::DetectATRVolatilityRegimeExpansion(
               atr[0],atr[5]);
      }
   }

   //=========================================================
   // QUALITY TAGS
   //=========================================================

   if(fvg != 0 && volume_spike)
      type = "FVG_HQ";

   if(range_expansion)
      type += "|RANGE_EXP";

   if(bb_expansion)
      type += "|BB_EXP";

   if(atr_regime_expansion)
      type += "|ATR_REGIME_EXP";

   if(volume_spike && fvg == 0)
      type += "|VOL_SPIKE";

   double base_score = ComputeBaseScore(type);
   double final_score = ApplyMTFMultiplier(base_score,1);
   
   int s_index = -1;
   int tf_index = -1;
   
   for(int i=0;i<ArraySize(MONITORED_SYMBOLS);i++)
   {
      if(MONITORED_SYMBOLS[i]==symbol)
      {
         s_index=i;
         break;
      }
   }
   
   for(int i=0;i<ArraySize(MONITORED_TIMEFRAMES);i++)
   {
      if(MONITORED_TIMEFRAMES[i]==timeframe)
      {
         tf_index=i;
         break;
      }
   }
   
   if(s_index < 0 || tf_index < 0)
      return false;
   
   if(last_signal_bar[s_index][tf_index] == current_bar)
      return false;
   
   bool ok = FillSignal(symbol,timeframe,type,direction,rates,signal);
   
   if(ok)
   {
      signal.score = final_score;
      last_signal_bar[s_index][tf_index] = current_bar;
   }

return ok;
}
}
#endif