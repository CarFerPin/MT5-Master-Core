#ifndef DETECTOR_STRUCTURE_MQH
#define DETECTOR_STRUCTURE_MQH

namespace DetectorsStructure
{

//==============================================================
// INTERNAL UTILITIES
//==============================================================

double HighestHigh(const MqlRates &rates[], const int from_shift, const int to_shift)
{
   double highest = rates[from_shift].high;

   for(int i = from_shift + 1; i <= to_shift; i++)
   {
      if(rates[i].high > highest)
         highest = rates[i].high;
   }

   return highest;
}

double LowestLow(const MqlRates &rates[], const int from_shift, const int to_shift)
{
   double lowest = rates[from_shift].low;

   for(int i = from_shift + 1; i <= to_shift; i++)
   {
      if(rates[i].low < lowest)
         lowest = rates[i].low;
   }

   return lowest;
}

double AverageRange(const MqlRates &rates[], const int from_shift, const int to_shift)
{
   double sum = 0.0;
   int count = 0;

   for(int i = from_shift; i <= to_shift; i++)
   {
      sum += (rates[i].high - rates[i].low);
      count++;
   }

   if(count == 0)
      return 0.0;

   return sum / (double)count;
}

//==============================================================
// LIQUIDITY SWEEP
//==============================================================

int DetectLiquiditySweep(const MqlRates &rates[])
{
   const double ref_low  = LowestLow(rates,2,11);
   const double ref_high = HighestHigh(rates,2,11);

   if(rates[1].low < ref_low && rates[1].close > ref_low)
      return 1;

   if(rates[1].high > ref_high && rates[1].close < ref_high)
      return -1;

   return 0;
}

//==============================================================
// BREAKOUT
//==============================================================

int DetectBreakout(const MqlRates &rates[])
{
   const double range_high = HighestHigh(rates,2,21);
   const double range_low  = LowestLow(rates,2,21);

   const double close_1 = rates[1].close;

   if(close_1 > range_high)
      return 1;

   if(close_1 < range_low)
      return -1;

   return 0;
}

//==============================================================
// FAIR VALUE GAP
//==============================================================

int DetectFVG(const MqlRates &rates[], bool requireImpulse = true)
{
   if(requireImpulse)
   {
      const double avg_range = AverageRange(rates,4,13);
      const double body_2 = MathAbs(rates[2].open - rates[2].close);

      if(avg_range <= 0.0 || body_2 <= avg_range * 1.5)
         return 0;
   }

   if(rates[1].low > rates[3].high)
      return 1;

   if(rates[1].high < rates[3].low)
      return -1;

   return 0;
}

//==============================================================
// MARKET STRUCTURE SHIFT
//==============================================================

int DetectMSS(const MqlRates &rates[])
{
   const double close_1 = rates[1].close;

   bool have_swing_high = false;
   bool have_swing_low  = false;

   double last_swing_high = 0.0;
   double last_swing_low  = 0.0;

   // búsqueda de pivots en las últimas 40 velas
   for(int i = 2; i <= 41; i++)
   {
      if(!have_swing_high)
      {
         if(rates[i].high > rates[i+1].high && rates[i].high > rates[i-1].high)
         {
            last_swing_high = rates[i].high;
            have_swing_high = true;
         }
      }

      if(!have_swing_low)
      {
         if(rates[i].low < rates[i+1].low && rates[i].low < rates[i-1].low)
         {
            last_swing_low = rates[i].low;
            have_swing_low = true;
         }
      }

      if(have_swing_high && have_swing_low)
         break;
   }

   if(have_swing_high && close_1 > last_swing_high)
      return 1;

   if(have_swing_low && close_1 < last_swing_low)
      return -1;

   return 0;
}

}

#endif