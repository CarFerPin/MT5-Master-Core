// MQL5\Include\TTT_Metals\TradeStops.mqh
#ifndef TTT_TRADE_STOPS_MQH
#define TTT_TRADE_STOPS_MQH

double GetMinStopDistancePrice()
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL); // in points
   if(stopsLevel <= 0) return 0.0;
   return stopsLevel * _Point;
}

double NormalizeToTick(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0) return NormalizeDouble(price, _Digits);

   double n = MathRound(price / tickSize) * tickSize;
   return NormalizeDouble(n, _Digits);
}

bool ValidateStopsForMarket(const bool isBuy, double &sl, double &tp)
{
   // enforce min stop distance if broker requires
   double minDist = GetMinStopDistancePrice();
   if(minDist <= 0.0) return true;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double ref = isBuy ? ask : bid;

   if(sl > 0.0)
   {
      double d = MathAbs(ref - sl);
      if(d < minDist)
      {
         if(isBuy) sl = ref - minDist;
         else      sl = ref + minDist;
         sl = NormalizeToTick(sl);
      }
   }

   if(tp > 0.0)
   {
      double d = MathAbs(tp - ref);
      if(d < minDist)
      {
         if(isBuy) tp = ref + minDist;
         else      tp = ref - minDist;
         tp = NormalizeToTick(tp);
      }
   }

   return true;
}

void ComputeFixedSLTP(const bool isBuy, const double entry, const double stopPct, const double takePct, double &sl, double &tp)
{
   sl = 0.0; tp = 0.0;

   if(entry <= 0.0) return;

   double sp   = stopPct / 100.0;
   double tpp  = takePct / 100.0;

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

#endif // TTT_TRADE_STOPS_MQH
