// MQL5\Include\TTT_Metals\NotificationsTelegram.mqh

#ifndef TTT_NOTIFICATIONS_TELEGRAM_MQH
#define TTT_NOTIFICATIONS_TELEGRAM_MQH

// --- CLOSE-by-position tracking
bool  tg_was_inpos = false;
ulong tg_pos_id    = 0;
ulong tg_last_close_pos_id = 0;  // dedupe CLOSE notifications

// Net PnL for a closed position via DEAL_POSITION_ID
bool TG_ClosedNetByPosId(const ulong pos_id, double &net, datetime &last_deal_time, int &n_out_deals)
{
   net = 0.0;
   last_deal_time = 0;
   n_out_deals = 0;
   if(pos_id == 0) return false;

   datetime now = TimeCurrent();
   datetime from = now - 86400 * 30; // ventana segura 30d

   if(!HistorySelect(from, now))
      return false;

   int total = HistoryDealsTotal();
   bool any = false;

   for(int i=0; i<total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      if((string)HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;

      ulong mg = (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(mg != gMagic) continue;

      ulong dp = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(dp != pos_id) continue;

      long entry = (long)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue; // solo cierres

      double p = HistoryDealGetDouble(deal, DEAL_PROFIT);
      double c = HistoryDealGetDouble(deal, DEAL_COMMISSION);
      double s = HistoryDealGetDouble(deal, DEAL_SWAP);
      net += (p + c + s);

      datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(t > last_deal_time) last_deal_time = t;

      n_out_deals++;
      any = true;
   }

   return any;
}


// --- Telegram helpers
void TG_Send(const string msg)
{
   if(!TG_Enabled) return;

   bool ok = tg.Send(msg);
   if(!ok)
   {
      if(tg.LastWasThrottled())
         Print("TG_THROTTLED | ", msg);
      else
         Print("TG_SEND_FAIL | ", msg);
   }
}

void TG_SendForce(const string msg)
{
   if(!TG_Enabled) return;

   bool ok = tg.Send(msg, true); // bypass throttle
   if(!ok) Print("TG_SEND_FAIL | ", msg);
}

#endif
