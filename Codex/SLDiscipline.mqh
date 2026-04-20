#ifndef __SL_DISCIPLINE_MQH__
#define __SL_DISCIPLINE_MQH__

struct SLTrack
{
   ulong    ticket;
   string   symbol;
   int      digits;
   double   point;
   double   lockedSL;
   bool     initialized;
   datetime lastEnforceAttempt;
   int      enforceFailCount;
   uint     lastRetcode;
};

SLTrack g_slTracks[200];
int     g_slCount = 0;

double SLD_Norm(const double p, const int digits){ return NormalizeDouble(p, digits); }
double SLD_Eps(const double point){ return MathMax(point, point * 0.1); }
bool SLD_Greater(double a,double b,double eps){ return (a-b) > eps; }
bool SLD_Less(double a,double b,double eps){ return (b-a) > eps; }

string SLD_Key(const string symbol, const ulong tk)
{
   return "SLD_" + symbol + "_" + (string)tk;
}

int SLD_Find(ulong tk)
{
   for(int i=0;i<g_slCount;i++)
      if(g_slTracks[i].ticket==tk) return i;
   return -1;
}

bool SLD_Modify(ulong tk,double sl,double tp,uint &rc)
{
   rc=0;
   if(!PositionSelectByTicket(tk)) return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = tk;
   req.symbol   = symbol;
   req.sl       = SLD_Norm(sl, digits);
   req.tp       = SLD_Norm(tp, digits);

   bool ok = OrderSend(req,res);
   rc = (uint)res.retcode;

   if(!ok) return false;
   if(res.retcode!=TRADE_RETCODE_DONE && res.retcode!=TRADE_RETCODE_DONE_PARTIAL)
      return false;

   return true;
}

bool SLD_IsSLValidForBroker(const string symbol, const long type, const double candidateSL, string &why)
{
   why = "";

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point<=0)
   {
      why = "NO_POINT";
      return false;
   }

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0)
   {
      why = "NO_PRICE";
      return false;
   }

   int stopsLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int maxLevelPts = MathMax(stopsLevelPts, freezeLevelPts);
   double minDistance = (double)maxLevelPts * point;

   if(type == POSITION_TYPE_BUY)
   {
      if(candidateSL >= (bid - minDistance))
      {
         why = "TOO_CLOSE_TO_PRICE";
         return false;
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(candidateSL <= (ask + minDistance))
      {
         why = "TOO_CLOSE_TO_PRICE";
         return false;
      }
   }
   else
   {
      why = "INVALID_TYPE";
      return false;
   }

   return true;
}

bool SLD_CanRetry(datetime last,int fails)
{
   if(last<=0) return true;

   int cd=2;
   if(fails>=3) cd=5;
   if(fails>=6) cd=10;
   if(fails>=10) cd=20;

   return (TimeCurrent()-last)>=cd;
}

void SLD_RegisterOrRefresh(const ulong tk)
{
   if(!PositionSelectByTicket(tk)) return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point<=0) return;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl>0) sl = SLD_Norm(sl, digits);
   double eps = SLD_Eps(point);
   long type = PositionGetInteger(POSITION_TYPE);

   int idx = SLD_Find(tk);
   if(idx<0)
   {
      if(g_slCount>=ArraySize(g_slTracks)) return;

      g_slTracks[g_slCount].ticket=tk;
      g_slTracks[g_slCount].symbol=symbol;
      g_slTracks[g_slCount].digits=digits;
      g_slTracks[g_slCount].point=point;
      
      string key = SLD_Key(symbol, tk);
      double storedSL = 0;
      bool hasStored = GlobalVariableGet(key, storedSL);
      
      if(sl > 0)
      {
         g_slTracks[g_slCount].lockedSL = sl;
         GlobalVariableSet(key, sl);
         GlobalVariablesFlush();
      }
      else if(hasStored && storedSL > 0)
      {
         g_slTracks[g_slCount].lockedSL = storedSL;
      }
      else
      {
         return;
      }
      
      g_slTracks[g_slCount].initialized=true;
      g_slTracks[g_slCount].lastEnforceAttempt=0;
      g_slTracks[g_slCount].enforceFailCount=0;
      g_slTracks[g_slCount].lastRetcode=0;
      g_slCount++;
      return;
   }

   g_slTracks[idx].symbol=symbol;
   g_slTracks[idx].digits=digits;
   g_slTracks[idx].point=point;

   if(sl<=0) return;

   if(type==POSITION_TYPE_BUY && SLD_Greater(sl,g_slTracks[idx].lockedSL,eps))
   {
      g_slTracks[idx].lockedSL = sl;
      GlobalVariableSet(SLD_Key(symbol, tk), sl);
      GlobalVariablesFlush();
   }
   
   if(type==POSITION_TYPE_SELL && SLD_Less(sl,g_slTracks[idx].lockedSL,eps))
   {
      g_slTracks[idx].lockedSL = sl;
      GlobalVariableSet(SLD_Key(symbol, tk), sl);
      GlobalVariablesFlush();
   }
}

void SLD_EnforceSymbol(const string symbol)
{
   for(int i=0;i<g_slCount;i++)
   {
      ulong tk=g_slTracks[i].ticket;

      if(!PositionSelectByTicket(tk)) continue;
      if(!g_slTracks[i].initialized) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double lock  = SLD_Norm(g_slTracks[i].lockedSL, g_slTracks[i].digits);
      double eps   = SLD_Eps(g_slTracks[i].point);
      long   type  = PositionGetInteger(POSITION_TYPE);

      bool restore=false;
      if(curSL<=0) restore=true;
      else
      {
         curSL = SLD_Norm(curSL, g_slTracks[i].digits);
         if(type==POSITION_TYPE_BUY && SLD_Less(curSL,lock,eps)) restore=true;
         if(type==POSITION_TYPE_SELL && SLD_Greater(curSL,lock,eps)) restore=true;
      }

      if(!restore) continue;

      if(!SLD_CanRetry(g_slTracks[i].lastEnforceAttempt,
                       g_slTracks[i].enforceFailCount))
         continue;

      string brokerWhy="";
      if(!SLD_IsSLValidForBroker(symbol, type, lock, brokerWhy))
      {
         g_slTracks[i].lastEnforceAttempt = TimeCurrent();
      
         if(g_slTracks[i].enforceFailCount==0 || ((g_slTracks[i].enforceFailCount+1)%5)==0)
         {
            Print(StringFormat("[SL SKIP RESTORE] ticket=%I64u reason=%s", (long)tk, brokerWhy));
            Print(StringFormat("[SL SKIP] ticket=%I64u reason=%s", (long)tk, brokerWhy));
         }
      
         g_slTracks[i].enforceFailCount++;
         continue;
      }

      uint rc=0;
      g_slTracks[i].lastEnforceAttempt=TimeCurrent();

      if(SLD_Modify(tk,lock,tp,rc))
      {
         g_slTracks[i].enforceFailCount=0;
         g_slTracks[i].lastRetcode=0;
         Print(StringFormat("[SL RESTORE] ticket=%I64u locked=%.*f current=%.*f",
               (long)tk,
               g_slTracks[i].digits, lock,
               g_slTracks[i].digits, curSL));
      }
      else
      {
         g_slTracks[i].enforceFailCount++;
         g_slTracks[i].lastRetcode=rc;
         if(g_slTracks[i].enforceFailCount==1 || (g_slTracks[i].enforceFailCount%5)==0)
            Print(StringFormat("[SL FAIL] ticket=%I64u reason=RETCODE_%u", (long)tk, rc));
      }
   }
}

void SLD_Cleanup()
{
   for(int i=0;i<g_slCount;i++)
   {
      if(!PositionSelectByTicket(g_slTracks[i].ticket))
      {
         string key = SLD_Key(g_slTracks[i].symbol, g_slTracks[i].ticket);
         GlobalVariableDel(key);
         GlobalVariablesFlush();
         
         g_slTracks[i]=g_slTracks[g_slCount-1];
         g_slCount--;
         i--;
      }
   }
}

#endif
