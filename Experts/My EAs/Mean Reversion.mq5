#property strict
#property description "Main EA: mean-reversion orchestration using Geometry/Regularization/Probability/Distribution modules"

#include <Trade/Trade.mqh>

#include <My Includes/Geometry.mqh>
#include <My Includes/Regularization.mqh>
#include <My Includes/Probability.mqh>
#include <My Includes/Distribution.mqh>

//----------------------------- Inputs --------------------------------//
input bool   UseZscoreVTurn           = true;
input double VTurnSlopeTolerance      = 1.0;
input bool   UsePriceVTurn            = false;
input int    LookbackPeriod           = 100;
input double R2Threshold              = 0.50;
input double MinSlope                 = 0.015;
input double MaxSlope                 = 0.03;
input double DegreesOfFreedom         = 5.0;
input double Alpha                    = 1.0;
input double EntryThreshold           = 1.5;
input double MinExtremenessScore      = 2.3;
input double ScalingFactor            = 1.5;
input double BaseLot                  = 5;
input double MaxMultiplier            = 3.0;

// ---- ATR EXITS ----
input int    ATRPeriod                = 14;
input double StopLossATRMultiplier    = 1.5; // Stop Loss Times ATR
input double TakeProfitATRMultiplier  = 2.0; // TP Times ATR

// ---- FIXED POINTS EXITS ----
input bool   UseFixedStops       = false;
input double FixedStopPoints     = 2250;
input double RiskRewardRatio     = 1.35;

// ---- Trade Management ----
input bool   UseBreakEven             = true;
input double BreakEvenTriggerPct      = 0.30;   // % distance to TP
input int    BreakEvenOffsetPoints    = 2;

input bool   UseTimeGuardrail         = true;
input int    MaxTradeMinutes          = 120;
input double TimeoutProgressThreshold = 0.20;   // Minimum TP progress required

input bool CloseBeforeDailyPause = false;
input int  DailyCloseBufferMinutes = 5;

//--------------------------- Global State ----------------------------//
CTrade               g_trade;
CLinearRegression    g_lr;
CStructureValidator  g_validator;
CResidualEngine      g_residual_engine;
CStudentTCalibration g_t_calibration;

double               g_prev_zscore = 0.0;
int                  g_atr_handle = INVALID_HANDLE;
datetime             g_last_bar_time = 0;

//-------------------------- Helper Methods ---------------------------//
bool IsNewBar()
  {
   const datetime current_bar_time = iTime(_Symbol,_Period,0);
   if(current_bar_time <= 0)
      return false;

   if(current_bar_time != g_last_bar_time)
     {
      g_last_bar_time = current_bar_time;
      return true;
     }

   return false;
  }

bool HasOpenPositionOnSymbol()
  {
   return PositionSelect(_Symbol);
  }

double NormalizeVolume(const double raw_lot)
  {
   const double vol_min  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double vol_max  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double vol_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(vol_step <= 0.0)
      return MathMax(vol_min,MathMin(vol_max,raw_lot));

   double lots = MathMax(vol_min,MathMin(vol_max,raw_lot));
   lots = MathFloor(lots / vol_step) * vol_step;
   lots = MathMax(vol_min,MathMin(vol_max,lots));
   return lots;
  }

double ComputeDynamicLot(const double proxy_abs)
  {
   const double sf = (ScalingFactor <= DBL_EPSILON ? 1.0 : ScalingFactor);
   const double multiplier = MathMin(proxy_abs / sf,MaxMultiplier);
   const double raw_lot = BaseLot * multiplier;
   return NormalizeVolume(raw_lot);
  }

bool ReadATR(const int shift,double &atr_value)
  {
   atr_value = 0.0;

   if(g_atr_handle == INVALID_HANDLE)
      return false;

   double atr_buffer[];
   ArraySetAsSeries(atr_buffer,true);

   // shift=1 uses the previous closed bar for deterministic values on new-bar execution.
   if(CopyBuffer(g_atr_handle,0,shift,1,atr_buffer) != 1)
      return false;

   atr_value = atr_buffer[0];
   return (atr_value > DBL_EPSILON);
  }

double ComputeTPProgress()
{
   if(!PositionSelect(_Symbol))
      return 0.0;

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double tp    = PositionGetDouble(POSITION_TP);
   double price = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ?
                  SymbolInfoDouble(_Symbol,SYMBOL_BID) :
                  SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   if(tp==0.0)
      return 0.0;

   if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
      return (price-entry)/(tp-entry);

   return (entry-price)/(entry-tp);
}

void ManageBreakEven()
{
   if(!UseBreakEven)
      return;

   if(!PositionSelect(_Symbol))
      return;

   double progress = ComputeTPProgress();

   if(progress < BreakEvenTriggerPct)
      return;

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);

   int type = PositionGetInteger(POSITION_TYPE);

   double offset = BreakEvenOffsetPoints * _Point;

   double new_sl;

   if(type==POSITION_TYPE_BUY)
      new_sl = entry + offset;
   else
      new_sl = entry - offset;

   if(type==POSITION_TYPE_BUY && sl != 0.0 && sl >= new_sl)
      return;
   
   if(type==POSITION_TYPE_SELL && sl != 0.0 && sl <= new_sl)
      return;

   g_trade.PositionModify(_Symbol,new_sl,PositionGetDouble(POSITION_TP));
}

void ManageTimeGuardrail()
{
   if(!UseTimeGuardrail)
      return;

   if(!PositionSelect(_Symbol))
      return;

   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

   int minutes_open = (int)((TimeCurrent()-open_time)/60);

   if(minutes_open < MaxTradeMinutes)
      return;

   double progress = ComputeTPProgress();

   double profit = PositionGetDouble(POSITION_PROFIT);

   if(profit < 0 || progress < TimeoutProgressThreshold)
   {
      g_trade.PositionClose(_Symbol);
   }
}

void ManageDailySessionClose()
{
   if(!CloseBeforeDailyPause)
      return;

   if(!PositionSelect(_Symbol))
      return;

   datetime now = TimeCurrent();

   // Convert to New York time
   datetime ny_time = now - (TimeGMT() - TimeTradeServer());

   MqlDateTime t;
   TimeToStruct(ny_time,t);

   int minutes_now = t.hour * 60 + t.min;

   int session_close = 17 * 60; // 17:00 NY

   if(minutes_now >= session_close - DailyCloseBufferMinutes)
   {
      g_trade.PositionClose(_Symbol);
   }
}

void ExecuteSignal(const double proxy,const double atr_value)
  {
   if(HasOpenPositionOnSymbol())
      return;

   const double abs_proxy = MathAbs(proxy);
   if(abs_proxy < EntryThreshold)
      return;

   const double lot = ComputeDynamicLot(abs_proxy);
   if(lot <= 0.0)
      return;

   const double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double sl_dist;
   double tp_dist;
   
   if(UseFixedStops)
   {
      sl_dist = FixedStopPoints * _Point;
      tp_dist = sl_dist * RiskRewardRatio;
   }
   else
   {
      sl_dist = atr_value * StopLossATRMultiplier;
      tp_dist = atr_value * TakeProfitATRMultiplier;
   }

   // Mean-reversion direction:
   // proxy > 0 => price above center => SHORT
   // proxy < 0 => price below center => LONG
   if(proxy > EntryThreshold)
   {
      const double entry = bid;
      const double sl = entry + sl_dist;
      const double tp = entry - tp_dist;
      g_trade.Sell(lot,_Symbol,0.0,sl,tp,"MeanRev SHORT");
   }
   else if(proxy < -EntryThreshold)
   {
      const double entry = ask;
      const double sl = entry - sl_dist;
      const double tp = entry + tp_dist;
      g_trade.Buy(lot,_Symbol,0.0,sl,tp,"MeanRev LONG");
   }
}
//----------------------------- EA Events -----------------------------//
int OnInit()
  {
   if(LookbackPeriod < 3)
      return(INIT_PARAMETERS_INCORRECT);
   if(ATRPeriod < 1)
      return(INIT_PARAMETERS_INCORRECT);
   if(EntryThreshold <= 0.0 || BaseLot <= 0.0)
      return(INIT_PARAMETERS_INCORRECT);

   g_validator.SetThreshold(R2Threshold);
   g_validator.SetMinSlope(MinSlope);
   g_validator.SetMaxSlope(MaxSlope);
   // Normalized slope in %/bar for cross-asset consistency.
   g_validator.SetSlopeMode(SLOPE_PERCENT_PER_BAR);

   g_t_calibration.SetDegreesOfFreedom(DegreesOfFreedom);

   g_atr_handle = iATR(_Symbol,_Period,ATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
      return(INIT_FAILED);

   // Initialize new-bar anchor.
   g_last_bar_time = 0;

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
  }

void OnTick()
{
   // --- Manage existing positions every tick ---
   ManageBreakEven();
   ManageTimeGuardrail();
   ManageDailySessionClose();

   // Execute pipeline strictly once per new bar.
   if(!IsNewBar())
      return;

   double close_prices[];
   ArraySetAsSeries(close_prices,true);

   if(CopyClose(_Symbol,_Period,0,LookbackPeriod,close_prices) != LookbackPeriod)
      return;

   // 1) Geometry.
   if(!g_lr.Calculate(close_prices,LookbackPeriod))
      return;

   // 2) Structure filter.
   const bool structure_ok = g_validator.Evaluate(g_lr);
   if(!structure_ok)
      return;

   // 3) Residual engine.
   if(!g_residual_engine.Calculate(g_lr))
      return;

   const double zscore = g_residual_engine.GetZScore();

   bool vturn_ok = true;

   if(UseZscoreVTurn)
   {
      if(g_prev_zscore != 0.0)
      {
         double dz = zscore - g_prev_zscore;
   
         if(zscore > 0)
            vturn_ok = (dz <= VTurnSlopeTolerance);
   
         if(zscore < 0)
            vturn_ok = (dz >= -VTurnSlopeTolerance);
      }
   }
   
   if(UsePriceVTurn)
   {
      double close1 = iClose(_Symbol,_Period,1);
      double close2 = iClose(_Symbol,_Period,2);
      double open1  = iOpen(_Symbol,_Period,1);
      
      bool price_vturn_long  = (close1 > close2 && close1 > open1);
      bool price_vturn_short = (close1 < close2 && close1 < open1);
   
   
      if(zscore < 0)
         vturn_ok = vturn_ok && price_vturn_long;
   
      if(zscore > 0)
         vturn_ok = vturn_ok && price_vturn_short;
   }

   // 4) Fat-tail calibration.
   g_t_calibration.Calculate(zscore);

   // 5) Proxy and trading conditions.
   const double proxy = zscore * Alpha;
   const double extremeness = g_t_calibration.GetExtremenessScore();

   if(MathAbs(proxy) < EntryThreshold)
      return;
   
   if((UseZscoreVTurn || UsePriceVTurn) && !vturn_ok)
   return;

   if(extremeness < MinExtremenessScore)
      return;

   // 6) Read ATR and execute directional mean-reversion signal.
   double atr_value = 0.0;
   if(!ReadATR(1,atr_value))
      return;

   ExecuteSignal(proxy,atr_value);

   Comment(
      "MainEA Mean-Reversion\n",
      "R^2: ", DoubleToString(g_validator.GetRSquared(),6), "\n",
      "Z-score: ", DoubleToString(zscore,6), "\n",
      "Proxy: ", DoubleToString(proxy,6), "\n",
      "Extremeness: ", DoubleToString(extremeness,6)
   );
   
   g_prev_zscore = zscore;
  }
