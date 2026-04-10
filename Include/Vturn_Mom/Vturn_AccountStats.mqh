// MQL5\Include\Vtun_Mom\Vturn_AccountStats.mqh
#ifndef VTURN_MOM_ACCOUNT_STATS_MQH
#define VTURN_MOM_ACCOUNT_STATS_MQH

double TodayClosedNet()
{
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime start = StructToTime(dt);

   if(!HistorySelect(start, now))
      return 0.0;

   double sum = 0.0;
   int total = HistoryDealsTotal();
   for(int i=0; i<total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      if((string)HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;

      ulong mg = (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(mg != gMagic) continue;

      long entry = (long)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      double p = HistoryDealGetDouble(deal, DEAL_PROFIT);
      double c = HistoryDealGetDouble(deal, DEAL_COMMISSION);
      double s = HistoryDealGetDouble(deal, DEAL_SWAP);
      sum += (p + c + s);
   }
   return sum;
}

#endif // VTURN_MOM_ACCOUNT_STATS_MQH
