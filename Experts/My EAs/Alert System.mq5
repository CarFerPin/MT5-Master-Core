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
   
   //---------------- SYMBOLS ----------------//
   input string Symbols = "US500.cash,US100.cash,EURUSD,BTCUSD,ETHUSD,XAUUSD,USOIL.cash";
   string symbolList[];
   
   //---------------- GLOBAL ----------------//
   
   string keys[];
   datetime lastBarTimes[];
   
   string alertKeys[];
   datetime alertTimes[];

//   datetime lastHeartbeat = 0;  // HEARTBEAT ELIMINAR DESPUES
   
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
      // BUS
      //----------------------------------
   
      string msg="";
   
      if(vcBullOnce)
         msg="Bull Vector Candle";
      
      else if(vcBearOnce)
         msg="Bear Vector Candle";
   
      else if(atrBuyOnce)
         msg="ATR-Buy | " + (bbInsideBuy?"Internal":"External");
   
      else if(atrSellOnce)
         msg="ATR-Sell | " + (bbInsideSell?"Internal":"External");
   
      else if(bbBuyOnce)
         msg="2s-Buy | " + (bbInsideBuy?"Internal":"External");
   
      else if(bbSellOnce)
         msg="2s-Sell | " + (bbInsideSell?"Internal":"External");
   
      //----------------------------------
      // SEND TELEGRAM
      //----------------------------------
   
      if(msg!="" && CanSendAlert(symbol, tf))
      {
         string text = symbol+" "+EnumToString(tf)+"\n"+msg+
                 "\nPrice: "+DoubleToString(close,_Digits);
      
         SendTelegramMessage(text);
      
         Print("ALERT: ",text);
      }
      
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
   
      //--- HEARTBEAT 15 MIN
//      if(TimeCurrent() - lastHeartbeat >= 900)
//      {
//         string text = "EA ALIVE ✅\n" +
//              "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
//   
//         SendTelegramMessage(text);
//         Print("HEARTBEAT SENT");
   
//         lastHeartbeat = TimeCurrent();
//      }
      // // HEARTBEAT ELIMINAR DESPUES (HASTA AQUI)

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