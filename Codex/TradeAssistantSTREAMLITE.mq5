//+------------------------------------------------------------------+
//| TradeAssistantMASTERCONTROL.mq5                                         |
//| Manual trade assistant   | MULTIASSET VERSION
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#define MAX_TRAIL_TRACK 100

#include "Trade.mqh"
#include "SLDiscipline.mqh"
#include "Schedule.mqh"
#include "RiskManager.mqh"
#include "MasterSize.mqh"
#include "MasterControl.mqh"
CTrade trade;

enum ENV_TYPE { ENV_DEMO=0, ENV_REAL=1, ENV_PROP=2 };

string BrokerProfile = "";
input string AssetProfile  = "US500";

input double ManualSize = 0.0;
input double RR   = 1.2;
input double SL_Multiplier = 1.0;
input double BE_TriggerPercent = 0.65;
input int MinRefreshDistancePts = 2;
long g_login;
string g_server;
ENV_TYPE g_env = ENV_DEMO;
double g_size_multiplier;

int g_sl_pts;
int g_max_spread;
int g_entry_offset;
int g_min_sl;
int g_max_sl;
int g_slippage;
int g_be_protect_pts;

ulong  g_trailTickets[MAX_TRAIL_TRACK];
double g_trailInitialSL[MAX_TRAIL_TRACK];
int g_trailTranche[MAX_TRAIL_TRACK];


bool g_envValid = false;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;

bool g_wasBlocked = false;

string BTN_BUY="TA_BUY", BTN_SELL="TA_SELL", BTN_BE="TA_BE";
string BTN_CANCEL="TA_CANCEL";
string BTN_CLOSE="TA_CLOSE";
string BTN_FBUY="TA_FastBUY", BTN_FSELL="TA_FastSELL";

string LBL_STATUS="TA_STATUS";
string g_lastStatusText = "";
bool g_showStatus=true;

ulong g_fastTicket = 0;
bool g_fastIsBuy = true;
datetime g_fastLastRpl = 0;

struct ClosedTradeRecord
{
   ulong deal_ticket;
   datetime close_time;
   double profit;
   double commission;
   double swap;
   string symbol;
};

ClosedTradeRecord g_closedTrades[];
ulong g_lastClosedDealTicket = 0;
datetime g_lastTradeHistoryUpdate = 0;

void DetectFillingMode()
{
   uint fillingMode = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillingMode & SYMBOL_FILLING_IOC) != 0)
      g_filling = ORDER_FILLING_IOC;
   else if((fillingMode & SYMBOL_FILLING_FOK) != 0)
      g_filling = ORDER_FILLING_FOK;
   else
      g_filling = ORDER_FILLING_RETURN;
}

double GetSpreadPoints(string symbol)
{
   double ask=SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid=SymbolInfoDouble(symbol, SYMBOL_BID);
   if(ask<=0 || bid<=0) return 0.0;
   return (ask-bid)/_Point;
}

bool ValidateEnvironment(string &reason)
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(server != g_server)
   {
      reason = "Server mismatch";
      return false;
   }
   if(g_env == ENV_DEMO && mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      reason = "Expected DEMO but broker reports REAL";
      return false;
   }
   if((g_env == ENV_REAL || g_env == ENV_PROP) && mode != ACCOUNT_TRADE_MODE_REAL)
   {
      reason = "Expected REAL/PROP but broker reports DEMO";
      return false;
   }
   return true;
}

bool LoadBroker(string profile, string &err)
{
   string path = "TradeAssistant\\" + profile + ".ini";

   int h = FileOpen(path, FILE_READ | FILE_CSV | FILE_ANSI, '=');
   if(h == INVALID_HANDLE)
   {
      err = "Cannot open broker file: " + path;
      return false;
   }

   // reset
   g_login = 0;
   g_server = "";
   g_env = ENV_DEMO;
   g_size_multiplier = 1.0;

   while(!FileIsEnding(h))
   {
      string key = FileReadString(h);
      if(FileIsEnding(h))
         break;

      string val = FileReadString(h);

      StringTrimLeft(key);
      StringTrimRight(key);
      StringTrimLeft(val);
      StringTrimRight(val);

      if(key == "" || val == "")
         continue;

      if(key=="login") g_login = (long)StringToInteger(val);
      else if(key=="server") g_server = val;
      else if(key=="env")
      {
         if(val=="ENV_DEMO") g_env=ENV_DEMO;
         else if(val=="ENV_REAL") g_env=ENV_REAL;
         else if(val=="ENV_PROP") g_env=ENV_PROP;
      }
      else if(key=="size_multiplier") g_size_multiplier = StringToDouble(val);
   }

   FileClose(h);

   if(g_login <= 0 || g_server == "")
   {
      err = "Invalid broker config";
      return false;
   }

   return true;
}

bool LoadAsset(string profile, string &err)
{
   string path = "TradeAssistant\\" + profile + ".ini";

   int h = FileOpen(path, FILE_READ | FILE_CSV | FILE_ANSI, '=');
   if(h == INVALID_HANDLE)
   {
      err = "Cannot open asset file: " + path;
      return false;
   }

   // reset defensivo
   g_sl_pts         = 0;
   g_max_spread     = 0;
   g_entry_offset   = 0;
   g_min_sl         = 0;
   g_max_sl         = 0;
   g_slippage       = 0;
   g_be_protect_pts = 0;

   while(!FileIsEnding(h))
   {
      string key = FileReadString(h);
      if(FileIsEnding(h))
         break;

      string val = FileReadString(h);

      StringTrimLeft(key);
      StringTrimRight(key);
      StringTrimLeft(val);
      StringTrimRight(val);

      if(key == "" || val == "")
         continue;

      if(key=="sl_pts")          g_sl_pts         = (int)StringToInteger(val);
      else if(key=="max_spread_pts")  g_max_spread     = (int)StringToInteger(val);
      else if(key=="entry_offset_pts")g_entry_offset   = (int)StringToInteger(val);
      else if(key=="min_sl_pts")      g_min_sl         = (int)StringToInteger(val);
      else if(key=="max_sl_pts")      g_max_sl         = (int)StringToInteger(val);
      else if(key=="slippage")        g_slippage       = (int)StringToInteger(val);
      else if(key=="be_protect_pts")  g_be_protect_pts = (int)StringToInteger(val);
   }

   FileClose(h);

   if(g_sl_pts <= 0 || g_max_spread <= 0)
   {
      err = StringFormat("Invalid asset config | sl_pts=%d max_spread=%d",
                         g_sl_pts, g_max_spread);
      return false;
   }

   return true;
}

double GetProtectionFactor(double progress)
{
   if(progress < 0.2)
      return 0.0;

   double x = (progress - 0.2) / 0.7;
   x = MathMax(0.0, MathMin(1.0, x));

   return 0.5 * MathPow(x, 1.4);
}

void ApplySmartTrailing(const string symbol)
{
   if(!PositionSelect(symbol)) return;

   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   long type = PositionGetInteger(POSITION_TYPE);

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double tp   = PositionGetDouble(POSITION_TP);
   double curSL = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double total = MathAbs(tp - open);
   if(total <= 0.0) return;

   double progress = 0.0;
   if(type == POSITION_TYPE_BUY)
      progress = (bid - open) / total;
   else if(type == POSITION_TYPE_SELL)
      progress = (open - ask) / total;
   else
      return;

   int tranche = -1;
   if(progress < 0.2) return;
   else if(progress < 0.35) tranche = 0;
   else if(progress < 0.5) tranche = 1;
   else if(progress < 0.7) tranche = 2;
   else if(progress < 0.9) tranche = 3;
   else tranche = 4;

   int lastTranche = Trail_GetTranche(ticket);
   if(tranche <= lastTranche)
      return;

   double initialSL = 0.0;
   if(!Trail_GetInitialSL(ticket, initialSL))
      return;

   double risk = MathAbs(open - initialSL);
   if(risk <= 0.0) return;

   double candidateSL = 0.0;

   if(type == POSITION_TYPE_BUY)
   {
      if(tranche == 0) candidateSL = open - 0.80 * risk;
      else if(tranche == 1) candidateSL = open - 0.50 * risk;
      else if(tranche == 2) candidateSL = open;
      else if(tranche == 3) candidateSL = open + 0.25 * total;
      else if(tranche == 4) candidateSL = open + 0.50 * total;
      else return;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(tranche == 0) candidateSL = open + 0.80 * risk;
      else if(tranche == 1) candidateSL = open + 0.50 * risk;
      else if(tranche == 2) candidateSL = open;
      else if(tranche == 3) candidateSL = open - 0.25 * total;
      else if(tranche == 4) candidateSL = open - 0.50 * total;
      else return;
   }
   else
      return;

   candidateSL = NormalizeDouble(candidateSL, digits);

   if(type == POSITION_TYPE_BUY)
   {
      if(curSL > 0.0 && candidateSL <= curSL)
         return;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(curSL > 0.0 && candidateSL >= curSL)
         return;
   }

   if(TryPromoteSL(ticket, candidateSL, "TRANCHE_TRAIL"))
      Trail_SetTranche(ticket, tranche);
}

bool GetMidEntry(bool isBuy, double &entry)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return false;

   double mid = (bid + ask) * 0.5;
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick = _Point;

   entry = NormalizeDouble(MathRound(mid / tick) * tick, _Digits);

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;

   if(isBuy && entry >= ask - minDist) return false;
   if(!isBuy && entry <= bid + minDist) return false;
   return (entry > 0);
}

double ResolveLotSize()
{
   // 1. PRIORIDAD ABSOLUTA: manual override
   if(ManualSize > 0.0)
      return ManualSize;

   // 2. Fuente principal: control.json
   double baseVolume = GetBaseVolume();

   if(baseVolume <= 0.0)
   {
      Print("[SIZE ERROR] base_volume not defined in control.json");
      return 0.0;
   }

   // 3. Ajuste por broker
   double adjusted = baseVolume * g_size_multiplier;

   // 4. Ajuste por modo (trend / counter)
   double finalVolume = adjusted * GetVolumeMultiplier();

   return finalVolume;
}

double NormalizeLot(double raw)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(raw < vmin || raw > vmax)
      return 0.0;

   double lots = MathFloor(raw / vstep) * vstep;

   int volDigits = (int)MathRound(-MathLog10(vstep));
   lots = NormalizeDouble(lots, volDigits);

   return lots;
}

bool BuildOrder(bool isBuy, double &entry, double &sl, double &tp, double &lots, string &reason)
{
   double spr = GetSpreadPoints(_Symbol);
   if(spr > g_max_spread)
   {
      reason = StringFormat("SPREAD BLOCK: %.1f pts > max %d", spr, g_max_spread);
      return false;
   }

   double adjusted_sl_pts = g_sl_pts * SL_Multiplier;
   if(adjusted_sl_pts < g_min_sl || adjusted_sl_pts > g_max_sl)
   {
      reason = "SL points out of allowed range (after multiplier)";
      return false;
   }

   int slPtsParaCalculo = (int)adjusted_sl_pts;
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel > 0) slPtsParaCalculo = MathMax(slPtsParaCalculo, stopsLevel + 2);

   double slDist = (double)slPtsParaCalculo * _Point;
   double tpDist = slDist * RR;

   if(isBuy) { sl = entry - slDist; tp = entry + tpDist; }
   else      { sl = entry + slDist; tp = entry - tpDist; }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double raw_lot = ResolveLotSize();
   lots = NormalizeLot(raw_lot);
    
   if(lots <= 0.0)
   {
       reason = "Invalid lot (after normalization)";
       return false;
   }

   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(freeze > 0)
   {
      double freezeDist = freeze * _Point;
      if(slDist <= freezeDist)
      {
         reason = "SL inside FreezeLevel";
         return false;
      }
   }
   return true;
}

bool SendFastLimit(bool isBuy, double lots, double entry, double sl, double tp, string &reason, ulong &outTicket)
{
   trade.SetTypeFilling(g_filling);
   trade.SetDeviationInPoints(g_slippage);

   bool ok = isBuy ? trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "TA_FAST")
                   : trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "TA_FAST");

   if(!ok)
   {
      reason = StringFormat("OrderSend failed. ret=%d, err=%d", trade.ResultRetcode(), GetLastError());
      outTicket = 0;
      return false;
   }

   outTicket = (ulong)trade.ResultOrder();
   if(outTicket==0)
   {
      reason = "Fast order placed but ticket is 0";
      return false;
   }
   return true;
}

bool FastOrderIsAlive()
{
   if(g_fastTicket==0) return false;
   if(!OrderSelect(g_fastTicket)) return false;

   long st = (long)OrderGetInteger(ORDER_STATE);
   if(st!=ORDER_STATE_PLACED && st!=ORDER_STATE_PARTIAL) return false;

   return (OrderGetString(ORDER_SYMBOL)==_Symbol);
}

void RefreshFastOrder()
{
   if(!FastOrderIsAlive()) { g_fastTicket = 0; return; }

   datetime now = TimeCurrent();
   if((now - g_fastLastRpl) < 5) return;

   double entry=0, sl=0, tp=0, lots=0;
   string reason="";

   if(!GetMidEntry(g_fastIsBuy, entry)) return;
   if(!BuildOrder(g_fastIsBuy, entry, sl, tp, lots, reason)) return;

   double currentEntry = OrderGetDouble(ORDER_PRICE_OPEN);
   double minRefreshDistance = (double)MinRefreshDistancePts * _Point;
   if(MathAbs(entry - currentEntry) < minRefreshDistance) return;

   ulong newTicket=0;
   if(!SendFastLimit(g_fastIsBuy, lots, entry, sl, tp, reason, newTicket)) return;

   if(trade.OrderDelete(g_fastTicket))
   {
      g_fastTicket = newTicket;
      g_fastLastRpl = now;
   }
}

bool ModifyPositionSLTP(ulong ticket, double newSL, double newTP, string &err)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   if(!PositionSelectByTicket(ticket))
   {
      err = "Position not found";
      return false;
   }

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = PositionGetString(POSITION_SYMBOL);
   req.sl       = newSL;
   req.tp       = newTP;

   ResetLastError();
   if(!OrderSend(req, res))
   {
      err = StringFormat("OrderSend failed. le=%d", GetLastError());
      return false;
   }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL)
   {
      err = StringFormat("retcode=%d", (int)res.retcode);
      return false;
   }
   return true;
}

int Trail_Find(const ulong ticket)
{
   for(int i=0;i<MAX_TRAIL_TRACK;i++)
      if(g_trailTickets[i]==ticket)
         return i;
   return -1;
}

bool Trail_Register(const ulong ticket, const double sl)
{
   if(Trail_Find(ticket)>=0) return true;

   for(int i=0;i<MAX_TRAIL_TRACK;i++)
   {
      if(g_trailTickets[i]==0)
      {
         g_trailTickets[i]=ticket;
         g_trailInitialSL[i]=sl;
         g_trailTranche[i] = -1; 
         return true;
      }
   }
   return false;
}

bool Trail_GetInitialSL(const ulong ticket, double &sl)
{
   int idx = Trail_Find(ticket);
   if(idx<0) return false;
   sl = g_trailInitialSL[idx];
   return true;
}

void Trail_Cleanup()
{
   for(int i=0; i<MAX_TRAIL_TRACK; i++)
   {
      if(g_trailTickets[i] == 0)
         continue;

      if(!PositionSelectByTicket(g_trailTickets[i]))
      {
         g_trailTickets[i] = 0;
         g_trailInitialSL[i] = 0.0;
         g_trailTranche[i] = -1;
      }
   }
}

int Trail_GetTranche(const ulong ticket)
{
   int idx = Trail_Find(ticket);
   if(idx < 0) return -1;
   return g_trailTranche[idx];
}

void Trail_SetTranche(const ulong ticket, const int t)
{
   int idx = Trail_Find(ticket);
   if(idx < 0) return;
   g_trailTranche[idx] = t;
}

bool ValidateSLCandidate(const string symbol, const long type, const double candidateSL, string &failReason)
{
   failReason = "";
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0)
   {
      failReason = "NO_POINT";
      return false;
   }

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0)
   {
      failReason = "NO_PRICE";
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
         failReason = (freezeLevelPts >= stopsLevelPts) ? "FREEZE_LEVEL" : "INVALID_DISTANCE";
         return false;
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(candidateSL <= (ask + minDistance))
      {
         failReason = (freezeLevelPts >= stopsLevelPts) ? "FREEZE_LEVEL" : "INVALID_DISTANCE";
         return false;
      }
   }
   else
   {
      failReason = "INVALID_TYPE";
      return false;
   }

   return true;
}

bool TryPromoteSL(ulong ticket, double candidateSL, string reason)
{
   if(!PositionSelectByTicket(ticket)) return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point<=0) return false;

   long type = PositionGetInteger(POSITION_TYPE);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);

   candidateSL = NormalizeDouble(candidateSL, digits);

   bool improves=false;
   if(type == POSITION_TYPE_BUY)
   {
      improves = (curSL <= 0.0 || candidateSL > curSL);
      if(!improves)
      {
         return false;
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      improves = (curSL <= 0.0 || candidateSL < curSL);
      if(!improves)
      {
         return false;
      }
   }
   else return false;

   string distReason="";
   if(!ValidateSLCandidate(symbol, type, candidateSL, distReason))
   {
      if(distReason=="FREEZE_LEVEL")
         Print(StringFormat("[SL FAIL] %s ticket=%I64u reason=FREEZE_LEVEL", symbol, (long)ticket));
      else if(distReason=="INVALID_DISTANCE")
         Print(StringFormat("[SL FAIL] %s ticket=%I64u reason=INVALID_DISTANCE", symbol, (long)ticket));
      else
         Print(StringFormat("[SL SKIP] %s ticket=%I64u reason=%s", symbol, (long)ticket, distReason));
     }
     
   string err="";
   if(!ModifyPositionSLTP(ticket, candidateSL, curTP, err))
   {
      int pos = StringFind(err, "retcode=");
      if(pos >= 0)
      {
         string code = StringSubstr(err, pos + 8);
         Print(StringFormat("[SL FAIL] ticket=%I64u reason=RETCODE_%s", (long)ticket, code));
      }
      else
         Print(StringFormat("[SL FAIL] ticket=%I64u reason=%s", (long)ticket, err));
      return false;
   }

   double oldSL = curSL;
   SLD_RegisterOrRefresh(ticket);
   
   Print(StringFormat("[SL UPDATE] %s ticket=%I64u old=%.*f new=%.*f reason=%s",
      symbol,
      (long)ticket,
      digits, oldSL,
      digits, candidateSL,
      reason));
   
   return true;
}

bool MovePositionToBE(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long type = PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point<=0) return false;

   int protPts = MathMax(0, g_be_protect_pts);
   double protectDist = (double)protPts * point;

   double candidateSL = 0.0;
   if(type == POSITION_TYPE_BUY) candidateSL = open + protectDist;
   else if(type == POSITION_TYPE_SELL) candidateSL = open - protectDist;
   else return false;

   candidateSL = NormalizeDouble(candidateSL, digits);
   return TryPromoteSL(ticket, candidateSL, "MANUAL_BE");
}

void AutoMovePositionsToBE(const string symbol)
{
   if(!PositionSelect(symbol)) return;

   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   long type = PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double curTP = PositionGetDouble(POSITION_TP);

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return;

   int stopsLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int safeProtectPts = g_be_protect_pts;
   if(stopsLevelPts > 0)
      safeProtectPts = MathMax(safeProtectPts, stopsLevelPts + 2);

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(point<=0) return;

   double protectDist = (double)safeProtectPts * point;
   double totalTPDistance = MathAbs(curTP - open);
   if(totalTPDistance <= 0) return;

   double move = 0.0;
   double candidateSL = 0.0;
   if(type == POSITION_TYPE_BUY)
   {
      move = (bid - open);
      candidateSL = open + protectDist;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      move = (open - ask);
      candidateSL = open - protectDist;
   }
   else return;

   double progress = move / totalTPDistance;
   if(progress < BE_TriggerPercent) return;

   candidateSL = NormalizeDouble(candidateSL, digits);
   TryPromoteSL(ticket, candidateSL, "AUTO_BE");
}

bool CancelAllPendingForSymbol(const string symbol, string &out)
{
   int deleted=0, failed=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol) continue;

      long type = (long)OrderGetInteger(ORDER_TYPE);
      bool isPending =
         (type==ORDER_TYPE_BUY_LIMIT  || type==ORDER_TYPE_SELL_LIMIT ||
          type==ORDER_TYPE_BUY_STOP   || type==ORDER_TYPE_SELL_STOP  ||
          type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending) continue;

      if(trade.OrderDelete(tk)) deleted++;
      else failed++;
   }

   out = StringFormat("CANCEL %s pending: deleted=%d failed=%d", symbol, deleted, failed);
   return (deleted>0 && failed==0);
}

bool CloseAllPositionsForSymbol(const string symbol, string &out)
{
   int closed=0, failed=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

      if(trade.PositionClose(ticket)) closed++;
      else failed++;
   }

   out = StringFormat("CLOSE %s positions: closed=%d failed=%d", symbol, closed, failed);
   return (failed==0 && closed>0);
}

void MakeButton(string name, string text, int x, int y, int w=80, int h=22)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

void MakeLabel(string name, int x, int y, int fontsize=10)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontsize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, "");
}

void SetLabelText(string name, string txt)
{
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
}

void UI_Init()
{
   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int yBtn = 30, yLbl = 50;
   int btnW = 70, btnH = 22, spacing = 10;

   int totalWidth = (btnW * 5) + (spacing * 4);
   int startX = (chartWidth - totalWidth) / 2;
   if(startX < 10) startX = 10;

    int x = startX;
    
    // BUY extremo izquierdo
    MakeButton(BTN_FBUY,   "BUY",      x, yBtn, btnW, btnH); x += btnW + spacing;
    
    // centro
    MakeButton(BTN_BE,     "BE",       x, yBtn, btnW, btnH); x += btnW + spacing;
    MakeButton(BTN_CLOSE,  "CLOSE",    x, yBtn, btnW, btnH); x += btnW + spacing;
    MakeButton(BTN_CANCEL, "CANCEL",   x, yBtn, btnW, btnH); x += btnW + spacing;
    
    // SELL extremo derecho
    MakeButton(BTN_FSELL,  "SELL",     x, yBtn, btnW, btnH);

   MakeLabel(LBL_STATUS, 10, yLbl, 10);
   ObjectSetInteger(0, LBL_STATUS, OBJPROP_COLOR, clrTomato);
   SetLabelText(LBL_STATUS, "");
   g_lastStatusText = "";
}

void UI_Ensure()
{
   if(ObjectFind(0, LBL_STATUS) < 0 || ObjectFind(0, BTN_CLOSE) < 0 ||
      ObjectFind(0, BTN_BE) < 0 || ObjectFind(0, BTN_CANCEL) < 0 ||
      ObjectFind(0, BTN_FBUY) < 0 || ObjectFind(0, BTN_FSELL) < 0)
      UI_Init();
}

int OnInit()
{
   string err="";
   LoadMasterSize(err);

   string mcErr="";
   if(!LoadMasterControl(mcErr))
      Print("[MASTER CONTROL] ", mcErr);

   // detectar server real
   BrokerProfile = AccountInfoString(ACCOUNT_SERVER);
   
   // opcional: limpiar espacios raros
   StringTrimLeft(BrokerProfile);
   StringTrimRight(BrokerProfile);
   
   Print("AUTO BrokerProfile: ", BrokerProfile);
   
   if(!LoadBroker(BrokerProfile, err))
   {
      Print("LoadBroker ERROR: ", err);
      return(INIT_FAILED);
   }
   //  detectar asset del grafico
   if(!LoadAsset(AssetProfile, err))   { Print("LoadAsset ERROR: ", err);  return(INIT_FAILED); }
   
   // validar tipo de plataforma
   if(!ValidateEnvironment(err))       { Print("ENV ERROR: ", err);        return(INIT_FAILED); }

   g_envValid = true;
   UI_Init();
   DetectFillingMode();

   string schedErr="";
   if(!LoadSchedule(schedErr))
      Print("[SCHEDULE] ", schedErr);

   string riskErr="";
   if(!LoadRiskLimits(riskErr))
      Print("[ RISK ] ", riskErr);
      
   ArrayInitialize(g_trailTickets, 0);
   ArrayInitialize(g_trailInitialSL, 0.0);
   ArrayInitialize(g_trailTranche, -1);

   EventSetTimer(2);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(reason==REASON_CHARTCHANGE) return;
   EventKillTimer();

   ObjectDelete(0, BTN_BE);
   ObjectDelete(0, BTN_FBUY);
   ObjectDelete(0, BTN_FSELL);
   ObjectDelete(0, BTN_CLOSE);
   ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, LBL_STATUS);
   Comment("");
}

void ProcessReloads()
{
   CheckMasterReload();
   CheckRiskReload();
   CheckAndReload();
}

bool ProcessBlockingState()
{
   bool scheduleBlocked = IsBlockedNow();
   bool riskBlocked     = IsRiskBlocked();
   if(scheduleBlocked)
   {
      ObjectSetInteger(0, LBL_STATUS, OBJPROP_COLOR, clrOrange);
      SetLabelText(LBL_STATUS, "BLOQUEADO POR HORARIO");

      if(!g_wasBlocked)
      {
         if(FastOrderIsAlive())
         {
            trade.OrderDelete(g_fastTicket);
            g_fastTicket = 0;
         }

         string msg1="";
         CancelAllPendingForSymbol(_Symbol, msg1);
         Print("BLOCK ENTRY: ", msg1);
      }
      g_wasBlocked = true;

      // CRITICO: bloquear entradas NO significa apagar protecciÃ³n SL
      if(PositionSelect(_Symbol))
      {
         ulong tk = (ulong)PositionGetInteger(POSITION_TICKET);
         SLD_RegisterOrRefresh(tk);
         SLD_EnforceSymbol(_Symbol);
      }

      SLD_Cleanup();
      return true;
   }

   if(riskBlocked)
   {
      ObjectSetInteger(0, LBL_STATUS, OBJPROP_COLOR, clrOrange);
      SetLabelText(LBL_STATUS, "RISK BLOCK: NEW ENTRIES DISABLED");
   }

   g_wasBlocked = false;
   return false;
}

void ProcessFastOrders()
{
   UI_Ensure();
   RefreshFastOrder();
}

void ProcessOpenPositionProtection()
{
   if(PositionSelect(_Symbol))
   {
      ulong tk = (ulong)PositionGetInteger(POSITION_TICKET);
      double curSL = PositionGetDouble(POSITION_SL);

      SLD_RegisterOrRefresh(tk);

    if(curSL > 0.0 && Trail_Find(tk) < 0)
    Trail_Register(tk, curSL);

      ApplySmartTrailing(_Symbol);
      SLD_EnforceSymbol(_Symbol);
   }
   SLD_Cleanup();
}

void ProcessUIStatus()
{
   if(!g_showStatus)
   {
      SetLabelText(LBL_STATUS, "");
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   string levelsTxt = "";
   if(bid > 0 && ask > 0)
   {
      double adjusted_sl_pts = g_sl_pts * SL_Multiplier;
      double slDist = adjusted_sl_pts * _Point;
      double buySL  = bid - slDist;
      double sellSL = ask + slDist;
      levelsTxt = StringFormat(" | L>%.2f / S<%.2f", buySL, sellSL);
   }

   double displayLots = NormalizeLot(ResolveLotSize());
   string txt = _Symbol +
                " | Lots: " + DoubleToString(displayLots,2) +
                " | RR: " + DoubleToString(RR,2) + levelsTxt;

   if(txt != g_lastStatusText)
   {
      SetLabelText(LBL_STATUS, txt);
      g_lastStatusText = txt;
   }
}

string TradeHistoryISOTime(datetime t)
{
   MqlDateTime tm;
   TimeToStruct(t, tm);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d",
                       tm.year, tm.mon, tm.day, tm.hour, tm.min, tm.sec);
}

bool HasClosedTradeTicket(ulong dealTicket)
{
   int total = ArraySize(g_closedTrades);
   for(int i = 0; i < total; i++)
   {
      if(g_closedTrades[i].deal_ticket == dealTicket)
         return true;
   }
   return false;
}

void AppendClosedTradeRecord(ulong dealTicket, datetime closeTime, double profit, double commission, double swap, string symbol)
{
   int idx = ArraySize(g_closedTrades);
   ArrayResize(g_closedTrades, idx + 1);

   g_closedTrades[idx].deal_ticket = dealTicket;
   g_closedTrades[idx].close_time = closeTime;
   g_closedTrades[idx].profit = profit;
   g_closedTrades[idx].commission = commission;
   g_closedTrades[idx].swap = swap;
   g_closedTrades[idx].symbol = symbol;

   if(ArraySize(g_closedTrades) > 1000)
   {
      int total = ArraySize(g_closedTrades);
      for(int i = 1; i < total; i++)
         g_closedTrades[i - 1] = g_closedTrades[i];
      ArrayResize(g_closedTrades, total - 1);
   }
}

bool CollectClosedTrades(bool fullRebuild)
{
   static datetime last_processed_time = 0;
   datetime to = TimeCurrent();
   datetime from = to - 86400 * 30;

   if(!HistorySelect(from, to))
      return false;

   int totalDeals = HistoryDealsTotal();
   bool changed = fullRebuild;
   ulong newestTicket = g_lastClosedDealTicket;
   datetime newestProcessedTime = last_processed_time;

   if(fullRebuild)
   {
      ArrayResize(g_closedTrades, 0);
      newestTicket = 0;
      last_processed_time = 0;
      newestProcessedTime = 0;
   }

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      long entryType = (long)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT)
         continue;

      datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      if(!fullRebuild && last_processed_time > 0 && closeTime < last_processed_time)
         continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);

      AppendClosedTradeRecord(dealTicket, closeTime, profit, commission, swap, symbol);
      changed = true;

      if(dealTicket > newestTicket)
         newestTicket = dealTicket;
      if(closeTime > newestProcessedTime)
         newestProcessedTime = closeTime;
   }

   g_lastClosedDealTicket = newestTicket;
   last_processed_time = newestProcessedTime;
   return changed;
}

void UpdateTradeHistoryJSON()
{
   datetime now = TimeCurrent();
   if(g_lastTradeHistoryUpdate != 0 && (now - g_lastTradeHistoryUpdate) < 5)
      return;

   g_lastTradeHistoryUpdate = now;

   bool fullRebuild = (ArraySize(g_closedTrades) == 0);
   bool changed = CollectClosedTrades(fullRebuild);
   //if(!changed)
   //   return;

   string json = "{\n";
   json += "  \"terminal_id\": \"test_01\",\n";
   json += "  \"trades\": [\n";

   int total = ArraySize(g_closedTrades);
   for(int i = 0; i < total; i++)
   {
      json += "    {\n";
      json += StringFormat("      \"close_time\": \"%s\",\n", TradeHistoryISOTime(g_closedTrades[i].close_time));
      json += StringFormat("      \"profit\": %.2f,\n", g_closedTrades[i].profit);
      json += StringFormat("      \"commission\": %.2f,\n", g_closedTrades[i].commission);
      json += StringFormat("      \"swap\": %.2f,\n", g_closedTrades[i].swap);
      json += StringFormat("      \"symbol\": \"%s\"\n", g_closedTrades[i].symbol);
      json += "    }";

      if(i < total - 1)
         json += ",";
      json += "\n";
   }

   json += "  ]\n";
   json += "}";

   string stateDir = "runtime\\terminals\\test_01\\tradeAssistant";
   FolderCreate("runtime");
   FolderCreate("runtime\\terminals");
   FolderCreate("runtime\\terminals\\test_01");
   FolderCreate(stateDir);

   int h = FileOpen(stateDir + "\\status_trades.json", FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   FileWriteString(h, json);
   FileClose(h);
}

void ExportState()
{
   RM_UpdateRuntime();

   double lot = NormalizeLot(ResolveLotSize());
   double rr = RR;
   int slPts = g_sl_pts;
   int spread = g_max_spread;

   double dailyLimitPct = g_max_daily_loss_pct;
   double dailyUsedPct = RM_GetDailyLossPct();

   bool scheduleBlocked = IsBlockedNow();
   bool riskBlocked = IsRiskBlocked();
   bool tradingEnabled = (!scheduleBlocked && !riskBlocked);
   string blockReason = "NONE";

   if(scheduleBlocked && riskBlocked)
      blockReason = "BOTH";
   else if(riskBlocked)
      blockReason = "RISK";
   else if(scheduleBlocked)
      blockReason = "SCHEDULE";

   string json = "{\n";
   json += "  \"config\": {\n";
   json += StringFormat("    \"lot\": %.2f,\n", lot);
   json += StringFormat("    \"rr\": %.2f,\n", rr);
   json += StringFormat("    \"sl_pts\": %d,\n", slPts);
   json += StringFormat("    \"spread\": %d\n", spread);
   json += "  },\n";
   json += "  \"risk\": {\n";
   json += StringFormat("    \"daily_limit_pct\": %.2f,\n", dailyLimitPct);
   json += StringFormat("    \"daily_used_pct\": %.2f\n", dailyUsedPct);
   json += "  },\n";
   json += "  \"status\": {\n";
   json += StringFormat("    \"trading_enabled\": %s,\n", tradingEnabled ? "true" : "false");
   json += StringFormat("    \"block_reason\": \"%s\"\n", blockReason);
   json += "  }\n";
   json += "}";

   string stateDir = "runtime\\terminals\\test_01\\TradeAssistant";
   FolderCreate("runtime");
   FolderCreate("runtime\\terminals");
   FolderCreate("runtime\\terminals\\test_01");
   FolderCreate(stateDir);

   int h = FileOpen(stateDir + "\\state.json", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   FileWriteString(h, json);
   FileClose(h);
}

void OnTimer()
{
    ProcessReloads();
    // ProcessExternalAction();
    Trail_Cleanup();
    if(ProcessBlockingState()) return;
    ProcessFastOrders();
    ProcessOpenPositionProtection();
    ProcessUIStatus();
    ExportState();
    UpdateTradeHistoryJSON();
}

void OnTick()
{
   CheckAndReloadMasterControl();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!g_envValid)
   {
      Print("Blocked: invalid environment");
      return;
   }

    if(IsBlockedNow())
    {
       ObjectSetInteger(0, LBL_STATUS, OBJPROP_COLOR, clrOrange);
       SetLabelText(LBL_STATUS, "BLOQUEADO POR HORARIO");
       return;
    }

   if(id==CHARTEVENT_CHART_CHANGE)
   {
      UI_Init();
      g_lastStatusText = "";
      return;
   }

   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   if(sparam==BTN_FBUY || sparam==BTN_FSELL)
   {
      string reason = "";
      if(!IsEnabled(reason))
      {
         Print("MASTER CONTROL BLOCK: ", reason);
         return;
      }

      if(IsBlockedNow())
      {
         Print("FAST BLOCKED BY SCHEDULE");
         return;
      }
      if(IsRiskBlocked())
      {
         Print("FAST BLOCKED BY RISK");
         return;
      }
        
      if(PositionSelect(_Symbol)) { Print("Blocked: Position already open"); return; }

      bool isBuy = (sparam==BTN_FBUY);
      if(FastOrderIsAlive())
      {
         trade.OrderDelete(g_fastTicket);
         g_fastTicket = 0;
      }

      double entry=0, sl=0, tp=0, lots=0;
      if(!GetMidEntry(isBuy, entry)) { Print("FAST: Cannot get mid entry."); return; }
      if(!BuildOrder(isBuy, entry, sl, tp, lots, reason)) { Print("FAST BuildOrder blocked: ", reason); return; }
      if(!CanOpenNewPosition(entry, sl, lots))
      {
         Print("[ RISK ] Order rejected: projected loss exceeds limit");
         return;
      }

      ulong tk=0;
      if(!SendFastLimit(isBuy, lots, entry, sl, tp, reason, tk)) { Print("FAST Send blocked: ", reason); return; }

      g_fastTicket = tk;
      g_fastIsBuy = isBuy;
      g_fastLastRpl = TimeCurrent();

      Print(StringFormat("SENT %s FAST LIMIT lots=%.2f ENTRY=%.*f SL=%.*f TP=%.*f ticket=%I64u",
            isBuy?"BUY":"SELL", lots, _Digits, entry, _Digits, sl, _Digits, tp, (long)g_fastTicket));
      return;
   }

   if(sparam==BTN_BE)
   {
      if(!PositionSelect(_Symbol))
      {
         Print("BE: no open positions on this symbol");
         return;
      }

      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      if(MovePositionToBE(ticket))
         Print("BE: done");
      else
         Print("BE: skipped");
      return;
   }

   if(sparam==BTN_CANCEL)
   {
      if(FastOrderIsAlive())
      {
         trade.OrderDelete(g_fastTicket);
         g_fastTicket = 0;
      }

      string msg="";
      CancelAllPendingForSymbol(_Symbol, msg);
      Print(msg);
      return;
   }

   if(sparam==BTN_CLOSE)
   {
      if(FastOrderIsAlive())
      {
         trade.OrderDelete(g_fastTicket);
         g_fastTicket = 0;
      }

      string msg="";
      if(!CloseAllPositionsForSymbol(_Symbol, msg)) Print("CLOSE: ", msg);
      else Print(msg);
      return;
   }
}
