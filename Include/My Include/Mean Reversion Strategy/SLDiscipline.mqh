#ifndef __SL_DISCIPLINE_MQH__
#define __SL_DISCIPLINE_MQH__

struct SLTrack
{
   ulong    ticket;
   double   lockedSL;
   bool     initialized;
   datetime lastEnforceAttempt;
   int      enforceFailCount;
   uint     lastRetcode;
};

SLTrack g_slTracks[200];
int     g_slCount = 0;

// ---------------- helpers ----------------
double SLD_Norm(const double p){ return NormalizeDouble(p, _Digits); }
double SLD_Eps(){ return _Point * 0.1; }

bool SLD_Greater(double a,double b){ return (a-b) > SLD_Eps(); }
bool SLD_Less(double a,double b){ return (b-a) > SLD_Eps(); }

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

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = tk;
   req.symbol   = PositionGetString(POSITION_SYMBOL);
   req.sl       = SLD_Norm(sl);
   req.tp       = SLD_Norm(tp);

   bool ok = OrderSend(req,res);
   rc = (uint)res.retcode;

   if(!ok) return false;
   if(res.retcode!=TRADE_RETCODE_DONE &&
      res.retcode!=TRADE_RETCODE_DONE_PARTIAL)
      return false;

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

// ---------------- REGISTER ----------------
void SLD_RegisterOrRefresh(const ulong tk)
{
   if(!PositionSelectByTicket(tk)) return;

   // SOLO EA trades
   string cmt = PositionGetString(POSITION_COMMENT);
   if(StringFind(cmt,"TA")<0) return;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl<=0) return;

   sl = SLD_Norm(sl);
   long type = PositionGetInteger(POSITION_TYPE);

   int idx = SLD_Find(tk);

   if(idx<0)
   {
      if(g_slCount>=ArraySize(g_slTracks)) return;

      g_slTracks[g_slCount].ticket=tk;
      g_slTracks[g_slCount].lockedSL=sl;
      g_slTracks[g_slCount].initialized=true;
      g_slTracks[g_slCount].lastEnforceAttempt=0;
      g_slTracks[g_slCount].enforceFailCount=0;
      g_slTracks[g_slCount].lastRetcode=0;
      g_slCount++;
      return;
   }

   // SOLO mejora (BE)
   if(type==POSITION_TYPE_BUY && SLD_Greater(sl,g_slTracks[idx].lockedSL))
      g_slTracks[idx].lockedSL=sl;

   if(type==POSITION_TYPE_SELL && SLD_Less(sl,g_slTracks[idx].lockedSL))
      g_slTracks[idx].lockedSL=sl;
}

// ---------------- ENFORCE ----------------
void SLD_Enforce()
{
   for(int i=0;i<g_slCount;i++)
   {
      ulong tk=g_slTracks[i].ticket;

      if(!PositionSelectByTicket(tk)) continue;
      if(!g_slTracks[i].initialized) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double lock  = SLD_Norm(g_slTracks[i].lockedSL);
      long   type  = PositionGetInteger(POSITION_TYPE);

      bool restore=false;

      if(curSL<=0) restore=true;
      else
      {
         curSL = SLD_Norm(curSL);

         if(type==POSITION_TYPE_BUY && SLD_Less(curSL,lock)) restore=true;
         if(type==POSITION_TYPE_SELL && SLD_Greater(curSL,lock)) restore=true;
      }

      if(!restore) continue;

      if(!SLD_CanRetry(g_slTracks[i].lastEnforceAttempt,
                       g_slTracks[i].enforceFailCount))
         continue;

      uint rc=0;
      g_slTracks[i].lastEnforceAttempt=TimeCurrent();

      if(SLD_Modify(tk,lock,tp,rc))
      {
         g_slTracks[i].enforceFailCount=0;
         g_slTracks[i].lastRetcode=0;
         Print("SLD restored SL tk=",tk);
      }
      else
      {
         g_slTracks[i].enforceFailCount++;
         g_slTracks[i].lastRetcode=rc;

         if(g_slTracks[i].enforceFailCount==1 ||
            g_slTracks[i].enforceFailCount%5==0)
         {
            Print("SLD fail tk=",tk,
                  " rc=",rc,
                  " fails=",g_slTracks[i].enforceFailCount);
         }
      }
   }
}

// ---------------- CLEANUP ----------------
void SLD_Cleanup()
{
   for(int i=0;i<g_slCount;i++)
   {
      if(!PositionSelectByTicket(g_slTracks[i].ticket))
      {
         g_slTracks[i]=g_slTracks[g_slCount-1];
         g_slCount--;
         i--;
      }
   }
}

#endif