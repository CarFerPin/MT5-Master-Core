#ifndef GENERATE_SIGNAL_MQH
#define GENERATE_SIGNAL_MQH

bool GenerateSignal(string symbol, ENUM_TIMEFRAMES tf, ScannerEngine::MarketSignal &signal)
{
   int shift = 1;

   double close = iClose(symbol,tf,shift);
   double open  = iOpen(symbol,tf,shift);
   double high  = iHigh(symbol,tf,shift);
   double low   = iLow(symbol,tf,shift);

   int maHandle  = iMA(symbol,tf,20,0,MODE_SMA,PRICE_CLOSE);
   int stdHandle = iStdDev(symbol,tf,20,0,MODE_SMA,PRICE_CLOSE);
   int atrHandle = iATR(symbol,tf,14);
   int ma5Handle = iMA(symbol,tf,5,0,MODE_SMA,PRICE_CLOSE);

   if(maHandle==INVALID_HANDLE || stdHandle==INVALID_HANDLE ||
      atrHandle==INVALID_HANDLE || ma5Handle==INVALID_HANDLE)
      return false;

   double maBuf[], stdBuf[], atrBuf[];

   if(CopyBuffer(maHandle,0,shift,1,maBuf)<=0) return false;
   if(CopyBuffer(stdHandle,0,shift,1,stdBuf)<=0) return false;
   if(CopyBuffer(atrHandle,0,shift,1,atrBuf)<=0) return false;

   double basis = maBuf[0];
   double stdev = stdBuf[0];
   double atr   = atrBuf[0];

   if(atr==0) return false;

   double dev = sigma * stdev;

   double upper = basis + dev;
   double lower = basis - dev;

   if(CopyBuffer(maHandle,0,shift+3,1,maBuf)<=0) return false;
   double basis_3 = maBuf[0];

   double slope = (basis - basis_3) / atr;
   bool trendValid = MathAbs(slope) > minSlopeATR;

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

   double prevOpen   = iOpen(symbol,tf,shift+1);
   double prevClose2 = iClose(symbol,tf,shift+1);
   double prevHigh   = iHigh(symbol,tf,shift+1);
   double prevLow    = iLow(symbol,tf,shift+1);

   double prevBody  = MathAbs(prevClose2-prevOpen);
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

   bool vcBullOnce = vectorBull && !prevVectorBull;
   bool vcBearOnce = vectorBear && !prevVectorBear;

   double ma5Buf[];
   if(CopyBuffer(ma5Handle,0,shift,1,ma5Buf)<=0) return false;

   double atrAnchor = ma5Buf[0];

   double uTopAbs = atrAnchor + atr*uTopATR;
   double uBotAbs = atrAnchor + atr*uBottomATR;

   double uHi = MathMax(uTopAbs,uBotAbs);
   double uLo = MathMin(uTopAbs,uBotAbs);

   double lTopAbs = atrAnchor + atr*lTopATR;
   double lBotAbs = atrAnchor + atr*lBottomATR;

   double lHi = MathMax(lTopAbs,lBotAbs);
   double lLo = MathMin(lTopAbs,lBotAbs);

   double buyLevel  = lower + dev * zoneDistFromBand;
   double sellLevel = upper - dev * zoneDistFromBand;

   bool bbBuy  = close <= buyLevel;
   bool bbSell = close >= sellLevel;

   bool atrBuy  = close>=lLo && close<=lHi;
   bool atrSell = close>=uLo && close<=uHi;

   double maBufPrev[], stdBufPrev[], atrBufPrev[], ma5BufPrev[];

   if(CopyBuffer(maHandle,0,shift+1,1,maBufPrev)<=0) return false;
   if(CopyBuffer(stdHandle,0,shift+1,1,stdBufPrev)<=0) return false;
   if(CopyBuffer(atrHandle,0,shift+1,1,atrBufPrev)<=0) return false;
   if(CopyBuffer(ma5Handle,0,shift+1,1,ma5BufPrev)<=0) return false;

   double basisPrev = maBufPrev[0];
   double stdevPrev = stdBufPrev[0];
   double atrPrev2  = atrBufPrev[0];
   double atrAnchorPrev = ma5BufPrev[0];

   double upperPrev = basisPrev + sigma*stdevPrev;
   double lowerPrev = basisPrev - sigma*stdevPrev;

   double buyLevelPrev  = lowerPrev + (basisPrev-lowerPrev)*zoneDistFromBand;
   double sellLevelPrev = upperPrev - (upperPrev-basisPrev)*zoneDistFromBand;

   double uTopPrev = atrAnchorPrev + atrPrev2*uTopATR;
   double uBotPrev = atrAnchorPrev + atrPrev2*uBottomATR;

   double uHiPrev = MathMax(uTopPrev,uBotPrev);
   double uLoPrev = MathMin(uTopPrev,uBotPrev);

   double lTopPrev = atrAnchorPrev + atrPrev2*lTopATR;
   double lBotPrev = atrAnchorPrev + atrPrev2*lBottomATR;

   double lHiPrev = MathMax(lTopPrev,lBotPrev);
   double lLoPrev = MathMin(lTopPrev,lBotPrev);

   bool bbBuyPrev  = prevClose2 <= buyLevelPrev;
   bool bbSellPrev = prevClose2 >= sellLevelPrev;

   bool atrBuyPrev  = prevClose2>=lLoPrev && prevClose2<=lHiPrev;
   bool atrSellPrev = prevClose2>=uLoPrev && prevClose2<=uHiPrev;

   bool bbBuyOnce  = bbBuy  && !bbBuyPrev;
   bool bbSellOnce = bbSell && !bbSellPrev;

   bool atrBuyOnce  = atrBuy  && !atrBuyPrev;
   bool atrSellOnce = atrSell && !atrSellPrev;

   bbBuyOnce  = bbBuyOnce  && trendValid;
   bbSellOnce = bbSellOnce && trendValid;
   atrBuyOnce  = atrBuyOnce  && trendValid;
   atrSellOnce = atrSellOnce && trendValid;

   string type="";
   int direction=0;

   if(vcBullOnce) { type="Vector Bull"; direction=1; }
   else if(vcBearOnce) { type="Vector Bear"; direction=-1; }
   else if(atrBuyOnce) { type="ATR Buy"; direction=1; }
   else if(atrSellOnce) { type="ATR Sell"; direction=-1; }
   else if(bbBuyOnce) { type="BB Buy"; direction=1; }
   else if(bbSellOnce) { type="BB Sell"; direction=-1; }
   else return false;

   signal.symbol = symbol;
   signal.timeframe = tf;
   signal.direction = direction;
   signal.type = type;
   signal.price = close;
   signal.time = iTime(symbol,tf,shift);
   signal.score = 70;

   return true;
}

#endif