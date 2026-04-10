//+------------------------------------------------------------------+
#property strict

#include <Alerts System/telegram_api.mqh>

//---------------- INPUTS ----------------//

input string TELEGRAM_BOT_TOKEN = "1750377600:AAExrEl_E6wckGfwHGy-bobtjJWMOuz_A_I";
input string TELEGRAM_CHAT_ID   = "1723491813";

input double sigma = 2.0;
input double minSlopeATR = 0.35;

input double uTopATR = 3.0;
input double uBottomATR = 2.0;

input double lTopATR = -2.0;
input double lBottomATR = -3.0;

input double bufPct = 0.1;
input double zoneDistFromBand = 0.20;

//---------------- IMPULSE REGIME INPUTS ----------------//
input int    impulseLookbackL   = 12;
input int    impulseWindowN     = 80;
input double impulseMlow        = 0.30;
input double impulseMhigh       = 0.80;
input double impulseDhigh       = 0.60;

//---------------- SYMBOLS ----------------//
input string Symbols = "US500.cash,US100.cash,EURUSD,BTCUSD,ETHUSD,XAUUSD,USOIL.cash";
string symbolList[];

//---------------- GLOBAL ----------------//

string keys[];
datetime lastBarTimes[];

string alertKeys[];
datetime alertTimes[];

string reversalAlertKeys[];
datetime reversalAlertTimes[];

// Impulse regime internal state (per symbol+tf)
string impulseKeys[];
double impulseRimpState[];
double impulseMState[];
int    impulseDState[];
double impulseMPctState[];
double impulseDPctState[];
int    impulseRegimeState[];
int    impulseLastSignalSign[];

//---------------- TYPES ----------------//
enum ImpulseRegime
{
   REGIME_NO_EDGE = 0,
   REGIME_TREND_DOMINANT = 1,
   REGIME_REVERSAL = 2
};

struct ImpulseRegimeSnapshot
{
   double rImp;
   double magnitude;
   int duration;
   double magnitudePct;
   double durationPct;
   ImpulseRegime regime;
   int signalSign;
   bool trigger;
   string direction;
};

//---------------- HELPERS ----------------//

bool NewBar(string symbol, ENUM_TIMEFRAMES tf)
{
   datetime t[1];
   if(CopyTime(symbol, tf, 0, 1, t) <= 0)
      return false;

   string key = symbol + "_" + EnumToString(tf);

   int size = ArraySize(keys);

   for(int i=0; i<size; i++)
   {
      if(keys[i] == key)
      {
         if(lastBarTimes[i] == t[0])
            return false;

         lastBarTimes[i] = t[0];
         return true;
      }
   }

   // nuevo registro
   ArrayResize(keys, size+1);
   ArrayResize(lastBarTimes, size+1);

   keys[size] = key;
   lastBarTimes[size] = t[0];

   return true;
}

bool CanSendAlert(string symbol, ENUM_TIMEFRAMES tf)
{
   datetime t[1];
   if(CopyTime(symbol, tf, 1, 1, t) <= 0)
      return false;

   string key = symbol + "_" + EnumToString(tf);

   int size = ArraySize(alertKeys);

   for(int i=0; i<size; i++)
   {
      if(alertKeys[i] == key)
      {
         if(alertTimes[i] == t[0])
            return false;

         alertTimes[i] = t[0];
         return true;
      }
   }

   ArrayResize(alertKeys, size+1);
   ArrayResize(alertTimes, size+1);

   alertKeys[size] = key;
   alertTimes[size] = t[0];

   return true;
}

bool CanSendReversalAlert(string symbol, ENUM_TIMEFRAMES tf)
{
   datetime t[1];
   if(CopyTime(symbol, tf, 1, 1, t) <= 0)
      return false;

   string key = symbol + "_" + EnumToString(tf) + "_REV";
   int size = ArraySize(reversalAlertKeys);

   for(int i=0; i<size; i++)
   {
      if(reversalAlertKeys[i] == key)
      {
         if(reversalAlertTimes[i] == t[0])
            return false;

         reversalAlertTimes[i] = t[0];
         return true;
      }
   }

   ArrayResize(reversalAlertKeys, size+1);
   ArrayResize(reversalAlertTimes, size+1);
   reversalAlertKeys[size] = key;
   reversalAlertTimes[size] = t[0];
   return true;
}

string TimeframeLabel(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M5)
      return "M5";
   if(tf == PERIOD_M15)
      return "M15";
   if(tf == PERIOD_H1)
      return "H1";
   return EnumToString(tf);
}

string GetRegimeLabel(ImpulseRegime regime)
{
   if(regime == REGIME_NO_EDGE)
      return "No Edge";
   if(regime == REGIME_TREND_DOMINANT)
      return "Trend";
   return "Reversal";
}

int SignOf(double value)
{
   if(value > 0.0)
      return 1;
   if(value < 0.0)
      return -1;
   return 0;
}

double PercentileRank(const double &arr[], double value)
{
   int n = ArraySize(arr);
   if(n <= 0)
      return 0.0;

   int countLE = 0;
   for(int i = 0; i < n; i++)
   {
      if(arr[i] <= value)
         countLE++;
   }

   return (double)countLE / (double)n;
}

int FindOrCreateImpulseStateIndex(string symbol, ENUM_TIMEFRAMES tf)
{
   string key = symbol + "_" + EnumToString(tf);
   int size = ArraySize(impulseKeys);

   for(int i = 0; i < size; i++)
   {
      if(impulseKeys[i] == key)
         return i;
   }

   int idx = size;
   ArrayResize(impulseKeys, idx + 1);
   ArrayResize(impulseRimpState, idx + 1);
   ArrayResize(impulseMState, idx + 1);
   ArrayResize(impulseDState, idx + 1);
   ArrayResize(impulseMPctState, idx + 1);
   ArrayResize(impulseDPctState, idx + 1);
   ArrayResize(impulseRegimeState, idx + 1);
   ArrayResize(impulseLastSignalSign, idx + 1);

   impulseKeys[idx] = key;
   impulseRimpState[idx] = 0.0;
   impulseMState[idx] = 0.0;
   impulseDState[idx] = 1;
   impulseMPctState[idx] = 0.0;
   impulseDPctState[idx] = 0.0;
   impulseRegimeState[idx] = REGIME_NO_EDGE;
   impulseLastSignalSign[idx] = 0;

   return idx;
}

void LogReversalSignalToCSV(
   string symbol,
   ENUM_TIMEFRAMES tf,
   datetime time,
   string direction,
   double mPct,
   double dPct,
   double price
)
{
   string filename = "reversal_signals.csv";
   
   int file = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_WRITE|FILE_SHARE_READ);

   if(file == INVALID_HANDLE)
   {
      Print("ERROR opening CSV file: ", GetLastError());
      return;
   }

   // Si el archivo está vacío, escribir header
   if(FileSize(file) == 0)
   {
      FileWrite(file, "time","symbol","tf","direction","M_pct","D_pct","price");
   }

   FileSeek(file, 0, SEEK_END);

   FileWrite(
      file,
      TimeToString(time, TIME_DATE|TIME_SECONDS),
      symbol,
      TimeframeLabel(tf),
      direction,
      DoubleToString(mPct, 4),
      DoubleToString(dPct, 4),
      DoubleToString(price, _Digits)
   );

   FileClose(file);
}

bool CalculateImpulseRegime(string symbol, ENUM_TIMEFRAMES tf, int shift, ImpulseRegimeSnapshot &snap)
{
   snap.rImp = 0.0;
   snap.magnitude = 0.0;
   snap.duration = 1;
   snap.magnitudePct = 0.0;
   snap.durationPct = 0.0;
   snap.regime = REGIME_NO_EDGE;
   snap.signalSign = 0;
   snap.trigger = false;
   snap.direction = "";

   if(impulseLookbackL <= 0 || impulseWindowN < 5)
      return false;

   int barsNeeded = shift + impulseWindowN + impulseLookbackL + 2;
   if(Bars(symbol, tf) < barsNeeded)
      return false;

   int countNeeded = shift + impulseWindowN + impulseLookbackL;
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(symbol, tf, 0, countNeeded, closeBuf) <= 0)
      return false;

   double mVals[];
   double dVals[];
   ArrayResize(mVals, impulseWindowN);
   ArrayResize(dVals, impulseWindowN);

   int prevSign = 0;
   int prevD = 1;

   for(int idx = impulseWindowN - 1; idx >= 0; idx--)
   {
      int barShift = shift + idx;
      double past = closeBuf[barShift + impulseLookbackL];
      if(past == 0.0)
         return false;

      double now = closeBuf[barShift];
      double rImp = (now - past) / past;
      int sign = SignOf(rImp);
      int effectiveSign = sign;
      if(sign == 0 && idx != impulseWindowN - 1)
         effectiveSign = prevSign;

      mVals[idx] = MathAbs(rImp);

      int d = 1;
      if(idx != impulseWindowN - 1 && effectiveSign == prevSign)
         d = prevD + 1;

      dVals[idx] = (double)d;

      prevSign = effectiveSign;
      prevD = d;

      if(idx == 0)
      {
         snap.rImp = rImp;
         snap.magnitude = mVals[idx];
         snap.duration = d;
         snap.signalSign = effectiveSign;
      }
   }

   snap.magnitudePct = PercentileRank(mVals, snap.magnitude);
   snap.durationPct = PercentileRank(dVals, (double)snap.duration);

   bool isNoEdge = (snap.magnitudePct < impulseMlow);
   bool isTrendDominant = (snap.magnitudePct >= impulseMhigh && snap.durationPct < impulseDhigh);
   bool isReversal =
      (snap.magnitudePct > impulseMlow &&
       (snap.magnitudePct < impulseMhigh ||
       (snap.magnitudePct >= impulseMhigh && snap.durationPct >= impulseDhigh)));

   if(isNoEdge)
      snap.regime = REGIME_NO_EDGE;
   else if(isTrendDominant)
      snap.regime = REGIME_TREND_DOMINANT;
   else if(isReversal)
      snap.regime = REGIME_REVERSAL;
   else
      snap.regime = REGIME_NO_EDGE;

   if(snap.signalSign > 0)
      snap.direction = "SHORT";
   else if(snap.signalSign < 0)
      snap.direction = "LONG";

   int stateIdx = FindOrCreateImpulseStateIndex(symbol, tf);
   int prevRegime = impulseRegimeState[stateIdx];
   int prevSignalSign = impulseLastSignalSign[stateIdx];

   bool isNewReversal = (prevRegime != REGIME_REVERSAL && snap.regime == REGIME_REVERSAL);
   bool isDirectionFlip =
      (prevRegime == REGIME_REVERSAL &&
       snap.regime == REGIME_REVERSAL &&
       prevSignalSign != snap.signalSign);

   snap.trigger = (isNewReversal || isDirectionFlip) && (snap.signalSign != 0);

   impulseRimpState[stateIdx] = snap.rImp;
   impulseMState[stateIdx] = snap.magnitude;
   impulseDState[stateIdx] = snap.duration;
   impulseMPctState[stateIdx] = snap.magnitudePct;
   impulseDPctState[stateIdx] = snap.durationPct;
   impulseRegimeState[stateIdx] = (int)snap.regime;
   impulseLastSignalSign[stateIdx] = snap.signalSign;

   return true;
}

//---------------- CORE ----------------//

void CheckSignal(string symbol, ENUM_TIMEFRAMES tf)
{
   if(!SymbolSelect(symbol, true))
      return;

   if(!SymbolIsSynchronized(symbol))
      return;

   if(Bars(symbol, tf) < 50)
      return;

   int maHandle  = iMA(symbol,tf,20,0,MODE_SMA,PRICE_CLOSE);
   int stdHandle = iStdDev(symbol,tf,20,0,MODE_SMA,PRICE_CLOSE);
   int atrHandle = iATR(symbol,tf,14);
   int ma5Handle = iMA(symbol,tf,5,0,MODE_SMA,PRICE_CLOSE);

   if(maHandle==INVALID_HANDLE || stdHandle==INVALID_HANDLE ||
      atrHandle==INVALID_HANDLE || ma5Handle==INVALID_HANDLE)
      return;

   int shift=1; // vela cerrada

   double close = iClose(symbol,tf, shift);
   double open  = iOpen(symbol,tf, shift);
   double high  = iHigh(symbol,tf, shift);
   double low   = iLow(symbol,tf, shift);

   //----------------------------------
   // BB
   //----------------------------------

   double maBuf[], stdBuf[], atrBuf[];

   if(CopyBuffer(maHandle,0,shift,1,maBuf)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }
   if(CopyBuffer(stdHandle,0,shift,1,stdBuf)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }
   if(CopyBuffer(atrHandle,0,shift,1,atrBuf)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }

   double basis = maBuf[0];
   double stdev = stdBuf[0];
   double atr   = atrBuf[0];

   double dev = sigma * stdev;

   double upper = basis + dev;
   double lower = basis - dev;

   //----------------------------------
   // ATR + SLOPE
   //----------------------------------

   if(CopyBuffer(maHandle,0,shift+3,1,maBuf)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }
   double basis_3 = maBuf[0];

   if(atr==0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }

   double slope = (basis - basis_3) / atr;

   bool trendValid = MathAbs(slope) > minSlopeATR;

   //----------------------------------
   // VECTOR CANDLE
   //----------------------------------

   double body = MathAbs(close-open);
   double range = high-low;

   double bodyPct = (range!=0)? body/range : 0;

   bool rangeExpansion = range > atr*1.5;

   bool dominantClose =
      (close > high - range*0.2) ||
      (close < low  + range*0.2);

   bool isVector = bodyPct>0.7 && rangeExpansion && dominantClose;

   bool vectorBull = isVector && close>open;
   bool vectorBear = isVector && close<open;

   //--- PREV VECTOR (shift+1)
   double prevOpen  = iOpen(symbol,tf,shift+1);
   double prevClose2 = iClose(symbol,tf,shift+1);
   double prevHigh  = iHigh(symbol,tf,shift+1);
   double prevLow   = iLow(symbol,tf,shift+1);

   double prevBody = MathAbs(prevClose2-prevOpen);
   double prevRange = prevHigh-prevLow;

   double prevBodyPct = (prevRange!=0)? prevBody/prevRange : 0;

   bool prevRangeExpansion = prevRange > atr*1.5;

   bool prevDominantClose =
      (prevClose2 > prevHigh - prevRange*0.2) ||
      (prevClose2 < prevLow  + prevRange*0.2);

   bool prevVector =
      prevBodyPct>0.7 && prevRangeExpansion && prevDominantClose;

   bool prevVectorBull = prevVector && prevClose2>prevOpen;
   bool prevVectorBear = prevVector && prevClose2<prevOpen;

   //--- ONCE
   bool vcBullOnce = vectorBull && !prevVectorBull;
   bool vcBearOnce = vectorBear && !prevVectorBear;

   //----------------------------------
   // ATR AOI
   //----------------------------------

   double ma5Buf[];
   if(CopyBuffer(ma5Handle,0,shift,1,ma5Buf)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }

   double atrAnchor = ma5Buf[0];

   double uTopAbs    = atrAnchor + atr*uTopATR;
   double uBottomAbs = atrAnchor + atr*uBottomATR;

   double uHi = MathMax(uTopAbs,uBottomAbs);
   double uLo = MathMin(uTopAbs,uBottomAbs);

   double lTopAbs    = atrAnchor + atr*lTopATR;
   double lBottomAbs = atrAnchor + atr*lBottomATR;

   double lHi = MathMax(lTopAbs,lBottomAbs);
   double lLo = MathMin(lTopAbs,lBottomAbs);

   //----------------------------------
   // BB ZONES
   //----------------------------------

   double totalBuyRange  = basis - lower;
   double totalSellRange = upper - basis;

   double buyLevel  = lower + totalBuyRange * zoneDistFromBand;
   double sellLevel = upper - totalSellRange * zoneDistFromBand;

   bool bbBuy  = close <= buyLevel;
   bool bbSell = close >= sellLevel;

   //----------------------------------
   // ATR ZONES
   //----------------------------------

   bool atrBuy  = close>=lLo && close<=lHi;
   bool atrSell = close>=uLo && close<=uHi;

   //----------------------------------
   // PRIOR BAR (para "once")
   //----------------------------------

   double prevClose = iClose(symbol,tf,shift+1);

   // recalcular niveles en shift+1

   double maBufPrev[], stdBufPrev[], atrBufPrev[], ma5BufPrev[];

   if(CopyBuffer(maHandle,0,shift+1,1,maBufPrev)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }
   if(CopyBuffer(stdHandle,0,shift+1,1,stdBufPrev)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }
   if(CopyBuffer(atrHandle,0,shift+1,1,atrBufPrev)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }
   if(CopyBuffer(ma5Handle,0,shift+1,1,ma5BufPrev)<=0)
   {
      IndicatorRelease(maHandle);
      IndicatorRelease(stdHandle);
      IndicatorRelease(atrHandle);
      IndicatorRelease(ma5Handle);
      return;
   }

   double basisPrev = maBufPrev[0];
   double stdevPrev = stdBufPrev[0];
   double atrPrev2  = atrBufPrev[0];
   double atrAnchorPrev = ma5BufPrev[0];

   double upperPrev = basisPrev + sigma*stdevPrev;
   double lowerPrev = basisPrev - sigma*stdevPrev;

   // zonas BB prev
   double totalBuyPrev  = basisPrev - lowerPrev;
   double totalSellPrev = upperPrev - basisPrev;

   double buyLevelPrev  = lowerPrev + totalBuyPrev * zoneDistFromBand;
   double sellLevelPrev = upperPrev - totalSellPrev * zoneDistFromBand;

   // zonas ATR prev
   double uTopPrev = atrAnchorPrev + atrPrev2*uTopATR;
   double uBotPrev = atrAnchorPrev + atrPrev2*uBottomATR;

   double uHiPrev = MathMax(uTopPrev,uBotPrev);
   double uLoPrev = MathMin(uTopPrev,uBotPrev);

   double lTopPrev = atrAnchorPrev + atrPrev2*lTopATR;
   double lBotPrev = atrAnchorPrev + atrPrev2*lBottomATR;

   double lHiPrev = MathMax(lTopPrev,lBotPrev);
   double lLoPrev = MathMin(lTopPrev,lBotPrev);

   // condiciones prev reales
   bool bbBuyPrev  = prevClose <= buyLevelPrev;
   bool bbSellPrev = prevClose >= sellLevelPrev;

   bool atrBuyPrev  = prevClose>=lLoPrev && prevClose<=lHiPrev;
   bool atrSellPrev = prevClose>=uLoPrev && prevClose<=uHiPrev;

   //----------------------------------
   // ONCE LOGIC
   //----------------------------------

   bool bbBuyOnce  = bbBuy  && !bbBuyPrev;
   bool bbSellOnce = bbSell && !bbSellPrev;

   bool atrBuyOnce  = atrBuy  && !atrBuyPrev;
   bool atrSellOnce = atrSell && !atrSellPrev;

   //----------------------------------
   // APPLY FILTER
   //----------------------------------

   bbBuyOnce  = bbBuyOnce  && trendValid;
   bbSellOnce = bbSellOnce && trendValid;
   atrBuyOnce  = atrBuyOnce  && trendValid;
   atrSellOnce = atrSellOnce && trendValid;

   //----------------------------------
   // INTERNAL / EXTERNAL
   //----------------------------------

   bool bbInsideBuy  = (lower>=lLo && lower<=lHi);
   bool bbInsideSell = (upper>=uLo && upper<=uHi);

   //----------------------------------
   // IMPULSE REGIME
   //----------------------------------

   ImpulseRegimeSnapshot impulseSnap;
   bool impulseOk = CalculateImpulseRegime(symbol, tf, shift, impulseSnap);

   //----------------------------------
   // BUS
   //----------------------------------

   string msg="";

   if(vcBullOnce)
      msg="Bull Vector Candle STATES SYSTEM";

   else if(vcBearOnce)
      msg="Bear Vector Candle";

   else if(atrBuyOnce)
      msg="ATR-Buy STATES SYSTEM | " + (bbInsideBuy?"Internal":"External");

   else if(atrSellOnce)
      msg="ATR-Sell STATES SYSTEM | " + (bbInsideSell?"Internal":"External");

   else if(bbBuyOnce)
      msg="2s-Buy STATES SYSTEM | " + (bbInsideBuy?"Internal":"External");

   else if(bbSellOnce)
      msg="2s-Sell STATES SYSTEM | " + (bbInsideSell?"Internal":"External");

   if(msg != "")
   {
      string regimeLabel = "No Edge STATES SYSTEM";
      if(impulseOk)
         regimeLabel = GetRegimeLabel(impulseSnap.regime);
      msg = msg + " | State STATES SYSTEM=" + regimeLabel;
   }

   //----------------------------------
   // SEND TELEGRAM (existing signal bus)
   //----------------------------------

   if(msg!="" && CanSendAlert(symbol, tf))
   {
      string text = symbol+" "+EnumToString(tf)+"\n"+msg+
              "\nPrice: "+DoubleToString(close,_Digits);

      SendTelegramMessage(text);

      Print("ALERT: ",text);
   }

   //----------------------------------
   // REVERSAL ALERT (independent)
   //----------------------------------
   if(impulseOk && impulseSnap.trigger && CanSendReversalAlert(symbol, tf))
      {
         string revText = "REVERSAL SIGNAL STATES SYSTEM | " + symbol + " " + TimeframeLabel(tf) + " | " + impulseSnap.direction +
                          " | M=" + DoubleToString(impulseSnap.magnitudePct,2) +
                          " | D=" + DoubleToString(impulseSnap.durationPct,2) +
                          " | State=" + GetRegimeLabel(impulseSnap.regime);
   
         SendTelegramMessage(revText);
         Print("ALERT: ",revText);
      }
      
      LogReversalSignalToCSV(
      symbol,
      tf,
      TimeCurrent(),
      impulseSnap.direction,
      impulseSnap.magnitudePct,
      impulseSnap.durationPct,
      close
   );

   IndicatorRelease(maHandle);
   IndicatorRelease(stdHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(ma5Handle);
}

//---------------- EVENTS ----------------//

int OnInit()
{
   StringSplit(Symbols, ',', symbolList);

   for(int i=0; i<ArraySize(symbolList); i++)
   {
      string symbol = symbolList[i];

      StringTrimLeft(symbol);
      StringTrimRight(symbol);

      symbolList[i] = symbol;

      Print("SYMBOL CHECK: [", symbol, "]");

      if(!SymbolSelect(symbol, true))
      {
         Print("ERROR SymbolSelect failed: ", symbol,
               " | err=", GetLastError());
      }
      else
      {
         Print("SYMBOL OK: ", symbol);
      }
   }

   EventSetTimer(10);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}


void OnTimer()
{
   int total = ArraySize(symbolList);

   for(int i=0; i<total; i++)
   {
      string symbol = symbolList[i];

      if(NewBar(symbol, PERIOD_M5))
         CheckSignal(symbol, PERIOD_M5);

      if(NewBar(symbol, PERIOD_M15))
         CheckSignal(symbol, PERIOD_M15);

      if(NewBar(symbol, PERIOD_H1))
         CheckSignal(symbol, PERIOD_H1);
   }
}
//+------------------------------------------------------------------+
