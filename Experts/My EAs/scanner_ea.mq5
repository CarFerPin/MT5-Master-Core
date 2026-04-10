#property strict
#property version   "1.00"
#property description "Lightweight scanner orchestration EA"

#include <Alerts System/scanner_engine.mqh>
#include <Alerts System/signal_formatter.mqh>

input string TELEGRAM_BOT_TOKEN = "1750377600:AAExrEl_E6wckGfwHGy-bobtjJWMOuz_A_I";
input string TELEGRAM_CHAT_ID   = "1723491813";

#include <Alerts System/telegram_api.mqh>
#include <Alerts System/telemetry.mqh>

//--------------------------------------------------------------
// GLOBAL STATE
//--------------------------------------------------------------

static datetime last_signal_time[10][3];
static datetime last_bar_time[10][3];

//--------------------------------------------------------------
// HELPERS
//--------------------------------------------------------------
struct ActiveSignal
{
   string symbol;
   ENUM_TIMEFRAMES tf;
   int direction;
   double score;
   datetime time;
};

ActiveSignal active_signals[50];
int active_count=0;

string DirectionLabel(const int direction)
{
   if(direction == 1)  return "Bullish";
   if(direction == -1) return "Bearish";
   return "Unknown";
}

//--------------------------------------------------------------

string TimeframeLabel(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_H1:  return "H1";
   }

   return EnumToString(tf);
}

//--------------------------------------------------------------

void PrintSignal(const ScannerEngine::MarketSignal &signal)
{
   PrintFormat(
      "SIGNAL | %s | %s | %s | %s | score=%.1f | %.2f | %s",
      signal.symbol,
      TimeframeLabel(signal.timeframe),
      signal.type,
      DirectionLabel(signal.direction),
      signal.score,
      signal.price,
      TimeToString(signal.time, TIME_DATE | TIME_MINUTES)
   );
}

//--------------------------------------------------------------
int CountConfluence(const ScannerEngine::MarketSignal &signal)
{
   int count=1;

   for(int i=0;i<active_count;i++)
   {
      if(active_signals[i].symbol==signal.symbol &&
         active_signals[i].direction==signal.direction &&
         active_signals[i].tf != signal.timeframe)
      {
         count++;
      }
   }

   return count;
}

//--------------------------------------------------------------
double ApplyMTFConfluence(double score,int tf_count)
{
   double multiplier=1.0;

   if(tf_count==2)
      multiplier=1.30;

   if(tf_count>=3)
      multiplier=1.65;

   score*=multiplier;

   if(score>100)
      score=100;

   return score;
}

//--------------------------------------------------------------
void RegisterSignal(const ScannerEngine::MarketSignal &signal)
{
   if(active_count>=50)
      return;

   active_signals[active_count].symbol = signal.symbol;
   active_signals[active_count].tf = signal.timeframe;
   active_signals[active_count].direction = signal.direction;
   active_signals[active_count].score = signal.score;
   active_signals[active_count].time = signal.time;

   active_count++;
}

//--------------------------------------------------------------
void CleanupExpiredSignals()
{
   datetime now=TimeCurrent();

   for(int i=active_count-1;i>=0;i--)
   {
      int tf_seconds=PeriodSeconds(active_signals[i].tf);

      if(now-active_signals[i].time > tf_seconds*3)
      {
         for(int j=i;j<active_count-1;j++)
            active_signals[j]=active_signals[j+1];

         active_count--;
      }
   }
}

//--------------------------------------------------------------
// INIT
//--------------------------------------------------------------

int OnInit()
{
   const int symbol_count = ArraySize(ScannerEngine::MONITORED_SYMBOLS);
   const int tf_count     = ArraySize(ScannerEngine::MONITORED_TIMEFRAMES);
   
   active_count = 0;
   
   for(int s=0; s<symbol_count; s++)
   {
      for(int t=0; t<tf_count; t++)
      {
         string symbol = ScannerEngine::MONITORED_SYMBOLS[s];
         ENUM_TIMEFRAMES tf = ScannerEngine::MONITORED_TIMEFRAMES[t];
   
         datetime bar_time[];
   
         if(CopyTime(symbol,tf,0,1,bar_time)>0)
            last_bar_time[s][t] = bar_time[0];
      }
   }
    
   for(int i=0;i<ArraySize(ScannerEngine::MONITORED_SYMBOLS);i++)
   {
      string s = ScannerEngine::MONITORED_SYMBOLS[i];
   
      if(SymbolSelect(s,true))
         Print("SYMBOL OK: ", s);
      else
         Print("SYMBOL NOT FOUND: ", s);
   }

   for(int s=0; s<symbol_count; s++)
   {
      SymbolSelect(ScannerEngine::MONITORED_SYMBOLS[s], true);

      for(int t=0; t<tf_count; t++)
      {
         last_signal_time[s][t] = 0;
         last_bar_time[s][t]    = 0;
      }
   }

   EventSetTimer(60);

   Print("Scanner EA started.");

   return(INIT_SUCCEEDED);
}

//--------------------------------------------------------------
// DEINIT
//--------------------------------------------------------------

void OnDeinit(const int reason)
{
   EventKillTimer();
   ScannerEngine::ReleaseScannerHandles();

   Print("Scanner EA stopped.");
}

//--------------------------------------------------------------
// TIMER LOOP
//--------------------------------------------------------------

void OnTimer()
{
   const int symbol_count = ArraySize(ScannerEngine::MONITORED_SYMBOLS);
   const int tf_count     = ArraySize(ScannerEngine::MONITORED_TIMEFRAMES);

   for(int s=0; s<symbol_count; s++)
   {
      const string symbol = ScannerEngine::MONITORED_SYMBOLS[s];

      for(int t=0; t<tf_count; t++)
      {
         const ENUM_TIMEFRAMES tf =
            ScannerEngine::MONITORED_TIMEFRAMES[t];

         //--------------------------------------------------
         // NEW BAR DETECTION
         //--------------------------------------------------

         datetime bar_time[];

         if(CopyTime(symbol, tf, 0, 1, bar_time) < 1)
            continue;

         if(bar_time[0] == last_bar_time[s][t])
            continue;

         last_bar_time[s][t] = bar_time[0];

         //--------------------------------------------------
         // RUN SCANNER
         //--------------------------------------------------

         ScannerEngine::MarketSignal signal;

         if(!ScannerEngine::ScanSymbolTimeframe(symbol, tf, signal))
            continue;
            
         datetime now = TimeTradeServer();

         int tf_seconds = PeriodSeconds(tf);
         
         // ignorar señales que no sean recientes (máx 1.5 vela)
         if(now - signal.time > tf_seconds*1.5)
            continue;

         //--------------------------------------------------
         // ANTI-SPAM SIGNAL CONTROL
         //--------------------------------------------------

         if(signal.time <= last_signal_time[s][t])
            continue;

         last_signal_time[s][t] = signal.time;

         CleanupExpiredSignals();
         
         int confluence_count = CountConfluence(signal);

         signal.score = ApplyMTFConfluence(signal.score,confluence_count);

         RegisterSignal(signal);
         
         PrintSignal(signal);
         SendSignalTelemetry(signal);
      }
   }
}