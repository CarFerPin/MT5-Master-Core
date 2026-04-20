double g_masterSize = 0.0;
long g_masterSizeMod = 0;

string g_masterPath = "master_size.json";

bool LoadMasterSize(string &err)
{
   int h = FileOpen(g_masterPath, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      err = "Cannot open master size file";
      return false;
   }

   string json = "";
   while(!FileIsEnding(h))
      json += FileReadString(h);

   FileClose(h);

   int pos = StringFind(json, "master_size");
   if(pos < 0)
   {
      err = "master_size not found";
      return false;
   }

   int colon = StringFind(json, ":", pos);
   if(colon < 0) return false;

   int end = StringFind(json, ",", colon);
   if(end < 0) end = StringFind(json, "}", colon);

   string val = StringSubstr(json, colon+1, end-colon-1);
   StringTrimLeft(val);
   StringTrimRight(val);

   double parsed = StringToDouble(val);
   if(parsed <= 0)
   {
      err = "invalid master_size";
      return false;
   }

   g_masterSize = parsed;
   Print("[MASTER SIZE] loaded: ", g_masterSize);
   return true;
}

bool CheckMasterReload()
{
   int h = FileOpen(g_masterPath, FILE_READ | FILE_TXT);
   if(h == INVALID_HANDLE) return false;

   long mod = FileGetInteger(h, FILE_MODIFY_DATE);
   FileClose(h);

   if(mod != g_masterSizeMod)
   {
      string err="";
      if(LoadMasterSize(err))
      {
         g_masterSizeMod = mod;
         Print("[MASTER SIZE] reloaded");
         return true;
      }
      else
      {
         Print("[MASTER SIZE ERROR] ", err);
      }
   }
   return false;
}