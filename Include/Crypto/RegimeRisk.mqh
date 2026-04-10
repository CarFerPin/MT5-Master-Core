// Path: C:\Users\carfe\AppData\Roaming\MetaQuotes\Terminal\10CE948A1DFC9A8C27E56E827008EBD4\MQL5\Include\Crypto\RegimeRisk.mqh
//+------------------------------------------------------------------+
//| RiskRegime.mqh - Volatility regimes + sigma stop + RR TP         |
//| Minimal, no external deps                                        |
//+------------------------------------------------------------------+

#ifndef REGIME_RISK_MQH
#define REGIME_RISK_MQH

enum VolState { VOL_LOW=0, VOL_MID=1, VOL_HIGH=2 };

inline double ClampD(const double x, const double lo, const double hi)
{
   return MathMax(lo, MathMin(hi, x));
}

// Sigma of log-returns on Close: r = ln(C_t/C_{t-1})
inline double SigmaLogReturns(const string symbol, ENUM_TIMEFRAMES tf, int N, int shift=0)
{
   if(N < 3) return 0.0;

   double c[];
   if(CopyClose(symbol, tf, shift, N+1, c) < N+1) return 0.0;

   double sum=0.0, sum2=0.0;
   for(int i=0; i<N; i++)
   {
      double c0 = c[i];
      double c1 = c[i+1];
      if(c0 <= 0.0 || c1 <= 0.0) return 0.0;

      double r = MathLog(c0 / c1);
      sum  += r;
      sum2 += r*r;
   }
   double mean = sum / N;
   double var  = (sum2 / N) - mean*mean;
   if(var < 0.0) var = 0.0;
   return MathSqrt(var);
}

// z-score of sigmaS vs sampled historical sigma distribution
// Long window is represented by 'samples' computed every 'step' bars.
// This keeps it cheap enough for runtime.
inline bool SigmaZScoreSampled(const string symbol, ENUM_TIMEFRAMES tf,
                               int Nshort, int Nlong,
                               int step, int maxSamples,
                               double &sigmaS, double &z)
{
   sigmaS = SigmaLogReturns(symbol, tf, Nshort, 0);
   if(sigmaS <= 0.0) { z = 0.0; return false; }

   if(step < 1) step = 1;
   int samples = Nlong / step;
   if(samples < 20) samples = 20;
   if(maxSamples > 0) samples = MathMin(samples, maxSamples);

   double sum=0.0, sum2=0.0;
   int used=0;

   for(int k=0; k<samples; k++)
   {
      int sh = k*step;
      double s = SigmaLogReturns(symbol, tf, Nshort, sh);
      if(s <= 0.0) break;

      sum  += s;
      sum2 += s*s;
      used++;
   }

   if(used < 10) { z = 0.0; return false; }

   double mean = sum / used;
   double var  = (sum2 / used) - mean*mean;
   if(var < 1e-12) { z = 0.0; return true; }

   double sd = MathSqrt(var);
   z = (sigmaS - mean) / sd;
   return true;
}

// Hysteresis regime update
inline VolState UpdateVolStateH(const VolState prev, const double z,
                                const double upHigh=0.6, const double downHigh=0.4,
                                const double downLow=-0.6, const double upLow=-0.4)
{
   if(prev == VOL_MID)
   {
      if(z > upHigh)  return VOL_HIGH;
      if(z < downLow) return VOL_LOW;
      return VOL_MID;
   }
   if(prev == VOL_HIGH)
   {
      if(z < downHigh) return VOL_MID;
      return VOL_HIGH;
   }
   // prev == VOL_LOW
   if(z > upLow) return VOL_MID;
   return VOL_LOW;
}

// Stop from sigma for SHORT: SL = entry * exp(k*sigma)
inline double StopFromSigmaShort(const double entry, const double sigma, const double k)
{
   if(entry <= 0.0 || sigma <= 0.0 || k <= 0.0) return 0.0;
   return entry * MathExp(k * sigma);
}

// Apply structural constraint for SHORT: SL = max(stopSigma, swingHigh + buffer)
inline double ApplyStructureShort(const double stopSigma, const double swingHigh, const double buffer)
{
   if(stopSigma <= 0.0) return 0.0;
   return MathMax(stopSigma, swingHigh + buffer);
}

// TP from exact RR for SHORT: TP = entry - RR*(SL-entry)
inline double TakeProfitFromRRShort(const double entry, const double stop, const double RR)
{
   if(entry <= 0.0 || stop <= 0.0 || RR <= 0.0) return 0.0;
   double risk = stop - entry;
   if(risk <= 0.0) return 0.0;
   return entry - RR * risk;
}
#endif // REGIME_RISK_MQH
