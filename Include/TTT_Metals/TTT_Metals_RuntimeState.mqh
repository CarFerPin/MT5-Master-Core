// MQL5\Include\TTT_Metals\RunTimeState.mqh

#ifndef TTT_RUNTIME_STATE_MQH
#define TTT_RUNTIME_STATE_MQH

string GV_Prefix()
{
   return "TTT." + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "." + _Symbol + "." + (string)gMagic + ".";
}

bool GV_Get(const string suffix, double &val)
{
   string k = GV_Prefix() + suffix;
   if(!GlobalVariableCheck(k)) return false;
   val = GlobalVariableGet(k);
   return true;
}

void GV_Set(const string suffix, const double val)
{
   GlobalVariableSet(GV_Prefix() + suffix, val);
}

int DateYMD(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return dt.year*10000 + dt.mon*100 + dt.day;
}

void RestoreRuntimeState()
{
   double v;
   if(GV_Get("last_hb", v)) tg_last_heartbeat = (datetime)v;
   if(GV_Get("last_daily", v)) tg_last_daily = (datetime)v;
   if(GV_Get("news_active", v)) news_was_active = (v > 0.5);
   if(GV_Get("last_close_posid", v)) tg_last_close_pos_id = (ulong)v;
}

void PersistRuntimeState()
{
   GV_Set("last_hb", (double)tg_last_heartbeat);
   GV_Set("last_daily", (double)tg_last_daily);
   GV_Set("news_active", news_was_active ? 1.0 : 0.0);
   GV_Set("last_close_posid", (double)tg_last_close_pos_id);
}

#endif
