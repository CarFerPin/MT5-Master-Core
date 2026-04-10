//+------------------------------------------------------------------+
//| TradeAssistant_Scalp.mq5                                         |
//| Manual trade assistant   | MULTIASSET VERSION
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#define MAX_TRAIL_TRACK 100

#include <Trade/Trade.mqh>
#include <SLDiscipline.mqh>
#include <Schedule.mqh>
#include <RiskManager.mqh>
#include <MasterSize.mqh>
CTrade trade;

enum ENV_TYPE { ENV_DEMO=0, ENV_REAL=1, ENV_PROP=2 };

string BrokerProfile = "";
input string AssetProfile  = "US500";

input double ManualSize = 0.0;
input double RR   = 1.5;
input double SL_Multiplier = 1.0;
input double BE_TriggerPercent = 0.65;
input int MinRefreshDistancePts = 2;

long g_login;
string g_server;
ENV_TYPE g_env = ENV_DEMO;
double g_size_multiplier;

double g_full_size;
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

   Print("Opening broker file: ", path);

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

      Print("KEY: ", key, " VAL: ", val);

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

   Print("FINAL BROKER CONFIG: login=", g_login,
         " server=", g_server,
         " env=", g_env,
         " multiplier=", g_size_multiplier);

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

   // CSV con delimitador '='
   int h = FileOpen(path, FILE_READ | FILE_CSV | FILE_ANSI, '=');
   if(h == INVALID_HANDLE)
   {
      err = "Cannot open asset file: " + path;
      return false;
   }

   Print("Opening file: ", path);
   Print("FILE OPEN OK");

   // reset defensivo
   g_full_size      = 0.0;
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

      Print("KEY: ", key, " VAL: ", val);

      if(key=="full_size")            g_full_size      = StringToDouble(val);
      else if(key=="sl_pts")          g_sl_pts         = (int)StringToInteger(val);
      else if(key=="max_spread_pts")  g_max_spread     = (int)StringToInteger(val);
      else if(key=="entry_offset_pts")g_entry_offset   = (int)StringToInteger(val);
      else if(key=="min_sl_pts")      g_min_sl         = (int)StringToInteger(val);
      else if(key=="max_sl_pts")      g_max_sl         = (int)StringToInteger(val);
      else if(key=="slippage")        g_slippage       = (int)StringToInteger(val);
      else if(key=="be_protect_pts")  g_be_protect_pts = (int)StringToInteger(val);
   }

   FileClose(h);

   if(g_full_size <= 0 || g_sl_pts <= 0 || g_max_spread <= 0)
   {
      err = StringFormat("Invalid asset config | full_size=%.2f sl_pts=%d max_spread=%d",
                         g_full_size, g_sl_pts, g_max_spread);
      return false;
   }

   Print("FINAL CONFIG: ",
         " size=", g_full_size,
         " sl=", g_sl_pts,
         " spread=", g_max_spread,
         " offset=", g_entry_offset,
         " min_sl=", g_min_sl,
         " max_sl=", g_max_sl,
         " slippage=", g_slippage,
         " be_protect=", g_be_protect_pts);

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

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double move = 0.0;
   if(type == POSITION_TYPE_BUY)
      move = bid - open;
   else if(type == POSITION_TYPE_SELL)
      move = open - ask;
   else
      return;

   if(move <= 0.0) return;

   double total = MathAbs(tp - open);
   if(total <= 0.0) return;

   double progress = move / total;

   int tranche = -1;
   if(progress >= 0.2 && progress < 0.35) tranche = 0;
   else if(progress >= 0.35 && progress < 0.5) tranche = 1;
   else if(progress >= 0.5 && progress < 0.7) tranche = 2;
   else if(progress >= 0.7 && progress < 0.9) tranche = 3;
   else if(progress >= 0.9) tranche = 4;
   else return;

   int lastTranche = Trail_GetTranche(ticket);
   if(tranche <= lastTranche)
      return;

   double factors[5] = {0.20, 0.30, 0.35, 0.42, 0.50};
   double targetFactor = factors[tranche];

   double initialSL = 0.0;
   if(!Trail_GetInitialSL(ticket, initialSL))
      return;

   double candidateSL = 0.0;

   if(type == POSITION_TYPE_BUY)
   {
      double risk = open - initialSL;
      if(risk <= 0.0) return;

      double profit = bid - open;
      double protectedAmount = targetFactor * (risk + profit);
      candidateSL = initialSL + protectedAmount;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      double risk = initialSL - open;
      if(risk <= 0.0) return;

      double profit = open - ask;
      double protectedAmount = targetFactor * (risk + profit);
      candidateSL = initialSL - protectedAmount;
   }
   else
      return;

   candidateSL = NormalizeDouble(candidateSL, digits);

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
   if(ManualSize > 0.0)
      return ManualSize;

   double baseSize = (g_masterSize > 0.0)
                     ? g_masterSize
                     : g_full_size;

   return baseSize * g_size_multiplier;
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

   if(raw_lot < vmin || raw_lot > vmax)
   {
      reason = "Invalid lot (out of broker limits)";
      return false;
   }

   lots = NormalizeDouble(MathFloor(raw_lot / vstep) * vstep, 2);
   int volDigits = (int)MathRound(-MathLog10(vstep));
   lots = NormalizeDouble(lots, volDigits);

   if(lots <= 0)
   {
      reason = "Invalid lots after normalization";
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

   double displayLots = ResolveLotSize();
   string txt = _Symbol +
                " | Lots: " + DoubleToString(displayLots,2) +
                " | RR: " + DoubleToString(RR,2) + levelsTxt;

   if(txt != g_lastStatusText)
   {
      SetLabelText(LBL_STATUS, txt);
      g_lastStatusText = txt;
   }
}

void OnTimer()
{
    ProcessReloads();
    Trail_Cleanup();
    if(ProcessBlockingState()) return;
    ProcessFastOrders();
    ProcessOpenPositionProtection();
    ProcessUIStatus();
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
      string reason="";
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
