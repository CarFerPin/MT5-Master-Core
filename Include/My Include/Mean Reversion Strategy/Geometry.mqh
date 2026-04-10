#ifndef __GEOMETRY_MQH__
#define __GEOMETRY_MQH__

//+------------------------------------------------------------------+
//| Geometry Engine: OLS linear regression over a rolling window     |
//| Model: P_t = alpha + beta * t + epsilon_t                        |
//+------------------------------------------------------------------+
class CLinearRegression
  {
private:
   int      m_length;
   double   m_slope;
   double   m_intercept;
   double   m_last_value;
   double   m_r_squared;
   bool     m_is_valid;
   double   m_residuals[]; // Residuals indexed as x = 0..n-1 (oldest->latest)

   // Maps regression index x (oldest -> latest) to the source array index.
   // Supports both series arrays (index 0=current bar) and non-series arrays.
   int PriceIndex(const bool is_series,const int length,const int x) const
     {
      if(is_series)
         return (length - 1 - x);
      return x;
     }

public:
                     CLinearRegression()
     {
      Reset();
     }

   void              Reset()
     {
      m_length     = 0;
      m_slope      = 0.0;
      m_intercept  = 0.0;
      m_last_value = 0.0;
      m_r_squared  = 0.0;
      m_is_valid   = false;
      ArrayResize(m_residuals,0);
     }

   // Calculates OLS coefficients using x = 0..length-1 and y = price.
   // Returns false if input is invalid or denominator is degenerate.
   bool              Calculate(const double &price[],const int length)
     {
      Reset();

      if(length < 2)
         return false;

      if(ArraySize(price) < length)
         return false;

      const bool is_series = ArrayGetAsSeries(price);
      const double n = (double)length;

      double sum_x  = 0.0;
      double sum_y  = 0.0;
      double sum_xy = 0.0;
      double sum_x2 = 0.0;
      double sum_y2 = 0.0;

      // Single pass: collect all sums needed for beta, alpha and R^2.
      for(int x = 0; x < length; x++)
        {
         const int p_idx = PriceIndex(is_series,length,x);
         const double y  = price[p_idx];
         const double dx = (double)x;

         sum_x  += dx;
         sum_y  += y;
         sum_xy += dx * y;
         sum_x2 += dx * dx;
         sum_y2 += y * y;
        }

      const double den_x = (n * sum_x2) - (sum_x * sum_x);
      if(MathAbs(den_x) <= DBL_EPSILON)
         return false;

      m_slope = ((n * sum_xy) - (sum_x * sum_y)) / den_x;

      const double mean_x = sum_x / n;
      const double mean_y = sum_y / n;
      m_intercept = mean_y - (m_slope * mean_x);

      m_length = length;
      m_last_value = GetValueAt(length - 1);

      // Pearson correlation^2 using already-available OLS sums.
      const double den_y = (n * sum_y2) - (sum_y * sum_y);
      if(den_y > DBL_EPSILON)
        {
         const double num = (n * sum_xy) - (sum_x * sum_y);
         m_r_squared = (num * num) / (den_x * den_y);

         // Clamp potential floating-point drift.
         if(m_r_squared < 0.0)
            m_r_squared = 0.0;
         if(m_r_squared > 1.0)
            m_r_squared = 1.0;
        }
      else
        {
         // Flat Y series => perfect fit around constant mean/intercept.
         m_r_squared = 1.0;
        }

      // Optional residuals.
      if(ArrayResize(m_residuals,length) == length)
        {
         for(int x = 0; x < length; x++)
           {
            const int p_idx = PriceIndex(is_series,length,x);
            const double y  = price[p_idx];
            m_residuals[x]  = y - GetValueAt(x);
           }
        }

      m_is_valid = true;
      return true;
     }

   bool              IsValid() const
     {
      return m_is_valid;
     }

   double            GetSlope() const
     {
      return m_slope;
     }

   double            GetIntercept() const
     {
      return m_intercept;
     }

   // x index inside regression window: 0 = oldest, length-1 = latest/current.
   double            GetValueAt(const int index) const
     {
      if(index < 0 || index >= m_length)
         return EMPTY_VALUE;

      return (m_intercept + (m_slope * (double)index));
     }

   // Regression value at the latest/current bar in the window.
   double            GetLastValue() const
     {
      return m_last_value;
     }

   double            GetResidualAt(const int index) const
     {
      if(index < 0 || index >= ArraySize(m_residuals))
         return EMPTY_VALUE;

      return m_residuals[index];
     }

   int               GetLength() const
     {
      return m_length;
     }

   double            GetRSquared() const
     {
      return m_r_squared;
     }
  };

#endif // __GEOMETRY_MQH__
