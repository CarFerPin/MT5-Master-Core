//+------------------------------------------------------------------+
//| TradeAssistant_UI.mqh                                            |
//| UI Minimal Module                                                |
//+------------------------------------------------------------------+
#property strict

// Constantes de UI
#define BTN_BUY      "TA_BUY"
#define BTN_SELL     "TA_SELL"
#define BTN_BE       "TA_BE"
#define BTN_CLOSE    "TA_CLOSE"
#define BTN_CANCEL   "TA_CANCEL"
#define BTN_FBUY     "TA_FastBUY"
#define BTN_FSELL    "TA_FastSELL"
#define LBL_STATUS   "TA_STATUS"

// Clase simple
class TradeAssistantUI {
public:
   void Initialize(string envText) {
      MakeButton(BTN_BUY,  "BUY " + envText, 10, 30);
      MakeButton(BTN_SELL, "SELL " + envText, 95, 30);
      MakeButton(BTN_BE,     "BE",      180, 30);
      MakeButton(BTN_CLOSE,  "CLOSE",   245, 30);
      MakeButton(BTN_CANCEL, "CANCEL",  320, 30);
      MakeButton(BTN_FBUY,   "FastBUY",    400, 30);
      MakeButton(BTN_FSELL,  "FastSELL",   475, 30);
      MakeLabel(LBL_STATUS, 10, 60, 10);
   }
   
   void UpdateStatus(string text) {
      if(ObjectFind(0, LBL_STATUS) >= 0) {
         ObjectSetString(0, LBL_STATUS, OBJPROP_TEXT, text);
      }
   }
   
   void CleanUp() {
      ObjectDelete(0, BTN_BUY);
      ObjectDelete(0, BTN_SELL);
      ObjectDelete(0, BTN_BE);
      ObjectDelete(0, BTN_CLOSE);
      ObjectDelete(0, BTN_CANCEL);
      ObjectDelete(0, BTN_FBUY);
      ObjectDelete(0, BTN_FSELL);
      ObjectDelete(0, LBL_STATUS);
   }
   
   bool IsUIComplete() {
      return (ObjectFind(0, BTN_BUY) >= 0);
   }
   
private:
   void MakeButton(string name, string text, int x, int y, int w=80, int h=22) {
      ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
   
   void MakeLabel(string name, int x, int y, int fontsize=10) {
      ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontsize);
      ObjectSetString(0, name, OBJPROP_TEXT, "");
   }
};

TradeAssistantUI ui;