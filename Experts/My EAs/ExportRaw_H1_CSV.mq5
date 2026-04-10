//+------------------------------------------------------------------+
//|                                       ExportRawEURUSD_H1_CSV.mq5 |
//|                                  Carlos Fernando Pinilla - 2026  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input string InpSymbol       = "EURUSD";
input ENUM_TIMEFRAMES InpTF  = PERIOD_H1;
input int    BarsToExport    = 5000;
input bool   IncludeHeader   = true;

//+------------------------------------------------------------------+
//| Script start                                                     |
//+------------------------------------------------------------------+
void OnStart()
{
   string tfName   = TimeframeToString(InpTF);
   string fileName = InpSymbol + "_" + tfName + "_RAW.csv";

   ResetLastError();
   int fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');

   if(fileHandle == INVALID_HANDLE)
   {
      Print("Error al abrir archivo: ", fileName, " | code=", GetLastError());
      return;
   }

   if(IncludeHeader)
   {
      FileWrite(fileHandle,
                "symbol",
                "time",
                "open",
                "high",
                "low",
                "close",
                "tick_volume",
                "spread",
                "real_volume");
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, false);

   ResetLastError();
   int copied = CopyRates(InpSymbol, InpTF, 0, BarsToExport, rates);

   if(copied <= 0)
   {
      Print("Error al copiar barras | code=", GetLastError());
      FileClose(fileHandle);
      return;
   }

   // Export bruto, tal cual venga de MT5
   for(int i = 0; i < copied; i++)
   {
      FileWrite(fileHandle,
                InpSymbol,
                TimeToString(rates[i].time, TIME_DATE | TIME_SECONDS),
                DoubleToString(rates[i].open,  _DigitsForSymbol(InpSymbol)),
                DoubleToString(rates[i].high,  _DigitsForSymbol(InpSymbol)),
                DoubleToString(rates[i].low,   _DigitsForSymbol(InpSymbol)),
                DoubleToString(rates[i].close, _DigitsForSymbol(InpSymbol)),
                (string)rates[i].tick_volume,
                (string)rates[i].spread,
                (string)rates[i].real_volume);
   }

   FileClose(fileHandle);

   Print("Exportación completada: ", fileName, " | barras exportadas=", copied);
   Print("Ruta: MQL5\\Files\\", fileName);
}

//+------------------------------------------------------------------+
//| Timeframe to string                                              |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M4:   return "M4";
      case PERIOD_M5:   return "M5";
      case PERIOD_M6:   return "M6";
      case PERIOD_M10:  return "M10";
      case PERIOD_M12:  return "M12";
      case PERIOD_M15:  return "M15";
      case PERIOD_M20:  return "M20";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
      default:          return "TF";
   }
}

//+------------------------------------------------------------------+
//| Digits helper                                                    |
//+------------------------------------------------------------------+
int _DigitsForSymbol(string symbol)
{
   long digits = 5;
   if(SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits))
      return (int)digits;

   return 5;
}
//+------------------------------------------------------------------+