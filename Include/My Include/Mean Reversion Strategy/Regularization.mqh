#ifndef __REGULARIZATION_MQH__
#define __REGULARIZATION_MQH__

#include "Geometry.mqh"

//+------------------------------------------------------------------+
//| Optional slope normalization modes                               |
//+------------------------------------------------------------------+
enum ENUM_SLOPE_MODE
  {
   SLOPE_RAW = 0,          // Price units per bar
   SLOPE_POINTS_PER_BAR,   // Points per bar (requires point size)
   SLOPE_PERCENT_PER_BAR   // Percent per bar (vs regression last value)
  };

//+------------------------------------------------------------------+
//| Structural validator for mean-reversion regime filtering         |
//+------------------------------------------------------------------+
class CStructureValidator
  {
private:
   double          m_r2_threshold;
   double          m_max_slope;
   double          m_min_slope;
   bool            m_is_valid;

   double          m_r_squared;
   double          m_slope;
   double          m_slope_comparable;
   
   ENUM_SLOPE_MODE m_slope_mode;
   double          m_point_size;

   double NormalizeSlope(const CLinearRegression &lr) const
     {
      const double abs_slope = MathAbs(m_slope);

      switch(m_slope_mode)
        {
         case SLOPE_POINTS_PER_BAR:
            if(m_point_size > DBL_EPSILON)
               return abs_slope / m_point_size;
            return abs_slope;

         case SLOPE_PERCENT_PER_BAR:
           {
            const double reg_last = lr.GetLastValue();
            if(MathAbs(reg_last) > DBL_EPSILON)
               return (abs_slope / MathAbs(reg_last)) * 100.0;
            return DBL_MAX;
           }

         case SLOPE_RAW:
         default:
            return abs_slope;
        }
     }

public:
                     CStructureValidator(const double r2_threshold = 0.70,
                    const double max_slope = 0.0)
      {
         m_slope_mode = SLOPE_RAW;
         m_point_size = _Point;
         Reset();
         m_min_slope = 0.0;
         SetThreshold(r2_threshold);
         SetMaxSlope(max_slope);
      }

   void              Reset()
     {
      m_is_valid          = false;
      m_r_squared         = 0.0;
      m_slope             = 0.0;
      m_slope_comparable  = 0.0;
     }

   void              SetThreshold(const double r2_threshold)
     {
      m_r2_threshold = MathMax(0.0,MathMin(1.0,r2_threshold));
     }

   void SetMaxSlope(const double max_slope)
      {
         m_max_slope = MathMax(0.0,max_slope);
      }
      
      void SetMinSlope(const double min_slope)
      {
         m_min_slope = MathMax(0.0,min_slope);
      }

   // Optional slope normalization.
   // - SLOPE_RAW: threshold in price units/bar
   // - SLOPE_POINTS_PER_BAR: threshold in points/bar
   // - SLOPE_PERCENT_PER_BAR: threshold in %/bar
   void              SetSlopeMode(const ENUM_SLOPE_MODE mode,const double point_size = 0.0)
     {
      m_slope_mode = mode;
      if(point_size > 0.0)
         m_point_size = point_size;
     }

   // Evaluate structure quality from an already-computed linear regression.
   // Timeframe agnostic: simply reads values from the provided regression object.
   bool              Evaluate(const CLinearRegression &lr)
     {
      m_r_squared = lr.GetRSquared();
      m_slope     = lr.GetSlope();

      const bool r2_ok = (m_r_squared >= m_r2_threshold);

      bool slope_ok = true;
      
      m_slope_comparable = NormalizeSlope(lr);
      const double abs_slope = m_slope_comparable;
      
      if(m_min_slope > 0.0 && abs_slope < m_min_slope)
         slope_ok = false;
      
      if(m_max_slope > 0.0 && abs_slope > m_max_slope)
         slope_ok = false;

      m_is_valid = (r2_ok && slope_ok);
      return m_is_valid;
     }

   bool              IsStructureValid() const
     {
      return m_is_valid;
     }

   double            GetRSquared() const
     {
      return m_r_squared;
     }

   double            GetSlope() const
     {
      return m_slope;
     }

   // Useful when using normalized slope filters.
   double            GetComparableSlope() const
     {
      return m_slope_comparable;
     }
  };

#endif // __REGULARIZATION_MQH__
