#ifndef __DISTRIBUTION_MQH__
#define __DISTRIBUTION_MQH__

//+------------------------------------------------------------------+
//| Fat-tail calibration using Student-t distribution                |
//| Converts residual z-score into two-sided tail probability        |
//+------------------------------------------------------------------+
class CStudentTCalibration
  {
private:
   double m_df;
   double m_last_z;
   double m_tail_probability;
   double m_extremeness_score;
   bool   m_is_valid;

   // Lanczos approximation for log-gamma (numerically stable).
   double LogGamma(const double z) const
     {
      static const double p[] =
        {
         0.99999999999980993,
         676.5203681218851,
        -1259.1392167224028,
         771.32342877765313,
        -176.61502916214059,
         12.507343278686905,
        -0.13857109526572012,
         0.000009984369578019572,
         0.00000015056327351493116
        };

      if(z < 0.5)
         return MathLog(M_PI) - MathLog(MathSin(M_PI * z)) - LogGamma(1.0 - z);

      double x = p[0];
      const double zz = z - 1.0;
      for(int i = 1; i < ArraySize(p); i++)
         x += p[i] / (zz + (double)i);

      const double t = zz + 7.5;
      return 0.5 * MathLog(2.0 * M_PI) + (zz + 0.5) * MathLog(t) - t + MathLog(x);
     }

   // Continued fraction for incomplete beta function.
   double BetaContinuedFraction(const double a,const double b,const double x) const
     {
      const int    MAX_ITER = 200;
      const double EPS      = 3.0e-14;
      const double FPMIN    = 1.0e-300;

      double qab = a + b;
      double qap = a + 1.0;
      double qam = a - 1.0;
      double c = 1.0;
      double d = 1.0 - qab * x / qap;
      if(MathAbs(d) < FPMIN)
         d = FPMIN;
      d = 1.0 / d;
      double h = d;

      for(int m = 1; m <= MAX_ITER; m++)
        {
         int m2 = 2 * m;
         double aa = m * (b - (double)m) * x / ((qam + m2) * (a + m2));
         d = 1.0 + aa * d;
         if(MathAbs(d) < FPMIN)
            d = FPMIN;
         c = 1.0 + aa / c;
         if(MathAbs(c) < FPMIN)
            c = FPMIN;
         d = 1.0 / d;
         h *= d * c;

         aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
         d = 1.0 + aa * d;
         if(MathAbs(d) < FPMIN)
            d = FPMIN;
         c = 1.0 + aa / c;
         if(MathAbs(c) < FPMIN)
            c = FPMIN;
         d = 1.0 / d;
         const double del = d * c;
         h *= del;

         if(MathAbs(del - 1.0) < EPS)
            break;
        }

      return h;
     }

   // Regularized incomplete beta I_x(a,b).
   double RegularizedIncompleteBeta(const double x,const double a,const double b) const
     {
      if(x <= 0.0)
         return 0.0;
      if(x >= 1.0)
         return 1.0;
      if(a <= 0.0 || b <= 0.0)
         return 0.0;

      const double log_bt = LogGamma(a + b) - LogGamma(a) - LogGamma(b)
                          + a * MathLog(x) + b * MathLog(1.0 - x);
      const double bt = MathExp(log_bt);

      // Symmetry transform improves numerical stability.
      if(x < (a + 1.0) / (a + b + 2.0))
         return bt * BetaContinuedFraction(a,b,x) / a;

      return 1.0 - (bt * BetaContinuedFraction(b,a,1.0 - x) / b);
     }

   // Student-t CDF for any real t and df > 0.
   double StudentTCDF(const double t,const double df) const
     {
      if(df <= 0.0)
         return 0.5;

      if(t == 0.0)
         return 0.5;

      const double x = df / (df + t * t);
      const double a = df * 0.5;
      const double b = 0.5;
      const double ib = RegularizedIncompleteBeta(x,a,b);

      if(t > 0.0)
         return 1.0 - 0.5 * ib;

      return 0.5 * ib;
     }

public:
                     CStudentTCalibration(const double df = 5.0)
     {
      Reset();
      SetDegreesOfFreedom(df);
     }

   void              Reset()
     {
      m_last_z           = 0.0;
      m_tail_probability = 1.0;
      m_extremeness_score= 0.0;
      m_is_valid         = false;
     }

   // Degrees of freedom for Student-t tail modeling.
   void              SetDegreesOfFreedom(const double df)
     {
      // Keep df strictly positive and stable near zero.
      m_df = MathMax(df,1.0e-6);
     }

   // Calculates two-sided tail probability and extremeness from z-score.
   bool              Calculate(const double zscore)
     {
      m_last_z = zscore;

      const double abs_z = MathAbs(zscore);
      const double cdf   = StudentTCDF(abs_z,m_df);

      double p = 2.0 * (1.0 - cdf);
      if(p < DBL_MIN)
         p = DBL_MIN;
      if(p > 1.0)
         p = 1.0;

      m_tail_probability  = p;
      m_extremeness_score = -MathLog(p);
      m_is_valid          = true;
      return true;
     }

   double            GetTailProbability() const
     {
      return m_tail_probability;
     }

   double            GetExtremenessScore() const
     {
      return m_extremeness_score;
     }

   double            GetDegreesOfFreedom() const
     {
      return m_df;
     }
  };

#endif // __DISTRIBUTION_MQH__
