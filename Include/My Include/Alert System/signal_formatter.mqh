#ifndef SIGNAL_FORMATTER_MQH
#define SIGNAL_FORMATTER_MQH

#include "scanner_engine.mqh"

// Helper functions provided by the EA
string TimeframeLabel(const ENUM_TIMEFRAMES timeframe);
string DirectionLabel(const int direction);

string FormatSignalMessage(const ScannerEngine::MarketSignal &signal)
{
   string tf_label = TimeframeLabel(signal.timeframe);
   string dir_label = DirectionLabel(signal.direction);

   string message;

   message = signal.symbol + " " + tf_label + " " + dir_label;

   message += "\n";
   string clean_type = signal.type;
   StringReplace(clean_type,"|"," | ");

   message += clean_type;

   message += "\nScore: " + DoubleToString(signal.score,1);

   message += "\nPrice: " + DoubleToString(signal.price,2);

   // Broker date (month/day)
   MqlDateTime t;
   TimeToStruct(signal.time,t);

   string broker_date =
      IntegerToString(t.mon) + "." +
      IntegerToString(t.day);

   message += "\nBroker Date: " + broker_date;

   // Local time
   message += "\nLocal Time: " + TimeToString(TimeLocal() - (TimeCurrent() - signal.time), TIME_MINUTES);

   return message;
}

#endif