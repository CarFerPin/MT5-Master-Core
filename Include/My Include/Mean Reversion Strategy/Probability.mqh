#ifndef __PROBABILITY_MQH__
#define __PROBABILITY_MQH__

#include "Geometry.mqh"

//+------------------------------------------------------------------+
//| Residual Engine: residual dispersion and normalized distance      |
//| Uses residuals from CLinearRegression (no regression recalculation)|
//+------------------------------------------------------------------+
class CResidualEngine
  {
private:
   double m_sigma_residual;
   double m_last_residual;
   double m_zscore;
   int    m_length;
   bool   m_is_valid;

public:
            CResidualEngine()
     {
      Reset();
     }

   void     Reset()
     {
      m_sigma_residual = 0.0;
      m_last_residual  = 0.0;
      m_zscore         = 0.0;
      m_length         = 0;
      m_is_valid       = false;
     }

   // Calculates residual statistics from an already-computed regression object.
   // price[] is accepted to keep the method signature aligned with framework calls,
   // but regression values are never recomputed here.
   bool     Calculate(const CLinearRegression &lr)
     {
      Reset();

      const int n = lr.GetLength();
      if(n < 3) // Need n-2 degrees of freedom in denominator.
         return false;

      double sum_r   = 0.0;
      double sum_r2  = 0.0;

      // Single pass through residuals exported by CLinearRegression.
      for(int i = 0; i < n; i++)
        {
         const double r = lr.GetResidualAt(i);
         if(r == EMPTY_VALUE)
            return false;

         sum_r  += r;
         sum_r2 += (r * r);
        }

      // Residual mean (for validation/diagnostics). For OLS with intercept it
      // should be ~0, but we compute it explicitly as requested.

      // Residual standard deviation with n-2 DoF as requested:
      // sigma_r = sqrt( sum(r_i^2) / (n - 2) )
      m_sigma_residual = MathSqrt(sum_r2 / (double)(n - 2));

      // Last residual corresponds to x = n-1 (current/latest bar in window).
      m_last_residual = lr.GetResidualAt(n - 1);
      if(m_last_residual == EMPTY_VALUE)
         return false;

      // Numerical safety against division by zero.
      if(m_sigma_residual <= DBL_EPSILON)
         m_zscore = 0.0;
      else
         m_zscore = m_last_residual / m_sigma_residual;

      m_length   = n;
      m_is_valid = true;
      return true;
     }

   bool     IsValid() const
     {
      return m_is_valid;
     }

   double   GetResidualStdDev() const
     {
      return m_sigma_residual;
     }

   double   GetLastResidual() const
     {
      return m_last_residual;
     }

   double   GetZScore() const
     {
      return m_zscore;
     }

   int      GetLength() const
     {
      return m_length;
     }
  };

#endif // __PROBABILITY_MQH__
