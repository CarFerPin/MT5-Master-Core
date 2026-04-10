#ifndef TELEMETRY_MQH
#define TELEMETRY_MQH

#include <Alerts System/signal_formatter.mqh>
#include <Alerts System/telegram_api.mqh>

void SendSignalTelemetry(const ScannerEngine::MarketSignal &signal)
{
   string msg = FormatSignalMessage(signal);

   if(!SendTelegramMessage(msg))
      Print("TELEMETRY: Failed to send signal for ", signal.symbol);
}

#endif