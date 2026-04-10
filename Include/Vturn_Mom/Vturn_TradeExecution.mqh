// MQL5\Include\Vturn_Mom\Vturn_TradeExecution.mq
#ifndef VTURN_MOM_TRADE_EXECUTION_MQH
#define VTURN_MOM__TRADE_STOPS__MQH

#include <Trade/Trade.mqh>
#include <Vturn_Mom/Vturn_Utils.mqh>
#include <Vturn_Mom/Vturn_TradeStops.mqh>

// --- runtime externs (estos SÍ deben existir en el EA)
extern ulong  gMagic;
extern ulong  g_ourTicket;

extern CTrade trade;

extern double tradeStop;
extern double tradeTarget;
extern bool   wasInPos;

// true si hay cualquier posición en el símbolo (de quien sea)
bool HasAnyPositionOnSymbol()
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if((string)PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

// selecciona la posición del EA (symbol + magic). HEDGING SAFE.
bool Vturn_SelectOurPosition()
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if((string)PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ulong mg = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(mg != gMagic) continue;

      g_ourTicket = ticket;
      return true;
   }

   g_ourTicket = 0;
   return false;
}

long Vturn_OurPosType()
{
   if(g_ourTicket == 0) return -1;
   if(!PositionSelectByTicket(g_ourTicket)) return -1;
   return (long)PositionGetInteger(POSITION_TYPE);
}

bool Vturn_ModifyOurPosition(const double sl, const double tp)
{
   if(g_ourTicket == 0) return false;
   if(!PositionSelectByTicket(g_ourTicket)) return false;

   return trade.PositionModify(_Symbol, sl, tp);
}

bool Vturn_CloseOurPosition()
{
   if(!Vturn_SelectOurPosition()) return false;
   return trade.PositionClose(_Symbol);
}

// Trailing HL + stepped R, y opcional TP ratchet.
// PARAMS vienen del EA (V_StopPct / V_TakePct), NO de driver.
void Vturn_ManageStopRatchetHL(
   const bool   useStopRatchetHL,
   const int    hlCount,
   const bool   useTPRatchet,
   const double stopPct,
   const double takePct
)
{
   if(!useStopRatchetHL) return;
   if(hlCount < 2) return;
   if(stopPct <= 0.0) return;

   bool inPos = Vturn_SelectOurPosition();
   if(!inPos)
   {
      tradeStop   = 0.0;
      tradeTarget = 0.0;
      wasInPos    = false;
      return;
   }

   long type = Vturn_OurPosType();
   if(type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL) return;

   if(!wasInPos)
   {
      tradeStop   = PositionGetDouble(POSITION_SL);
      tradeTarget = PositionGetDouble(POSITION_TP);
      wasInPos    = true;
   }

   double c = iClose(_Symbol, _Period, 1);
   if(c <= 0.0) return;

   double ep = PositionGetDouble(POSITION_PRICE_OPEN);
   if(ep <= 0.0) return;

   double tick = _Point * 2.0;

   double rPct = stopPct / 100.0;
   double pPct = takePct / 100.0;

   double R = ep * rPct;
   double P = ep * pPct;

   double support = LowestLow(1, hlCount);
   double resist  = HighestHigh(1, hlCount);

   double longStopHL  = (support > 0.0) ? MathMax(support, ep * (1.0 - rPct)) : (ep * (1.0 - rPct));
   double shortStopHL = (resist  > 0.0) ? MathMin(resist,  ep * (1.0 + rPct)) : (ep * (1.0 + rPct));

   double newSL = tradeStop;

   if(type == POSITION_TYPE_BUY)
   {
      double stopCand = 0.0;

      if(c >= ep + 4.0*R)      stopCand = ep + 1.0*R;
      else if(c >= ep + 3.0*R) stopCand = ep + 0.5*R;
      else if(c >= ep + 2.0*R) stopCand = ep + 0.0*R;
      else if(c >= ep + 1.0*R) stopCand = ep - 0.5*R;

      if(stopCand > 0.0)
      {
         stopCand = MathMax(stopCand, longStopHL);

         if(stopCand < c - tick)
         {
            stopCand = NormalizeDouble(stopCand, _Digits);
            if(newSL <= 0.0 || stopCand > newSL) newSL = stopCand;
         }
      }
   }
   else // SELL (Vturn no vende, pero lo dejo por consistencia si algún día habilitas AllowSell)
   {
      double stopCand = 0.0;

      if(c <= ep - 4.0*R)      stopCand = ep - 1.0*R;
      else if(c <= ep - 3.0*R) stopCand = ep - 0.5*R;
      else if(c <= ep - 2.0*R) stopCand = ep - 0.0*R;
      else if(c <= ep - 1.0*R) stopCand = ep + 0.5*R;

      if(stopCand > 0.0)
      {
         stopCand = MathMin(stopCand, shortStopHL);

         if(stopCand > c + tick)
         {
            stopCand = NormalizeDouble(stopCand, _Digits);
            if(newSL <= 0.0 || stopCand < newSL) newSL = stopCand;
         }
      }
   }

   double newTP = tradeTarget;

   if(useTPRatchet && takePct > 0.0)
   {
      if(type == POSITION_TYPE_BUY)
      {
         double tpCand = 0.0;
         if(c >= ep + 0.95*P)      tpCand = ep + 1.50*P;
         else if(c >= ep + 0.80*P) tpCand = ep + 1.25*P;
         else if(c >= ep + 0.60*P) tpCand = ep + 1.10*P;

         if(tpCand > 0.0 && tpCand > c + tick)
         {
            tpCand = NormalizeDouble(tpCand, _Digits);
            if(newTP <= 0.0 || tpCand > newTP) newTP = tpCand;
         }
      }
      else
      {
         double tpCand = 0.0;
         if(c <= ep - 0.95*P)      tpCand = ep - 1.50*P;
         else if(c <= ep - 0.80*P) tpCand = ep - 1.25*P;
         else if(c <= ep - 0.60*P) tpCand = ep - 1.10*P;

         if(tpCand > 0.0 && tpCand < c - tick)
         {
            tpCand = NormalizeDouble(tpCand, _Digits);
            if(newTP <= 0.0 || tpCand < newTP) newTP = tpCand;
         }
      }
   }

   bool slChanged = (newSL > 0.0 && MathAbs(newSL - tradeStop) > (_Point/2.0));
   bool tpChanged = (newTP > 0.0 && MathAbs(newTP - tradeTarget) > (_Point/2.0));

   if(slChanged || tpChanged)
   {
      if(Vturn_ModifyOurPosition(newSL, newTP))
      {
         tradeStop   = newSL;
         tradeTarget = newTP;
      }
   }
}

#endif // VTURN_TRADE_EXECUTION_MQH
