#ifndef TELEGRAM_API_MQH
#define TELEGRAM_API_MQH

string UrlEncode(const string value)
{
   string encoded = "";
   const int len = StringLen(value);

   for(int i = 0; i < len; i++)
   {
      const ushort c = StringGetCharacter(value, i);

      const bool unreserved =
         (c >= 'A' && c <= 'Z') ||
         (c >= 'a' && c <= 'z') ||
         (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~';

      if(unreserved)
         encoded += ShortToString(c);
      else
         encoded += "%" + StringFormat("%02X", c);
   }

   return encoded;
}

bool SendTelegramMessage(string text)
{
   if(StringLen(TELEGRAM_BOT_TOKEN)==0 || StringLen(TELEGRAM_CHAT_ID)==0)
   {
      Print("TELEGRAM: Token o ChatID no configurados.");
      return false;
   }

   string url =
      "https://api.telegram.org/bot"+TELEGRAM_BOT_TOKEN+"/sendMessage";

   string headers =
      "Content-Type: application/x-www-form-urlencoded\r\n";

   string post =
      "chat_id="+TELEGRAM_CHAT_ID+
      "&text="+text;

   char data[];
   char result[];

   StringToCharArray(post,data,0,WHOLE_ARRAY,CP_UTF8);

   string response_headers;

   int status=WebRequest(
      "POST",
      url,
      headers,
      10000,
      data,
      result,
      response_headers
   );

   if(status==-1)
   {
      Print("TELEGRAM WebRequest error: ",GetLastError());
      return false;
   }

   if(status!=200)
   {
      Print("TELEGRAM HTTP error: ",status);
      Print(CharArrayToString(result));
      return false;
   }

   return true;
}

#endif