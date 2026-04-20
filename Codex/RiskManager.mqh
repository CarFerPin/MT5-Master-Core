#ifndef __RISK_MANAGER_MQH__
#define __RISK_MANAGER_MQH__

// ----- config -----
double g_max_daily_loss_pct = 5.0;
double g_max_total_drawdown_pct = 10.0;
bool   g_block_new_entries_on_daily = true;
bool   g_block_new_entries_on_dd = true;

// ----- runtime -----
double   g_equity_day_start = 0.0;
double   g_equity_peak = 0.0;
datetime g_last_day = 0;

string   g_risk_path = "TradeAssistant\\risk_limits.ini";
datetime g_risk_last_modify = 0;
bool     g_risk_loaded = false;

bool g_risk_logged_daily = false;
bool g_risk_logged_dd = false;
bool g_risk_logged_block = false;

string RM_KeyDayStart()
{
   return "RM_DAY_START_" + AccountInfoString(ACCOUNT_SERVER) + "_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
}

int RM_DayKey(datetime t)
{
   MqlDateTime tm;
   TimeToStruct(t, tm);
   return tm.year * 10000 + tm.mon * 100 + tm.day;
}

datetime RM_GetModifyDate()
{
   int h = FileOpen(g_risk_path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return 0;
   datetime md = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
   FileClose(h);
   return md;
}

void RM_EnsureDayBaseline()
{
   datetime now = TimeCurrent();
   int curDay = RM_DayKey(now);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   string key = RM_KeyDayStart();
   string dayKey = key + "_DAY";

   bool hasBase = GlobalVariableCheck(key);
   bool hasDay = GlobalVariableCheck(dayKey);

   double storedBase = hasBase ? GlobalVariableGet(key) : 0.0;
   int storedDay = hasDay ? (int)GlobalVariableGet(dayKey) : 0;

   if(hasBase && hasDay && storedDay == curDay && storedBase > 0.0)
   {
      g_equity_day_start = storedBase;
      g_last_day = now;
      return;
   }

   g_equity_day_start = eq;
   g_last_day = now;
   GlobalVariableSet(key, g_equity_day_start);
   GlobalVariableSet(dayKey, (double)curDay);
}

bool LoadRiskLimits(string &err)
{
   err = "";

   int h = FileOpen(g_risk_path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      err = "Cannot open risk limits file: " + g_risk_path;
      return false;
   }

   // keep current as defaults; override if provided
   double maxDaily = g_max_daily_loss_pct;
   double maxDD = g_max_total_drawdown_pct;
   bool blockDaily = g_block_new_entries_on_daily;
   bool blockDD = g_block_new_entries_on_dd;

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);

      if(line == "" || StringFind(line, "=") < 0)
         continue;

      string parts[];
      if(StringSplit(line, '=', parts) < 2)
         continue;

      string key = parts[0];
      string val = parts[1];
      StringTrimLeft(key); StringTrimRight(key);
      StringTrimLeft(val); StringTrimRight(val);

      if(key == "max_daily_loss_pct")
         maxDaily = StringToDouble(val);
      else if(key == "max_total_drawdown_pct")
         maxDD = StringToDouble(val);
      else if(key == "block_new_entries_on_daily")
         blockDaily = ((int)StringToInteger(val) == 1);
      else if(key == "block_new_entries_on_dd")
         blockDD = ((int)StringToInteger(val) == 1);
   }

   datetime md = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
   FileClose(h);

   if(maxDaily < 0 || maxDD < 0)
   {
      err = "Risk limits must be non-negative";
      return false;
   }

   g_max_daily_loss_pct = maxDaily;
   g_max_total_drawdown_pct = maxDD;
   g_block_new_entries_on_daily = blockDaily;
   g_block_new_entries_on_dd = blockDD;

   g_risk_last_modify = md;
   g_risk_loaded = true;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_equity_peak = eq;
   RM_EnsureDayBaseline();

   g_risk_logged_daily = false;
   g_risk_logged_dd = false;
   g_risk_logged_block = false;

   return true;
}

bool CheckRiskReload()
{
   datetime md = RM_GetModifyDate();
   if(md == 0) return false;

   if(!g_risk_loaded || md != g_risk_last_modify)
   {
      string err="";
      if(!LoadRiskLimits(err))
      {
         Print("[ RISK ] reload failed: ", err);
         return false;
      }
      Print("[ RISK ] limits reloaded");
      return true;
   }

   return false;
}

void RM_UpdateRuntime()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime now = TimeCurrent();
   int curDay = RM_DayKey(now);
   string key = RM_KeyDayStart();
   string dayKey = key + "_DAY";

   if(g_last_day == 0 || g_equity_day_start <= 0.0)
      RM_EnsureDayBaseline();

   if(g_equity_peak <= 0.0)
      g_equity_peak = eq;

   if(RM_DayKey(g_last_day) != curDay)
   {
      g_equity_day_start = eq;
      g_last_day = now;
      GlobalVariableSet(key, g_equity_day_start);
      GlobalVariableSet(dayKey, (double)curDay);
      g_risk_logged_daily = false;
      g_risk_logged_block = false;
   }
   else if(GlobalVariableCheck(key) && GlobalVariableCheck(dayKey))
   {
      double storedBase = GlobalVariableGet(key);
      int storedDay = (int)GlobalVariableGet(dayKey);

      if(storedDay == curDay && storedBase > 0.0)
         g_equity_day_start = storedBase;
   }

   if(eq > g_equity_peak)
      g_equity_peak = eq;
}

double RM_GetDailyLossPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equity_day_start <= 0.0)
      return 0.0;

   return ((g_equity_day_start - eq) / g_equity_day_start) * 100.0;
}

double RM_GetDrawdownPct()
{
   if(g_equity_peak <= 0.0) return 0.0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return ((g_equity_peak - eq) / g_equity_peak) * 100.0;
}

bool IsDailyLossHit()
{
   RM_UpdateRuntime();
   double pct = RM_GetDailyLossPct();
   bool hit = (pct >= g_max_daily_loss_pct);

   if(hit && !g_risk_logged_daily)
   {
      Print(StringFormat("[ RISK ] Daily loss hit: %.2f%%", pct));
      g_risk_logged_daily = true;
   }
   if(!hit) g_risk_logged_daily = false;

   return hit;
}

bool IsMaxDDHit()
{
   RM_UpdateRuntime();
   double pct = RM_GetDrawdownPct();
   bool hit = (pct >= g_max_total_drawdown_pct);

   if(hit && !g_risk_logged_dd)
   {
      Print(StringFormat("[ RISK ] Max DD hit: %.2f%%", pct));
      g_risk_logged_dd = true;
   }
   if(!hit) g_risk_logged_dd = false;

   return hit;
}

bool IsRiskBlocked()
{
   RM_UpdateRuntime();

   double riskExisting = RM_GetPositionRiskToSL();
   double riskPending  = RM_GetPendingRiskToSL();

   double worstCaseTotal = riskExisting + riskPending;

   double allowedDailyLoss = g_equity_day_start * (g_max_daily_loss_pct / 100.0);
   double allowedDDLoss    = g_equity_peak * (g_max_total_drawdown_pct / 100.0);

   bool blockDaily = g_block_new_entries_on_daily && worstCaseTotal >= allowedDailyLoss;
   bool blockDD    = g_block_new_entries_on_dd    && worstCaseTotal >= allowedDDLoss;

   bool blocked = blockDaily || blockDD;

   if(blocked && !g_risk_logged_block)
   {
      Print("[ RISK ] Blocking new entries (worst-case SL risk)");
      g_risk_logged_block = true;
   }
   if(!blocked) g_risk_logged_block = false;

   return blocked;
}

double RM_GetPositionRiskToSL()
{
   double totalRisk = 0.0;

   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0 || vol <= 0.0) continue;

      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0) continue;

      double distance = MathAbs(open - sl);
      double risk = (distance / tickSize) * tickValue * vol;
      totalRisk += risk;
   }

   return totalRisk;
}

double RM_GetPendingRiskToSL()
{
   double totalRisk = 0.0;

   for(int i=0; i<OrdersTotal(); i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;

      long type = (long)OrderGetInteger(ORDER_TYPE);

      bool isPending =
         (type==ORDER_TYPE_BUY_LIMIT  || type==ORDER_TYPE_SELL_LIMIT ||
          type==ORDER_TYPE_BUY_STOP   || type==ORDER_TYPE_SELL_STOP  ||
          type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending) continue;

      string sym = OrderGetString(ORDER_SYMBOL);
      double entry = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl    = OrderGetDouble(ORDER_SL);
      double vol   = OrderGetDouble(ORDER_VOLUME_CURRENT);

      if(sl <= 0.0 || vol <= 0.0) continue;

      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0) continue;

      double distance = MathAbs(entry - sl);
      double risk = (distance / tickSize) * tickValue * vol;

      totalRisk += risk;
   }

   return totalRisk;
}


double RM_GetNewOrderRisk(double entry, double sl, double lots)
{
   if(lots <= 0.0) return 0.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double distance = MathAbs(entry - sl);
   return (distance / tickSize) * tickValue * lots;
}

bool CanOpenNewPosition(double entry, double sl, double lots)
{
   RM_UpdateRuntime();
    
    double riskExisting = RM_GetPositionRiskToSL();
    double riskPending  = RM_GetPendingRiskToSL();
    double riskNew      = RM_GetNewOrderRisk(entry, sl, lots);
    
    double projectedLoss = riskExisting + riskPending + riskNew;
    
    double allowedDailyLoss = g_equity_day_start * (g_max_daily_loss_pct / 100.0);
    double allowedDDLoss    = g_equity_peak * (g_max_total_drawdown_pct / 100.0);
    
    double projectedDaily = projectedLoss;
    double projectedDD    = projectedLoss;
    
    double openRisk = riskExisting + riskPending;
    
    bool dailyBlocked = g_block_new_entries_on_daily && projectedLoss >= allowedDailyLoss;
    bool ddBlocked    = g_block_new_entries_on_dd    && projectedLoss >= allowedDDLoss;
    
    Print(StringFormat(
       "[ RISK DAILY ] open=%.2f new_total=%.2f limit=%.2f status=%s",
       openRisk,
       projectedLoss,
       allowedDailyLoss,
       dailyBlocked ? "REJECTED" : "OK"
    ));
    
    Print(StringFormat(
       "[ RISK MAXDD ] open=%.2f new_total=%.2f limit=%.2f status=%s",
       openRisk,
       projectedLoss,
       allowedDDLoss,
       ddBlocked ? "REJECTED" : "OK"
    ));
    
    if(dailyBlocked)
    {
       Print("[ RISK ] Rejecting order (daily limit)");
       return false;
    }
    
    if(ddBlocked)
    {
       Print("[ RISK ] Rejecting order (max DD limit)");
       return false;
    }
    
    return true;
}

#endif
