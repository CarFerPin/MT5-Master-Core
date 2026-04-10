// MQL5\Include\Vtun_Mom\Vturn_TradeStops.mqh
#ifndef VTURN_MOM__TRADE_STOPS__MQH
#define VTURN_MOM__TRADE_STOPS__MQH

bool ValidateStopsForMarket(const bool isBuy, const double sl, const double tp)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return false;

   double price = isBuy ? ask : bid;

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (double)stopsLevel * _Point;

   if(sl > 0.0)
   {
      if(MathAbs(price - sl) < minDist) return false;
      if(isBuy && sl >= price) return false;
      if(!isBuy && sl <= price) return false;
   }

   if(tp > 0.0)
   {
      if(MathAbs(price - tp) < minDist) return false;
      if(isBuy && tp <= price) return false;
      if(!isBuy && tp >= price) return false;
   }

   return true;
}

#endif
