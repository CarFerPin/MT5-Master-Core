//+------------------------------------------------------------------+
//| TradeAssistant_Scalp.mq5                                         |
//| Manual trade assistant   | BITCOIN VERSION
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#include <Trade/Trade.mqh>
#include <My Includes/SLDiscipline.mqh>
CTrade trade;

// ---- ENV DECLARATION ----
enum ENV_TYPE { ENV_DEMO=0, ENV_REAL=1, ENV_PROP=2 };

// --------------------------- INPUTS --------------------------------
input double   Lots = 0.5;
input double   RR   = 1.5;
input int      SL_Pts = 50000;   // Stop Loss Distance

input long     ExpectedLogin   = 541140160;
input string   ExpectedServer  = "FTMO-Server4";
input ENV_TYPE ExpectedEnv     = ENV_REAL;

input double   BE_TriggerPercent      = 0.4;   // % recorrido hacia TP para BE
input int      BE_ProtectPts          = 1500;

input int      Slippage               = 1000;         // Slippage

// --- BLOQUEO HORARIO (HORA BROKER) ---
input bool   UseTimeBlock      = true;

input int    Block1_StartHour  = 7;
input int    Block1_StartMin   = 25;
input int    Block1_EndHour    = 7;
input int    Block1_EndMin     = 35;

input int    Block2_StartHour  = 8;
input int    Block2_StartMin   = 30;
input int    Block2_EndHour    = 8;
input int    Block2_EndMin     = 35;

// --------------------------- GLOBALS ---------------------------
ENV_TYPE g_env = ENV_DEMO;
bool     g_envValid = false;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;

bool g_forcedFlatDone = false;
bool g_wasBlocked     = false;
int g_lastConfigLoadDay = -1;

// --------------------------- BITCOIN SETTINGS ---------------------------
#define BTC_MAX_SPREAD_PTS  800
#define BTC_ENTRY_OFFSET_PTS 150

#define BTC_MIN_SL_POINTS   5000   // hard safety
#define BTC_MAX_SL_POINTS   150000

// --------------------------- SIMPLE UI -----------------------------
string BTN_BUY="TA_BUY", BTN_SELL="TA_SELL", BTN_BE="TA_BE";
string BTN_CANCEL="TA_CANCEL";
string BTN_CLOSE="TA_CLOSE"; // Close positions market
string BTN_FBUY="TA_FastBUY", BTN_FSELL="TA_FastSELL"; // Fast/Aggressive

string LBL_STATUS="TA_STATUS";
string g_lastStatusText = "";

bool   g_showStatus=true;

// ------------------------ FAST ORDER STATE -------------------------
ulong    g_fastTicket   = 0;
bool     g_fastIsBuy    = true;
datetime g_fastLastRpl  = 0;

// --------------------------- HELPERS --------------------------------
// Determina el modo de ejecución permitido por el broker
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
   long   login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(ExpectedLogin <= 0 || ExpectedServer == "")
   {
      reason = "ENV not declared in inputs";
      return false;
   }

   if(login != ExpectedLogin || server != ExpectedServer)
   {
      reason = "Account mismatch (login/server)";
      return false;
   }

   if(ExpectedEnv == ENV_DEMO && mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      reason = "Expected DEMO but broker reports REAL";
      return false;
   }

   if((ExpectedEnv == ENV_REAL || ExpectedEnv == ENV_PROP) &&
       mode != ACCOUNT_TRADE_MODE_REAL)
   {
      reason = "Expected REAL/PROP but broker reports DEMO";
      return false;
   }

   g_env = ExpectedEnv;
   return true;
}

string EnvToString()
{
   if(g_env == ENV_DEMO) return "DEMO";
   if(g_env == ENV_REAL) return "REAL";
   if(g_env == ENV_PROP) return "PROP";
   return "UNKNOWN";
}

// Lectura de archivo externo con ventanas de tiempo para bloqueo (news events)
bool ParseTimeToMinutes(string hhmm, int &outMin)
{
   string parts[];
   if(StringSplit(hhmm, ':', parts) != 2)
      return false;

   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);

   if(h < 0 || h > 23 || m < 0 || m > 59)
      return false;

   outMin = h * 60 + m;
   return true;
}

int GetBrokerOffsetMinutes()
{
   datetime server = TimeCurrent();
   datetime local  = TimeLocal();
   return (int)((server - local) / 60);
}


bool IsWithinBlockedSession()
{
   if(!UseTimeBlock)
      return false;

   int offset = GetBrokerOffsetMinutes();

   // Hora actual broker
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);
   int nowMin = tm.hour * 60 + tm.min;

   // Convertimos inputs LOCAL → BROKER
   int s1 = Block1_StartHour * 60 + Block1_StartMin + offset;
   int e1 = Block1_EndHour   * 60 + Block1_EndMin   + offset;

   int s2 = Block2_StartHour * 60 + Block2_StartMin + offset;
   int e2 = Block2_EndHour   * 60 + Block2_EndMin   + offset;

   s1 = (s1 + 1440) % 1440;
   e1 = (e1 + 1440) % 1440;
   s2 = (s2 + 1440) % 1440;
   e2 = (e2 + 1440) % 1440;

   // Ventana 1
   if(s1 <= e1)
   {
      if(nowMin >= s1 && nowMin <= e1)
         return true;
   }
   else
   {
      if(nowMin >= s1 || nowMin <= e1)
         return true;
   }

   // Ventana 2
   if(s2 <= e2)
   {
      if(nowMin >= s2 && nowMin <= e2)
         return true;
   }
   else
   {
      if(nowMin >= s2 || nowMin <= e2)
         return true;
   }
   

   return false;
}

// ------------------------ ORDER BUILD / SEND ------------------------
bool GetEntryPrice(bool isBuy, double &entry)
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return false;

   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick = _Point;

   int offPts = BTC_ENTRY_OFFSET_PTS;
   if(offPts < 1) offPts = 1;

   double off = (double)offPts * _Point;

   if(isBuy)
      entry = bid - off;
   else
      entry = ask + off;

   entry = MathRound(entry / tick) * tick;
   entry = NormalizeDouble(entry, _Digits);

   return (entry > 0);
}

bool BuildOrder(bool isBuy, double &entry, double &sl, double &tp, double &lots, string &reason)
{

   // Spread guard
    double spr = GetSpreadPoints(_Symbol);
    if(spr > BTC_MAX_SPREAD_PTS)
    {
       reason = StringFormat("SPREAD BLOCK: %.1f pts > max %d", spr, BTC_MAX_SPREAD_PTS);
       return false;
    }

   // --- FIXED BITCOIN SL (POINTS) ---  
    if(SL_Pts < BTC_MIN_SL_POINTS || SL_Pts > BTC_MAX_SL_POINTS)
       {
          reason = "SL points out of allowed BITCOIN range";
          return false;
       }
    
       int slPtsParaCalculo = SL_Pts; 
    
       int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
       if(stopsLevel > 0)
          slPtsParaCalculo = MathMax(slPtsParaCalculo, stopsLevel + 2);
    
       // 4. Usamos la variable nueva para calcular la distancia
       double slDist = (double)slPtsParaCalculo * _Point;
       double tpDist = slDist * RR;
    
    if(isBuy)
    {
       sl = entry - slDist;
       tp = entry + tpDist;
    }
    else
    {
       sl = entry + slDist;
       tp = entry - tpDist;
    }
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // ---------------- FIXED LOT SIZE ----------------
    double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(Lots < vmin || Lots > vmax)
    {
       reason = "Invalid Lots (out of broker limits)";
       return false;
    }
    
    // Normalize to broker step
    lots = MathFloor(Lots / vstep) * vstep;
    int volDigits = (int)MathRound(-MathLog10(vstep));
    lots = NormalizeDouble(lots, volDigits);
    
    if(lots <= 0)
    {
       reason = "Invalid lots after normalization";
       return false;
    }

   // Freeze level check (optional)
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

bool SendLimit(bool isBuy, double lots, double entry, double sl, double tp, string &reason)
{
   trade.SetTypeFilling(g_filling);
   trade.SetDeviationInPoints(Slippage);

   bool ok = isBuy ? trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "TA")
                   : trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "TA");

   if(!ok)
   {
      reason = StringFormat("OrderSend failed. ret=%d, err=%d", trade.ResultRetcode(), GetLastError());
      return false;
   }
   return true;
}

// ------------------------ FAST (MID) LIMIT -------------------------
bool GetMidEntry(bool isBuy, double &entry)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0)
      return false;

   double mid = (bid + ask) * 0.5;

   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick = _Point;

   entry = MathRound(mid / tick) * tick;
   entry = NormalizeDouble(entry, _Digits);

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;

   if(isBuy)
   {
      if(entry >= ask - minDist)
         return false;
   }
   else
   {
      if(entry <= bid + minDist)
         return false;
   }

   return (entry > 0);
}


bool SendFastLimit(bool isBuy, double lots, double entry, double sl, double tp, string &reason, ulong &outTicket)
{
   trade.SetTypeFilling(g_filling);
   trade.SetDeviationInPoints(Slippage);

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
   // si ya no está "placed/partial", lo consideramos muerto (filled/canceled/rejected/etc)
   if(st!=ORDER_STATE_PLACED && st!=ORDER_STATE_PARTIAL) return false;

   string sym = OrderGetString(ORDER_SYMBOL);
   if(sym!=_Symbol) return false;

   return true;
}

void RefreshFastOrder()
{
    if(!FastOrderIsAlive())
    {
        g_fastTicket = 0;
        return;
    }

    datetime now = TimeCurrent();
    if((now - g_fastLastRpl) < 5)
        return;

    double entry=0, sl=0, tp=0, lots=0;
    string reason="";

    if(!GetMidEntry(g_fastIsBuy, entry))
        return;

    if(!BuildOrder(g_fastIsBuy, entry, sl, tp, lots, reason))
        return;

    // INTENTAMOS ENVIAR PRIMERO
    ulong newTicket=0;
    if(!SendFastLimit(g_fastIsBuy, lots, entry, sl, tp, reason, newTicket))
        return;

    // SOLO SI SE CREÓ CORRECTAMENTE, BORRAMOS LA ANTERIOR
    if(trade.OrderDelete(g_fastTicket))
    {
        g_fastTicket  = newTicket;
        g_fastLastRpl = now;
    }
}

// ------------------------ BE (Break Even) --------------------------

bool ModifyPositionSLTP(ulong ticket, double newSL, double newTP, string &err)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

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

void AutoMovePositionsToBE(const string symbol)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return;

    // Obtenemos el nivel mínimo permitido por el broker
    int stopsLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    
    // Ajustamos los puntos de protección para que nunca sean menores al Stop Level + 2
    int safeProtectPts = BE_ProtectPts;
    if(stopsLevelPts > 0) 
       safeProtectPts = MathMax(safeProtectPts, stopsLevelPts + 2);
    
    double protectDist = (double)safeProtectPts * _Point;
    double minDist     = (double)stopsLevelPts * _Point;

   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt,"TA") < 0) continue;

      long   type   = PositionGetInteger(POSITION_TYPE);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      
      double totalDist = MathAbs(curTP - open);
      if(totalDist <= 0) continue;

      double newSL = 0.0;
      bool   canMove = false;
      double progress = 0.0;
      
      if(type == POSITION_TYPE_BUY)
      {
         progress = (bid - open) / totalDist;
         if(progress < BE_TriggerPercent) continue;
      
         newSL = open + protectDist;
      
         if(newSL >= bid - minDist) continue;
         if(curSL > 0 && newSL <= curSL) continue;
      
         canMove = true;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         progress = (open - ask) / totalDist;
         if(progress < BE_TriggerPercent) continue;
      
         newSL = open - protectDist;
      
         if(newSL <= ask + minDist) continue;
         if(curSL > 0 && newSL >= curSL) continue;
      
         canMove = true;
      }

      if(!canMove)
         continue;
      
      newSL = NormalizeDouble(newSL, _Digits);
      
      string err="";
      if(ModifyPositionSLTP(ticket, newSL, curTP, err))
      {
         // 👉 actualizar lock inmediatamente
         SLD_RegisterOrRefresh(ticket);
      }
   }
}

bool CancelAllPendingForSymbol(const string symbol, string &out)
{
   int deleted=0, failed=0;

   int total = OrdersTotal();
   for(int i=total-1; i>=0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;

      if(!OrderSelect(tk))
         continue;

      string sym = OrderGetString(ORDER_SYMBOL);
      if(sym != symbol) continue;

      long type = (long)OrderGetInteger(ORDER_TYPE);

      // Solo pendientes (limits/stops)
      bool isPending =
         (type==ORDER_TYPE_BUY_LIMIT  || type==ORDER_TYPE_SELL_LIMIT ||
          type==ORDER_TYPE_BUY_STOP   || type==ORDER_TYPE_SELL_STOP  ||
          type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending) continue;

      if(trade.OrderDelete(tk))
         deleted++;
      else
         failed++;
   }

   out = StringFormat("CANCEL %s pending: deleted=%d failed=%d", symbol, deleted, failed);
   return (deleted>0 && failed==0);
}

bool CloseAllPositionsForSymbol(const string symbol, string &out)
{
   int closed=0, failed=0;

   // Recorre desde el final por seguridad
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;

      if(!PositionSelectByTicket(ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym != symbol) continue;

      ResetLastError();
      if(trade.PositionClose(ticket))
         closed++;
      else
         failed++;
   }

   out = StringFormat("CLOSE %s positions: closed=%d failed=%d", symbol, closed, failed);
   return (failed==0 && closed>0);
}

// ---------------------------- UI -----------------------------------
void MakeButton(string name, string text, int x, int y, int w=80, int h=22)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   // Anchor bottom-left
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);      // text/border
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack);    // button background
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
   int yBtn = 30;
   int yLbl = 50;

   int btnW = 70;
   int btnH = 22;
   int spacing = 10;

   int totalWidth = (btnW * 5) + (spacing * 4);
   int startX = (chartWidth - totalWidth) / 2;
   if(startX < 10) startX = 10;

   int x = startX;

   MakeButton(BTN_BE,     "BE",       x, yBtn, btnW, btnH);  x += btnW + spacing;
   MakeButton(BTN_CLOSE,  "CLOSE",    x, yBtn, btnW, btnH);  x += btnW + spacing;
   MakeButton(BTN_CANCEL, "CANCEL",   x, yBtn, btnW, btnH);  x += btnW + spacing;
   MakeButton(BTN_FBUY,   "FastBUY",  x, yBtn, btnW, btnH);  x += btnW + spacing;
   MakeButton(BTN_FSELL,  "FastSELL", x, yBtn, btnW, btnH);

   MakeLabel(LBL_STATUS, 10, yLbl, 10);
   ObjectSetInteger(0, LBL_STATUS, OBJPROP_COLOR, clrBlue);
   SetLabelText(LBL_STATUS, "");

   g_lastStatusText = "";
}

void UI_Ensure()
{
    if(ObjectFind(0, LBL_STATUS) < 0) { UI_Init();return; }
    if(ObjectFind(0, BTN_CLOSE) < 0)  { UI_Init(); return; }
    
    if(ObjectFind(0, BTN_BE) < 0)     { UI_Init(); return; }
    if(ObjectFind(0, BTN_CANCEL) < 0) { UI_Init(); return; }
    if(ObjectFind(0, BTN_FBUY) < 0)   { UI_Init(); return; }
    if(ObjectFind(0, BTN_FSELL) < 0)  { UI_Init(); return; }


}

// -------------------------- LIFECYCLE --------------------------------
int OnInit()
{
    string envErr="";
    if(!ValidateEnvironment(envErr))
    {
       Comment("ENV ERROR: ", envErr);
       return(INIT_FAILED);
    }
    
    g_envValid = true;
    
   // --- BTC ONLY ---
   string sym = _Symbol;
   if(StringFind(sym, "BTCUSD") < 0)
   {
      Comment("ERROR: This EA is BTC-only. Current symbol: ", sym);
      return(INIT_FAILED);
   }

   g_showStatus = true;

   UI_Init();
   DetectFillingMode();
   EventSetTimer(2);
   Comment("");

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

void OnTimer()
{
   bool isBlocked = IsWithinBlockedSession();

   if(isBlocked)
   {
      ObjectSetInteger(0, LBL_STATUS, OBJPROP_COLOR, clrOrange);
      SetLabelText(LBL_STATUS, "BLOQUEADO POR HORARIO");

      // Solo al entrar en la ventana
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
      return;
   }

   // Si estamos aquí, NO está bloqueado
   g_wasBlocked = false;

   UI_Ensure();

   // ======================================================
   // SL DISCIPLINE ENGINE
   // ======================================================
   
   // 1. Registrar / refrescar posiciones del símbolo actual
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
   
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
   
      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt,"TA") < 0) continue;
      
      SLD_RegisterOrRefresh(tk);
   }
   
   // 2. Enforcement (CRÍTICO)
   SLD_Enforce();
   
   // 3. Cleanup
   SLD_Cleanup();
   
   // ======================================================
   // LÓGICA ORIGINAL
   // ======================================================
   RefreshFastOrder();
   AutoMovePositionsToBE(_Symbol);

   if(!g_showStatus)
   {
      SetLabelText(LBL_STATUS, "");
      return;
   }

   // --- CÁLCULO DINÁMICO DE NIVELES DE STOP ---
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   string levelsTxt = "";
   if(bid > 0 && ask > 0)
   {
      // Calculamos los niveles de Stop basándonos en SL_Pts e inputs actuales
      double slDist = (double)SL_Pts * _Point;
      
      // Para un Largo (Buy), el Stop estaría por debajo del Bid
      double buySL  = bid - slDist;
      // Para un Corto (Sell), el Stop estaría por encima del Ask
      double sellSL = ask + slDist;
      
      levelsTxt = StringFormat(" | L>%.2f / S<%.2f", buySL, sellSL);
   }

   string txt =
        "BTC" +
        " | Lots: " + DoubleToString(Lots,2) +
        " | RR: " + DoubleToString(RR,2) +
        levelsTxt; // Añadimos los niveles al texto final

   if(txt != g_lastStatusText)
   {
      SetLabelText(LBL_STATUS, txt);
      g_lastStatusText = txt;
   }
}


void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!g_envValid)
    {
       Print("Blocked: invalid environment");
       return;
    }
    
    if(IsWithinBlockedSession())
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


   
   // FAST BUY / FAST SELL -> MID + CXL/RPL cada 5s hasta fill
   if(sparam==BTN_FBUY || sparam==BTN_FSELL)
   {
      if(PositionSelect(_Symbol))
         {
            Print("Blocked: Position already open");
            return;
         }

      bool isBuy = (sparam==BTN_FBUY);

      // Si había una fast viva, la cancelamos y reemplazamos desde cero
      if(FastOrderIsAlive())
      {
         trade.OrderDelete(g_fastTicket);
         g_fastTicket = 0;
      }
   
      double entry=0, sl=0, tp=0, lots=0;
      string reason="";
   
      if(!GetMidEntry(isBuy, entry))
      {
         Print("FAST: Cannot get mid entry.");
         return;
      }
   
      if(!BuildOrder(isBuy, entry, sl, tp, lots, reason))
      {
         Print("FAST BuildOrder blocked: ", reason);
         return;
      }
   
      ulong tk=0;
      if(!SendFastLimit(isBuy, lots, entry, sl, tp, reason, tk))
      {
         Print("FAST Send blocked: ", reason);
         return;
      }
   
      g_fastTicket  = tk;
      g_fastIsBuy   = isBuy;
      g_fastLastRpl = TimeCurrent();
   
      Print(StringFormat("SENT %s FAST LIMIT lots=%.2f ENTRY=%.*f SL=%.*f TP=%.*f ticket=%I64u",
                         isBuy?"BUY":"SELL", lots, _Digits, entry, _Digits, sl, _Digits, tp, (long)g_fastTicket));
      return;
   }

   // BE
   if(sparam==BTN_BE)
   {
      AutoMovePositionsToBE(_Symbol);
      Print("BE: triggered");
      return;
   }
      
      // CANCEL ALL pending (this symbol)
   if(sparam==BTN_CANCEL)
   {
      // también mata la fast si existe
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
   
   // CLOSE ALL positions (this symbol) at market
    if(sparam==BTN_CLOSE)
    {
       // mata fast pending si existe
       if(FastOrderIsAlive())
       {
          trade.OrderDelete(g_fastTicket);
          g_fastTicket = 0;
       }
    
       string msg="";
       if(!CloseAllPositionsForSymbol(_Symbol, msg))
          Print("CLOSE: ", msg);
       else
          Print(msg);
       return;
    }
}