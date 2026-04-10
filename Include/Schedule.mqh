#ifndef __SCHEDULE_MQH__
#define __SCHEDULE_MQH__

struct Block
{
   int start_min;
   int end_min;
};

struct DaySchedule
{
   bool enabled;
   Block blocks[];
};

DaySchedule g_weekSchedule[7]; // 0=sunday ... 6=saturday
string g_schedulePath = "schedule.json";
datetime g_scheduleLastModify = 0;
bool g_scheduleLoaded = false;

void SCH_ResetDay(DaySchedule &day)
{
   day.enabled = false;
   ArrayResize(day.blocks, 0);
}

void SCH_ResetAll()
{
   for(int i=0; i<7; i++)
      SCH_ResetDay(g_weekSchedule[i]);
   g_scheduleLoaded = false;
}

bool SCH_ParseHHMM(const string hhmm, int &outMin)
{
   string s = hhmm;
   StringTrimLeft(s);
   StringTrimRight(s);

   string p[];
   if(StringSplit(s, ':', p) != 2) return false;

   int h = (int)StringToInteger(p[0]);
   int m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return false;

   outMin = h * 60 + m;
   return true;
}

int SCH_FindMatching(const string txt, const int openPos, const ushort openCh, const ushort closeCh)
{
   int n = StringLen(txt);
   if(openPos < 0 || openPos >= n) return -1;

   int depth = 0;
   for(int i=openPos; i<n; i++)
   {
      ushort c = (ushort)StringGetCharacter(txt, i);
      if(c == openCh) depth++;
      if(c == closeCh)
      {
         depth--;
         if(depth == 0) return i;
      }
   }
   return -1;
}

bool SCH_ExtractJsonString(const string obj, const string key, string &value)
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

bool SCH_ParseDay(const string json, const string dayName, DaySchedule &outDay)
{
   SCH_ResetDay(outDay);

   string dayKey = "\"" + dayName + "\"";
   int dayPos = StringFind(json, dayKey);
   if(dayPos < 0) return true; // day missing => disabled

   int objStart = StringFind(json, "{", dayPos);
   if(objStart < 0) return false;
   int objEnd = SCH_FindMatching(json, objStart, '{', '}');
   if(objEnd < 0) return false;

   string dayObj = StringSubstr(json, objStart, objEnd - objStart + 1);

   int enPos = StringFind(dayObj, "\"enabled\"");
   if(enPos >= 0)
   {
      int colon = StringFind(dayObj, ":", enPos);
      if(colon >= 0)
      {
         int tPos = StringFind(dayObj, "true", colon);
         int fPos = StringFind(dayObj, "false", colon);
         if(tPos >= 0 && (fPos < 0 || tPos < fPos)) outDay.enabled = true;
         else outDay.enabled = false;
      }
   }

   int blocksKey = StringFind(dayObj, "\"blocks\"");
   if(blocksKey < 0) return true;

   int arrStart = StringFind(dayObj, "[", blocksKey);
   if(arrStart < 0) return true;
   int arrEnd = SCH_FindMatching(dayObj, arrStart, '[', ']');
   if(arrEnd < 0) return false;

   string arr = StringSubstr(dayObj, arrStart + 1, arrEnd - arrStart - 1);

   int cursor = 0;
   while(true)
   {
      int bStart = StringFind(arr, "{", cursor);
      if(bStart < 0) break;
      int bEnd = SCH_FindMatching(arr, bStart, '{', '}');
      if(bEnd < 0) break;

      string bObj = StringSubstr(arr, bStart, bEnd - bStart + 1);
      string sStart, sEnd;
      if(SCH_ExtractJsonString(bObj, "start", sStart) && SCH_ExtractJsonString(bObj, "end", sEnd))
      {
         Block b;
         if(SCH_ParseHHMM(sStart, b.start_min) && SCH_ParseHHMM(sEnd, b.end_min))
         {
            int n = ArraySize(outDay.blocks);
            ArrayResize(outDay.blocks, n + 1);
            outDay.blocks[n] = b;
         }
      }

      cursor = bEnd + 1;
   }

   return true;
}

bool SCH_ParseJson(const string json, DaySchedule &parsed[])
{
   ArrayResize(parsed, 7);
   for(int i=0; i<7; i++) SCH_ResetDay(parsed[i]);

   string names[7] = {"sunday","monday","tuesday","wednesday","thursday","friday","saturday"};

   for(int d=0; d<7; d++)
   {
      DaySchedule tmp;
      if(!SCH_ParseDay(json, names[d], tmp))
         return false;
      parsed[d] = tmp;
   }

   return true;
}

datetime SCH_GetFileModifyDate()
{
   int h = FileOpen(g_schedulePath, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return 0;

   datetime md = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
   FileClose(h);
   return md;
}

bool LoadSchedule(string &err)
{
   err = "";

   int h = FileOpen(g_schedulePath, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      err = "Schedule file missing: " + g_schedulePath;
      return false;
   }

   string json = "";
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      json += line;
      if(!FileIsEnding(h)) json += "\n";
   }

   datetime md = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
   FileClose(h);

   DaySchedule parsed[];
   if(!SCH_ParseJson(json, parsed))
   {
      err = "Invalid schedule JSON format";
      return false;
   }

    for(int i=0; i<7; i++)
       g_weekSchedule[i] = parsed[i];
    
       g_scheduleLastModify = md;
       g_scheduleLoaded = true;
       return true;
}

bool CheckAndReload()
{
   datetime md = SCH_GetFileModifyDate();

   if(md == 0)
      return false;

   if(!g_scheduleLoaded || md != g_scheduleLastModify)
   {
      string err="";
      if(!LoadSchedule(err))
      {
         Print("[SCHEDULE] reload failed: ", err, " | keeping last valid config");
         return false;
      }
      Print("[SCHEDULE] reloaded successfully");
      return true;
   }

   return false;
}

bool IsBlockedNow()
{
   if(!g_scheduleLoaded)
      return false;

   datetime now = TimeCurrent();

   MqlDateTime tm;
   TimeToStruct(now, tm);

   int dow = tm.day_of_week;  // 🔥 faltaba esto
   if(dow < 0 || dow > 6) return false;

   int nowMin = tm.hour * 60 + tm.min;

   // offset: local → broker
   int offsetMin = (int)((TimeCurrent() - TimeLocal()) / 60);

   DaySchedule day = g_weekSchedule[dow];
   if(!day.enabled) return false;

   int n = ArraySize(day.blocks);
   for(int i=0; i<n; i++)
   {
      // 🔥 ajustar bloques, no el tiempo actual
      int s = (day.blocks[i].start_min + offsetMin + 1440) % 1440;
      int e = (day.blocks[i].end_min   + offsetMin + 1440) % 1440;

      if((s <= e && nowMin >= s && nowMin <= e) ||
         (s > e && (nowMin >= s || nowMin <= e)))
         return true;
   }

   return false;
}

#endif
