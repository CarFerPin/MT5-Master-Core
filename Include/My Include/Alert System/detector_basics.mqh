#ifndef DETECTOR_BASICS_MQH
#define DETECTOR_BASICS_MQH

namespace DetectorsBasic
{

double SMA(const double &values[], const int start, const int length)
{
   if(length <= 0)
      return 0.0;

   double sum = 0.0;

   for(int i=start;i<start+length;i++)
      sum += values[i];

   return sum/(double)length;
}

double StdDev(const double &values[], const int start, const int length)
{
   if(length <= 1)
      return 0.0;

   const double mean = SMA(values,start,length);

   double sq_sum = 0.0;

   for(int i=start;i<start+length;i++)
   {
      const double d = values[i] - mean;
      sq_sum += d*d;
   }

   return MathSqrt(sq_sum/(double)length);
}

//==============================================================
// VECTOR CANDLE
//==============================================================

int DetectVectorCandle(const MqlRates &rates[])
{
   const double full_range = rates[1].high - rates[1].low;

   if(full_range <= 0.0)
      return 0;

   const double body = MathAbs(rates[1].close - rates[1].open);

   double prev_ranges[10];

   for(int i=0;i<10;i++)
      prev_ranges[i] = rates[i+2].high - rates[i+2].low;

   const double avg_range = SMA(prev_ranges,0,10);

   if(avg_range <= 0.0)
      return 0;

   const bool range_expansion = full_range > avg_range*1.4;
   const bool body_dominance  = (body/full_range) > 0.7;

   if(range_expansion && body_dominance)
   {
      if(rates[1].close > rates[1].open)
         return 1;

      if(rates[1].close < rates[1].open)
         return -1;
   }

   return 0;
}

//==============================================================
// RANGE EXPANSION
//==============================================================

bool DetectRangeExpansion(const MqlRates &rates[], const double atr_current)
{
   const double candle_range = rates[1].high - rates[1].low;

   if(candle_range <= 0.0 || atr_current <= 0.0)
      return false;

   return candle_range > 1.6 * atr_current;
}

//==============================================================
// BOLLINGER EXPANSION
//==============================================================

bool DetectBollingerVolatilityExpansion(const MqlRates &rates[])
{
   double closes[26];

   for(int i=0;i<26;i++)
      closes[i] = rates[i+1].close;

   double bb_width[7];

   for(int i=0;i<7;i++)
   {
      const double basis = SMA(closes,i,20);
      const double dev = 2.0 * StdDev(closes,i,20);

      bb_width[i] = (basis+dev) - (basis-dev);
   }

   const double current_width = bb_width[0];
   const double width_mean = SMA(bb_width,0,7);

   if(width_mean <= 0.0)
      return false;

   const double expansion_pct =
      ((current_width - width_mean)/width_mean)*100.0;

   return expansion_pct > 15.0;
}

//==============================================================
// ATR REGIME EXPANSION
//==============================================================

bool DetectATRVolatilityRegimeExpansion(
      const double atr_current,
      const double atr_prev)
{
   if(atr_current <= 0.0 || atr_prev <= 0.0)
      return false;

   return atr_current > 1.3 * atr_prev;
}

//==============================================================
// VOLUME SPIKE
//==============================================================

bool DetectActivityConfirmationVolumeSpike(const MqlRates &rates[])
{
   double volume_series[20];

   for(int i=0;i<20;i++)
      volume_series[i] = (double)rates[i+1].tick_volume;

   const double avg_volume = SMA(volume_series,0,20);

   if(avg_volume <= 0.0)
      return false;

   return rates[1].tick_volume > avg_volume * 1.5;
}

}

#endif