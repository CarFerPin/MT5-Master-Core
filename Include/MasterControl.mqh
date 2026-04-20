#ifndef __MASTERCONTROL_MQH__
#define __MASTERCONTROL_MQH__

struct RiskConfig
{
   double base_volume;
   double counter_multiplier;
};

struct ControlLayer
{
   bool enabled;
   string mode;
   RiskConfig risk;
};

struct MasterControlConfig
{
   ControlLayer global;
};

MasterControlConfig g_masterControl;
ControlLayer g_symbolControl;

bool g_hasSymbolOverride = false;
string g_masterControlPath = "TradeAssistant/control.json";
string g_masterControlRawJson = "";
datetime g_masterControlLastModify = 0;
bool g_masterControlLoaded = false;

void MC_Reset()
{
   g_masterControl.global.enabled = false;
   g_masterControl.global.mode = "";
   g_masterControl.global.risk.base_volume = 0.0;
   g_masterControl.global.risk.counter_multiplier = 1.0;

   g_symbolControl.enabled = false;
   g_symbolControl.mode = "";
   g_symbolControl.risk.base_volume = 0.0;
   g_symbolControl.risk.counter_multiplier = 1.0;
   g_hasSymbolOverride = false;

   g_masterControlRawJson = "";
   g_masterControlLoaded = false;
}

datetime MC_GetFileModifyDate()
{
   return (datetime)FileGetInteger(g_masterControlPath, FILE_MODIFY_DATE);
}

bool MC_FindSection(const string json, const string key, string &section)
{
   section = "";
   string k = "\"" + key + "\"";
   int kpos = StringFind(json, k);
   if(kpos < 0) return false;

   int objStart = StringFind(json, "{", kpos + StringLen(k));
   if(objStart < 0) return false;

   int depth = 0;
   int n = StringLen(json);
   for(int i=objStart; i<n; i++)
   {
      ushort c = (ushort)StringGetCharacter(json, i);
      if(c == '{') depth++;
      if(c == '}')
      {
         depth--;
         if(depth == 0)
         {
            section = StringSubstr(json, objStart, i - objStart + 1);
            return true;
         }
      }
   }

   return false;
}

bool MC_ExtractJsonString(const string obj, const string key, string &value)
{
   value = "";
   string k = "\"" + key + "\"";
   int kpos = StringFind(obj, k);
   if(kpos < 0) return false;

   int colon = StringFind(obj, ":", kpos + StringLen(k));
   if(colon < 0) return false;

   int q1 = StringFind(obj, "\"", colon + 1);
   if(q1 < 0) return false;

   int q2 = StringFind(obj, "\"", q1 + 1);
   if(q2 < 0) return false;

   value = StringSubstr(obj, q1 + 1, q2 - q1 - 1);
   return true;
}

bool MC_ExtractJsonBool(const string obj, const string key, bool &value)
{
   string k = "\"" + key + "\"";
   int kpos = StringFind(obj, k);
   if(kpos < 0) return false;

   int colon = StringFind(obj, ":", kpos + StringLen(k));
   if(colon < 0) return false;

   int tPos = StringFind(obj, "true", colon);
   int fPos = StringFind(obj, "false", colon);

   if(tPos >= 0 && (fPos < 0 || tPos < fPos))
   {
      value = true;
      return true;
   }

   if(fPos >= 0 && (tPos < 0 || fPos < tPos))
   {
      value = false;
      return true;
   }

   return false;
}

bool MC_ExtractJsonDouble(const string obj, const string key, double &value)
{
   string k = "\"" + key + "\"";
   int kpos = StringFind(obj, k);
   if(kpos < 0) return false;

   int colon = StringFind(obj, ":", kpos + StringLen(k));
   if(colon < 0) return false;

   int start = colon + 1;
   int n = StringLen(obj);
   while(start < n)
   {
      ushort c = (ushort)StringGetCharacter(obj, start);
      if(c != ' ' && c != '\t' && c != '\r' && c != '\n')
         break;
      start++;
   }

   int end = start;
   while(end < n)
   {
      ushort c = (ushort)StringGetCharacter(obj, end);
      if((c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.')
         end++;
      else
         break;
   }

   if(end <= start) return false;

   value = StringToDouble(StringSubstr(obj, start, end - start));
   return true;
}

void MC_ParseGlobal()
{
   string globalObj;
   if(!MC_FindSection(g_masterControlRawJson, "global", globalObj))
      return;

   ControlLayer parsed;
   
   parsed.enabled = g_masterControl.global.enabled;
   parsed.mode = g_masterControl.global.mode;
   parsed.risk.base_volume = g_masterControl.global.risk.base_volume;
   parsed.risk.counter_multiplier = g_masterControl.global.risk.counter_multiplier;

   bool enabled;
   if(MC_ExtractJsonBool(globalObj, "enabled", enabled))
      parsed.enabled = enabled;

   string mode;
   if(MC_ExtractJsonString(globalObj, "mode", mode))
      parsed.mode = mode;

   string riskObj;
   if(MC_FindSection(globalObj, "risk", riskObj))
   {
      double baseVolume;
      if(MC_ExtractJsonDouble(riskObj, "base_volume", baseVolume))
         parsed.risk.base_volume = baseVolume;

      double counterMultiplier;
      if(MC_ExtractJsonDouble(riskObj, "counter_multiplier", counterMultiplier))
         parsed.risk.counter_multiplier = counterMultiplier;
   }
        g_masterControl.global = parsed;
}

string MC_NormalizeSymbol(string raw)
{
   string clean = raw;

   int dotPos = StringFind(clean, ".");
   if(dotPos >= 0)
      clean = StringSubstr(clean, 0, dotPos);

   int len = StringLen(clean);
   if(len > 0 && StringGetCharacter(clean, len - 1) == 'm')
      clean = StringSubstr(clean, 0, len - 1);

   return clean;
}

void MC_ParseSymbol()
{
   string symbolsObj;
   if(!MC_FindSection(g_masterControlRawJson, "symbols", symbolsObj))
      return;

   string symbolKey = MC_NormalizeSymbol(Symbol());
   if(symbolKey == "")
      return;

   string symbolObj;
   string symbolKeyJson = "\"" + symbolKey + "\"";
   if(!MC_FindSection(symbolsObj, symbolKeyJson, symbolObj))
      return;

   ControlLayer parsed;

   parsed.enabled = g_masterControl.global.enabled;
   parsed.mode = g_masterControl.global.mode;
   parsed.risk.base_volume = g_masterControl.global.risk.base_volume;
   parsed.risk.counter_multiplier = g_masterControl.global.risk.counter_multiplier;

   bool enabled;
   if(MC_ExtractJsonBool(symbolObj, "enabled", enabled))
      parsed.enabled = enabled;

   string mode;
   if(MC_ExtractJsonString(symbolObj, "mode", mode))
      parsed.mode = mode;

   string riskObj;
   if(MC_FindSection(symbolObj, "risk", riskObj))
   {
      double baseVolume;
      if(MC_ExtractJsonDouble(riskObj, "base_volume", baseVolume))
         parsed.risk.base_volume = baseVolume;

      double counterMultiplier;
      if(MC_ExtractJsonDouble(riskObj, "counter_multiplier", counterMultiplier))
         parsed.risk.counter_multiplier = counterMultiplier;
   }

      g_symbolControl = parsed;
      g_hasSymbolOverride = true;
}

bool LoadMasterControl(string &err)
{
   err = "";

   int h = FileOpen(g_masterControlPath, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      err = "Master control file missing: " + g_masterControlPath;
      return false;
   }

   string json = "";
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      json += line;
      if(!FileIsEnding(h)) json += "\n";
   }

   datetime md = MC_GetFileModifyDate();
   FileClose(h);
   
   MC_Reset();

   g_masterControlRawJson = json;
   MC_ParseGlobal();
   MC_ParseSymbol();
   g_masterControlLastModify = md;
   g_masterControlLoaded = true;
   return true;
}

bool CheckAndReloadMasterControl()
{
   datetime md = MC_GetFileModifyDate();

   if(md == 0)
      return false;

   if(!g_masterControlLoaded || md != g_masterControlLastModify)
   {
      string err = "";
      if(!LoadMasterControl(err))
      {
         Print("[MASTER CONTROL] reload failed: ", err, " | keeping last valid config");
         return false;
      }

      Print("[MASTER CONTROL] reloaded successfully");
      return true;
   }

   return false;
}

bool IsEnabled()
{
   if(g_hasSymbolOverride)
      return g_symbolControl.enabled;

   return g_masterControl.global.enabled;
}

string GetMode()
{
   if(g_hasSymbolOverride)
      return g_symbolControl.mode;

   return g_masterControl.global.mode;
}

double GetVolumeMultiplier()
{
   string mode = GetMode();

   if(mode == "counter")
   {
      if(g_hasSymbolOverride)
         return g_symbolControl.risk.counter_multiplier;
      else
         return g_masterControl.global.risk.counter_multiplier;
   }

   return 1.0;
}

#endif