//+------------------------------------------------------------------+
//|                         GlobalHedgePortfolioWithAdjust.mq5       |
//|  Script MQL5 : Ouvre 0.01 lot sur chaque paire du JSON,          |
//|               utilise les positions existantes pour adapter      |
//|               BUY/SELL – si une position inverse existe, on la   |
//|               ferme d'abord                                      |
//|  • Volume fixe 0.01 pour chaque paire                            |
//|  • Stop-loss fixe de 2000 points                                 |
//|  • Sleep de 30s entre chaque ordre                               |
//|  • Si position existante de sens opposé, on la ferme et on ouvre | 
//|    la nouvelle position                                           |
//+------------------------------------------------------------------+
#property copyright "ChatGPT"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Stop-loss en points (2000 points = 200 pips sur EURUSD)
#define SL_POINTS    2000
// Volume fixe pour chaque position
#define FIXED_VOLUME 0.01
// Pause entre chaque ordre (en ms)
#define PAUSE_MS     30000

//+------------------------------------------------------------------+
//| Extraction d'un sous-objet JSON { ... } pour la clé "key"       |
//+------------------------------------------------------------------+
string ExtractJsonObject(const string &json, const string &key)
  {
   string search_pattern = "\"" + key + "\"";
   int start_pos = StringFind(json, search_pattern);
   if(start_pos == -1) return "";
   start_pos = StringFind(json, ":", start_pos);
   if(start_pos == -1) return "";
   start_pos++;
   while(start_pos < StringLen(json) &&
         (StringGetCharacter(json, start_pos) == ' ' || StringGetCharacter(json, start_pos) == '\t'))
      start_pos++;
   if(StringGetCharacter(json, start_pos) != '{') return "";
   int brace_count = 1, end_pos = start_pos + 1;
   while(end_pos < StringLen(json) && brace_count > 0)
     {
      ushort c = StringGetCharacter(json, end_pos);
      if(c == '{') brace_count++;
      else if(c == '}') brace_count--;
      end_pos++;
     }
   if(brace_count == 0)
      return StringSubstr(json, start_pos, end_pos - start_pos);
   return "";
  }

//+------------------------------------------------------------------+
//| Recherche si une chaîne est dans un tableau de chaînes           |
//+------------------------------------------------------------------+
bool IsStringInArray(const string &arr[], const string &value)
  {
   for(int i=0; i < ArraySize(arr); i++)
      if(arr[i] == value) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Retourne l'indice d'une chaîne dans un tableau, ou -1 si absent   |
//+------------------------------------------------------------------+
int IndexOf(const string &arr[], const string &value)
  {
   for(int i=0; i < ArraySize(arr); i++)
      if(arr[i] == value) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Analyse le JSON complet, extrait toutes les paires ("data":{…}), |
//| calcule pour chaque paire la corrélation moyenne                 |
//| par rapport aux autres                                             |
//+------------------------------------------------------------------+
bool ParseAllAvgCorrelations(const string &json, string &symbols[], double &avgCorrs[])
  {
   // 1) Vérifier "success":true
   if(StringFind(json, "\"success\":true") == -1 && StringFind(json, "\"success\": true") == -1)
     {
      Print("❌ JSON invalide (\"success\" != true)");
      return false;
     }

   // 2) Extraire l'objet "data"
   string data_obj = ExtractJsonObject(json, "data");
   if(StringLen(data_obj) == 0)
     {
      Print("❌ Impossible d'extraire l'objet \"data\" du JSON.");
      return false;
     }

   // 3) Collecter toutes les clés (paires) au premier niveau de data_obj
   ArrayResize(symbols, 0);
   int pos = 0;
   while(true)
     {
      int quote1 = StringFind(data_obj, "\"", pos);
      if(quote1 == -1) break;
      int quote2 = StringFind(data_obj, "\"", quote1 + 1);
      if(quote2 == -1) break;
      string sym = StringSubstr(data_obj, quote1 + 1, quote2 - (quote1 + 1));
      if(StringLen(sym) >= 6)
        {
         if(!IsStringInArray(symbols, sym))
           {
            int n = ArraySize(symbols) + 1;
            ArrayResize(symbols, n);
            symbols[n-1] = sym;
           }
        }
      pos = quote2 + 1;
     }

   int total = ArraySize(symbols);
   if(total == 0)
     {
      Print("❌ Aucun symbole détecté dans l'objet \"data\".");
      return false;
     }

   // 4) Préparer tableaux de somme et comptage
   double sumCorrs[];    ArrayResize(sumCorrs, total);
   int    countCorrs[];  ArrayResize(countCorrs, total);
   for(int i=0; i<total; i++) { sumCorrs[i]=0.0; countCorrs[i]=0; }

   // 5) Parcourir à nouveau data_obj pour extraire chaque bloc { "sym":{...} }
   pos = 0;
   while(true)
     {
      int q1 = StringFind(data_obj, "\"", pos);
      if(q1 == -1) break;
      int q2 = StringFind(data_obj, "\"", q1 + 1);
      if(q2 == -1) break;
      string baseSym = StringSubstr(data_obj, q1 + 1, q2 - (q1 + 1));
      pos = q2 + 1;

      int brace_open = StringFind(data_obj, "{", pos);
      if(brace_open == -1) break;
      int brace_count = 1, idx = brace_open + 1;
      while(idx < StringLen(data_obj) && brace_count > 0)
        {
         ushort c = StringGetCharacter(data_obj, idx);
         if(c == '{') brace_count++;
         else if(c == '}') brace_count--;
         idx++;
        }
      if(brace_count != 0) break;

      string inner = StringSubstr(data_obj, brace_open, idx - brace_open);

      // 6) Parcourir "inner" pour extraire les corrélations
      int ipos = 0;
      while(true)
        {
         int sk1 = StringFind(inner, "\"", ipos);
         if(sk1 == -1) break;
         int sk2 = StringFind(inner, "\"", sk1 + 1);
         if(sk2 == -1) break;
         string corrSym = StringSubstr(inner, sk1 + 1, sk2 - (sk1 + 1));
         ipos = sk2 + 1;

         int colon = StringFind(inner, ":", ipos);
         if(colon == -1) break;
         ipos = colon + 1;

         string numstr = "";
         while(ipos < StringLen(inner))
           {
            ushort ch = StringGetCharacter(inner, ipos);
            if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
            {
               numstr += CharToString((uchar)ch);
               ipos++;
            }
            else break;
           }
         double val = StringToDouble(numstr);

         int ibase = IndexOf(symbols, baseSym);
         int icorr = IndexOf(symbols, corrSym);
         if(ibase >= 0 && icorr >= 0 && ibase != icorr)
           {
            sumCorrs[ibase]  += val;
            countCorrs[ibase]++;
            sumCorrs[icorr]  += val;
            countCorrs[icorr]++;
           }
        }

      pos = idx;
     }

   // 7) Calculer la corrélation moyenne pour chaque symbole
   ArrayResize(avgCorrs, total);
   for(int i=0; i<total; i++)
     {
      if(countCorrs[i] > 0)
         avgCorrs[i] = sumCorrs[i] / countCorrs[i];
      else
         avgCorrs[i] = 0.0;
     }

   PrintFormat("✅ %d paires chargées avec corrélation moyenne calculée.", total);
   return true;
  }

//+------------------------------------------------------------------+
//| Vérifie si une position est déjà ouverte sur le symbole donné    |
//| Renvoie true si au moins une position (BUY ou SELL) existe       |
//+------------------------------------------------------------------+
bool HasOpenPosition(const string &symbol)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol)
            return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Obtient le ticket et le type (BUY/SELL) d'une position existante |
//| Retourne true si au moins une position existe, et renvoie par     |
//| référence le ticket et le direction (POSITION_TYPE).              |
//+------------------------------------------------------------------+
bool GetExistingPosition(const string &symbol, ulong &outTicket, ENUM_POSITION_TYPE &outType)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol)
           {
            outTicket = ticket;
            outType   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Ferme la position du ticket donné                                |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   string sym    = PositionGetString(POSITION_SYMBOL);
   double vol    = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   bool ok = false;
   if(ptype == POSITION_TYPE_BUY)
      ok = trade.Sell(vol, sym);
   else
      ok = trade.Buy(vol, sym);
   if(!ok)
      PrintFormat("❌ Échec fermeture ticket %I64u (%s) : %s", ticket, sym, trade.ResultComment());
   return ok;
  }

//+------------------------------------------------------------------+
//| Script principal                                                 |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("▶️ Début : GlobalHedgePortfolioWithAdjust.mq5");

   // 1) Récupérer le JSON via WebRequest
   string url = "https://macrofinder.flolep.fr/api/assets/correlations";
   char   request_data[], result_bytes[];
   string response_headers;
   int    timeout = 5000;
   int    res = WebRequest("GET", url, "", timeout, request_data, result_bytes, response_headers);

   if(res == -1)
     {
      PrintFormat("❌ WebRequest échoué (GetLastError=%d).", GetLastError());
      return;
     }

   string json_content = CharArrayToString(result_bytes);
   if(StringLen(json_content) == 0)
     {
      Print("❌ Réponse vide de l'API.");
      return;
     }

   // 2) Parser toutes les paires et calculer leur corrélation moyenne
   string symbols[];
   double avgCorrs[];
   if(!ParseAllAvgCorrelations(json_content, symbols, avgCorrs))
     {
      Print("❌ Échec du parsing JSON.");
      return;
     }

   int total = ArraySize(symbols);
   if(total == 0)
     {
      Print("❌ Aucune paire à traiter.");
      return;
     }

   // 3) Boucler sur chaque paire pour ouvrir/ajuster la position
   for(int i=0; i<total; i++)
     {
      string sym  = symbols[i];
      double corr = avgCorrs[i];

      // 3.1) Vérifier que le symbole est chargé dans Market Watch
      if(!SymbolSelect(sym, true))
        {
         PrintFormat("❌ Symbole indisponible : %s", sym);
         continue;
        }

      // 3.2) Déterminer la direction voulue
      ENUM_ORDER_TYPE desiredOrder = (corr >= 0.0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

      // 3.3) Vérifier s'il y a déjà une position ouverte sur ce symbole
      ulong existingTicket = 0;
      ENUM_POSITION_TYPE existingType;
      bool hasPos = GetExistingPosition(sym, existingTicket, existingType);

      if(hasPos)
        {
         // Si la position existante est DU MÊME TYPE (BUY vs SELL),
         // on ne fait rien : on considère la position déjà conforme.
         if((existingType == POSITION_TYPE_BUY && desiredOrder == ORDER_TYPE_BUY) ||
            (existingType == POSITION_TYPE_SELL && desiredOrder == ORDER_TYPE_SELL))
           {
            PrintFormat("⏳ %s déjà en position (%s), pas d’action.", sym,
                        (existingType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
            continue;
           }
         // Si la position existante est dans le SENS OPPOSÉ, on la ferme d'abord
         else
           {
            PrintFormat("🔄 %s : position existante %s mais on souhaite %s → fermeture d'abord.",
                        sym,
                        (existingType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                        (desiredOrder == ORDER_TYPE_BUY ? "BUY" : "SELL"));

            // Fermer l’ancienne position
            if(!ClosePositionByTicket(existingTicket))
            {
               PrintFormat("❌ Impossible de fermer la position existante sur %s. On passe au suivant.", sym);
               continue;
            }
            // Attendre un court instant pour laisser le broker traiter la clôture
            Sleep(2000);
           }
        }

      // 3.4) À ce stade, soit il n'y avait aucune position, soit on vient de fermer l'opposée.
      // On ouvre le nouvel ordre dans le sens "desiredOrder"
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double price, sl_price;

      if(desiredOrder == ORDER_TYPE_BUY)
        {
         price    = SymbolInfoDouble(sym, SYMBOL_ASK);
         sl_price = price - SL_POINTS * point;
        }
      else
        {
         price    = SymbolInfoDouble(sym, SYMBOL_BID);
         sl_price = price + SL_POINTS * point;
        }
      sl_price = NormalizeDouble(sl_price, digits);

      bool ok = false;
      if(desiredOrder == ORDER_TYPE_BUY)
         ok = trade.Buy(FIXED_VOLUME, sym, price, sl_price, 0.0);
      else
         ok = trade.Sell(FIXED_VOLUME, sym, price, sl_price, 0.0);

      if(ok)
        {
         PrintFormat("✅ %s %s : Vol=%.2f, Corr=%.3f, SL=%.%df",
                     (desiredOrder == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     sym, FIXED_VOLUME, corr, digits);
        }
      else
        {
         PrintFormat("❌ Échec %s %s : %s",
                     (desiredOrder == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     sym, trade.ResultComment());
        }

      // 3.5) Pause avant le prochain ordre
      Sleep(PAUSE_MS);
     }

   Print("🏁 Script terminé");
  }
//+------------------------------------------------------------------+
