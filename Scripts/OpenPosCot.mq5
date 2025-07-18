//+------------------------------------------------------------------+
//|                         OpenPosCot.mq5                            |
//|  Script MQL5 : Combine corrélations et données COT pour ouvrir   |
//|               0.01 lot sur chaque paire, ajuster selon COT et   |
//|               corrélation, gérer positions existantes            |
//+------------------------------------------------------------------+
#property copyright "ChatGPT"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Paramètres généraux
#define SL_POINTS    2000   // Stop‐loss en points (2000 points = 200 pips)
#define FIXED_VOLUME 0.01   // Volume fixe par paire
#define PAUSE_MS     30000  // Pause entre ordres (30 secondes)

//+------------------------------------------------------------------+
//| Recherche si une chaîne existe dans un tableau de chaînes        |
//+------------------------------------------------------------------+
bool IsStringInArray(const string &arr[], const string &value)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Retourne l’indice d’une chaîne dans un tableau, ou -1 si absent  |
//+------------------------------------------------------------------+
int IndexOf(const string &arr[], const string &value)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Extrait un sous‐objet JSON {…} pour la clé “key”                 |
//+------------------------------------------------------------------+
string ExtractJsonObject(const string &json, const string &key)
  {
   string search_pattern = "\"" + key + "\"";
   int start_pos = StringFind(json, search_pattern);
   if(start_pos == -1) return "";
   start_pos = StringFind(json, ":", start_pos);
   if(start_pos == -1) return "";
   start_pos++;
   while(start_pos < StringLen(json) && (StringGetCharacter(json, start_pos) == ' ' || StringGetCharacter(json, start_pos) == '\t'))
      start_pos++;
   if(StringGetCharacter(json, start_pos) != '{') return "";
   int brace_count = 1;
   int end_pos = start_pos + 1;
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
//| Parse toutes les corrélations et calcule la corrélation moyenne |
//+------------------------------------------------------------------+
bool ParseAllAvgCorrelations(const string &json, string &symbols[], double &avgCorrs[])
  {
   // Vérifier "success":true
   if(StringFind(json, "\"success\":true") == -1 && StringFind(json, "\"success\": true") == -1)
     {
      Print("❌ JSON corrélations invalide (“success” != true)");
      return false;
     }

   // Extraire l’objet “data”
   string data_obj = ExtractJsonObject(json, "data");
   if(StringLen(data_obj) == 0)
     {
      Print("❌ Impossible d’extraire l’objet “data” du JSON corrélations.");
      return false;
     }

   // 1) Collecter toutes les clés (paires) au premier niveau de data_obj
   ArrayResize(symbols, 0);
   int pos = 0;
   while(true)
     {
      int q1 = StringFind(data_obj, "\"", pos);
      if(q1 == -1) break;
      int q2 = StringFind(data_obj, "\"", q1 + 1);
      if(q2 == -1) break;
      string sym = StringSubstr(data_obj, q1 + 1, q2 - (q1 + 1));
      if(StringLen(sym) >= 6)
        {
         if(!IsStringInArray(symbols, sym))
           {
            int n = ArraySize(symbols) + 1;
            ArrayResize(symbols, n);
            symbols[n - 1] = sym;
           }
        }
      pos = q2 + 1;
     }

   int total = ArraySize(symbols);
   if(total == 0)
     {
      Print("❌ Aucune paire détectée dans l’objet “data” du JSON corrélations.");
      return false;
     }

   // 2) Préparer tableaux pour somme et comptage des corrélations
   double sumCorrs[];   ArrayResize(sumCorrs, total);
   int    countCorrs[]; ArrayResize(countCorrs, total);
   for(int i = 0; i < total; i++)
     {
      sumCorrs[i] = 0.0;
      countCorrs[i] = 0;
     }

   // 3) Parcourir à nouveau data_obj pour extraire chaque bloc { "sym": {…} }
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
      int brace_count = 1;
      int idx = brace_open + 1;
      while(idx < StringLen(data_obj) && brace_count > 0)
        {
         ushort c = StringGetCharacter(data_obj, idx);
         if(c == '{') brace_count++;
         else if(c == '}') brace_count--;
         idx++;
        }
      if(brace_count != 0) break;

      string inner = StringSubstr(data_obj, brace_open, idx - brace_open);

      // Lire toutes les paires “clé:valeur” dans inner
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
            sumCorrs[ibase] += val;
            countCorrs[ibase]++;
            sumCorrs[icorr] += val;
            countCorrs[icorr]++;
           }
        }

      pos = idx;
     }

   // 4) Calculer corrélation moyenne pour chaque paire
   ArrayResize(avgCorrs, total);
   for(int i = 0; i < total; i++)
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
//| Parse les données COT (Commitments of Traders)                   |
//+| Remplit :                                                        |
//+| - cotAssets[]    : code devise (ex. "EUR", "USD", ...)           |
//+| - cotLongPct[]   : % of OI noncomm_positions_long_all            |
//+| - cotShortPct[]  : % of OI noncomm_positions_short_all           |
//+------------------------------------------------------------------+
bool ParseCOTData(const string &json, string &cotAssets[], double &cotLongPct[], double &cotShortPct[])
  {
   // 1) Vérifier "success":true
   if(StringFind(json, "\"success\":true") == -1 && StringFind(json, "\"success\": true") == -1)
     {
      Print("❌ JSON COT invalide (\"success\" != true)");
      return false;
     }

   // 2) Trouver le début du tableau "data":[ … ]
   int dataPos = StringFind(json, "\"data\"");
   if(dataPos == -1)
     {
      Print("❌ Clé “data” non trouvée dans le JSON COT.");
      return false;
     }
   int bracketStart = StringFind(json, "[", dataPos);
   if(bracketStart == -1)
     {
      Print("❌ Crochet ouvrant '[' introuvable pour “data”.");
      return false;
     }

   // 3) Trouver la fin du tableau, en gérant la profondeur des crochets
   int depth = 1;
   int idx = bracketStart + 1;
   while(idx < StringLen(json) && depth > 0)
     {
      ushort c = StringGetCharacter(json, idx);
      if(c == '[') depth++;
      else if(c == ']') depth--;
      idx++;
     }
   if(depth != 0)
     {
      Print("❌ Crochets imbalancés dans “data” du JSON COT.");
      return false;
     }
   // Extraire la sous-chaine “[ {...}, {...}, ... ]”
   string arrayData = StringSubstr(json, bracketStart, idx - bracketStart);

   // 4) Parcourir chaque objet { … } dans ce tableau
   ArrayResize(cotAssets,   0);
   ArrayResize(cotLongPct,  0);
   ArrayResize(cotShortPct, 0);

   int pos2 = 0;
   while(true)
     {
      int objStart = StringFind(arrayData, "{", pos2);
      if(objStart == -1) break;
      int brace_count = 1;
      int j = objStart + 1;
      while(j < StringLen(arrayData) && brace_count > 0)
        {
         ushort ch = StringGetCharacter(arrayData, j);
         if(ch == '{') brace_count++;
         else if(ch == '}') brace_count--;
         j++;
        }
      if(brace_count != 0) break;
      string obj = StringSubstr(arrayData, objStart, j - objStart);

      // Extraire "asset"
      string assetCode = "";
      int keyA = StringFind(obj, "\"asset\"");
      if(keyA != -1)
        {
         int colon = StringFind(obj, ":", keyA);
         if(colon != -1)
           {
            int q1 = StringFind(obj, "\"", colon + 1);
            int q2 = StringFind(obj, "\"", q1 + 1);
            if(q1 != -1 && q2 != -1)
               assetCode = StringSubstr(obj, q1 + 1, q2 - (q1 + 1));
           }
        }

      // Extraire pct_of_oi_noncomm_long_all
      double longPct = 0.0;
      int keyL = StringFind(obj, "\"pct_of_oi_noncomm_long_all\"");
      if(keyL != -1)
        {
         int colon = StringFind(obj, ":", keyL);
         if(colon != -1)
           {
            int p = colon + 1;
            while(p < StringLen(obj) && (StringGetCharacter(obj, p) == ' ' || StringGetCharacter(obj, p) == '\t')) p++;
            string num = "";
            while(p < StringLen(obj))
              {
               ushort ch = StringGetCharacter(obj, p);
               if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
                 {
                  num += CharToString((uchar)ch);
                  p++;
                 }
               else break;
              }
            longPct = StringToDouble(num);
           }
        }

      // Extraire pct_of_oi_noncomm_short_all
      double shortPct = 0.0;
      int keyS = StringFind(obj, "\"pct_of_oi_noncomm_short_all\"");
      if(keyS != -1)
        {
         int colon = StringFind(obj, ":", keyS);
         if(colon != -1)
           {
            int p = colon + 1;
            while(p < StringLen(obj) && (StringGetCharacter(obj, p) == ' ' || StringGetCharacter(obj, p) == '\t')) p++;
            string num = "";
            while(p < StringLen(obj))
              {
               ushort ch = StringGetCharacter(obj, p);
               if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
                 {
                  num += CharToString((uchar)ch);
                  p++;
                 }
               else break;
              }
            shortPct = StringToDouble(num);
           }
        }

      // Ajouter aux tableaux si assetCode valide
      if(StringLen(assetCode) > 0)
        {
         int existing = IndexOf(cotAssets, assetCode);
         if(existing == -1)
           {
            int n = ArraySize(cotAssets) + 1;
            ArrayResize(cotAssets,   n);
            ArrayResize(cotLongPct,  n);
            ArrayResize(cotShortPct, n);
            cotAssets[n - 1]   = assetCode;
            cotLongPct[n - 1]  = longPct;
            cotShortPct[n - 1] = shortPct;
           }
         else
           {
            // Si doublon, on écrase par la valeur actuelle
            cotLongPct[existing]  = longPct;
            cotShortPct[existing] = shortPct;
           }
        }

      pos2 = j;
     }

   if(ArraySize(cotAssets) == 0)
     {
      Print("❌ Aucune entrée COT valide trouvée.");
      return false;
     }

   PrintFormat("✅ %d actifs COT extraits.", ArraySize(cotAssets));
   return true;
  }

//+------------------------------------------------------------------+
//| Récupère la position existante sur un symbole, retourne ticket   |
//| et type (POSITION_TYPE_BUY ou POSITION_TYPE_SELL).               |
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
//| Ferme la position identifiée par “ticket” (ouvre l’inverse)      |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   string sym     = PositionGetString(POSITION_SYMBOL);
   double vol     = PositionGetDouble(POSITION_VOLUME);
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
//| Vérifie si une position existe déjà sur le symbole donné         |
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
//| Programme principal                                              |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("▶️ Début : OpenPosCot.mq5");

   // 1) Récupérer JSON corrélations
   string urlCorr = "https://macrofinder.flolep.fr/api/assets/correlations";
   char   req1[], res1[];
   string hdr1;
   int    r1 = WebRequest("GET", urlCorr, "", 5000, req1, res1, hdr1);
   if(r1 == -1)
     {
      PrintFormat("❌ WebRequest corrélations échouée (GetLastError=%d)", GetLastError());
      return;
     }
   string jsonCorr = CharArrayToString(res1);
   if(StringLen(jsonCorr) == 0)
     {
      Print("❌ JSON corrélations vide.");
      return;
     }

   // 2) Récupérer JSON COT (dernières données)
   string urlCOT = "https://macrofinder.flolep.fr/api/cot/latest";
   char   req2[], res2[];
   string hdr2;
   int    r2 = WebRequest("GET", urlCOT, "", 5000, req2, res2, hdr2);
   if(r2 == -1)
     {
      PrintFormat("❌ WebRequest COT échouée (GetLastError=%d)", GetLastError());
      return;
     }
   string jsonCOT = CharArrayToString(res2);
   if(StringLen(jsonCOT) == 0)
     {
      Print("❌ JSON COT vide.");
      return;
     }

   // 3) Parser corrélations moyennes
   string symbols[];
   double avgCorrs[];
   if(!ParseAllAvgCorrelations(jsonCorr, symbols, avgCorrs))
     {
      Print("❌ Échec parsing corrélations.");
      return;
     }

   // 4) Parser données COT
   string cotAssets[];
   double cotLongPct[], cotShortPct[];
   if(!ParseCOTData(jsonCOT, cotAssets, cotLongPct, cotShortPct))
     {
      Print("❌ Échec parsing COT.");
      return;
     }

   int totalPairs = ArraySize(symbols);
   if(totalPairs == 0)
     {
      Print("❌ Aucune paire extraite.");
      return;
     }

   // 5) Pour chaque paire, calculer “combinedScore” puis ouvrir/ajuster position
   for(int i = 0; i < totalPairs; i++)
     {
      string sym  = symbols[i];    // ex. "EURUSD"
      double corr = avgCorrs[i];   // corrélation moyenne

      // 5.1) Extraire “base” et “quote”
      string baseCur  = StringSubstr(sym, 0, 3);  // ex. "EUR"
      string quoteCur = StringSubstr(sym, 3, 3);  // ex. "USD"

      // 5.2) Récupérer index dans cotAssets[]
      int idxBase  = IndexOf(cotAssets, baseCur);
      int idxQuote = IndexOf(cotAssets, quoteCur);

      // 5.3) Calculer bias pour chaque devise (long% − short%)
      double biasBase  = (idxBase  >= 0) ? cotLongPct[idxBase]  - cotShortPct[idxBase]  : 0.0;
      double biasQuote = (idxQuote >= 0) ? cotLongPct[idxQuote] - cotShortPct[idxQuote] : 0.0;

      // 5.4) Score COT de la paire = biasBase − biasQuote
      double biasPair = biasBase - biasQuote;  // ex. +20 → pression haussière sur base/quote

      // 5.5) Combine corrélation (±1) et COT (converted to ±1)
      double weightCorr = corr;               // déjà en ≈[−1,+1]
      double weightCOT  = biasPair / 100.0;   // si biasPair = +20%, → +0.20
      double combinedScore = 0.5 * weightCorr + 0.5 * weightCOT;

      // 5.6) Déterminer sens souhaité (SELL si combinedScore ≥ 0, sinon BUY)
      ENUM_ORDER_TYPE desiredOrder = (combinedScore >= 0.0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

      // 5.7) Vérifier que le symbole est disponible dans Market Watch
      if(!SymbolSelect(sym, true))
        {
         PrintFormat("❌ Symbole indisponible : %s", sym);
         continue;
        }

      // 5.8) Vérifier présence d’une position existante
      ulong existingTicket = 0;
      ENUM_POSITION_TYPE existingType;
      bool hasPos = GetExistingPosition(sym, existingTicket, existingType);

      if(hasPos)
        {
         // Si position existante DU MÊME SENS → rien à faire
         if((existingType == POSITION_TYPE_BUY && desiredOrder == ORDER_TYPE_BUY) ||
            (existingType == POSITION_TYPE_SELL && desiredOrder == ORDER_TYPE_SELL))
           {
            PrintFormat("⏳ %s déjà en %s → pas de modification. (corr=%.3f, bias=%.1f%%, combo=%.3f)",
                        sym,
                        (existingType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                        corr, biasPair, combinedScore);
            continue;
           }
         // Si position existante sens opposé → fermer d'abord
         PrintFormat("🔄 %s : position existante %s, desired=%s → fermeture.",
                     sym,
                     (existingType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     (desiredOrder == ORDER_TYPE_BUY    ? "BUY" : "SELL"));

         if(!ClosePositionByTicket(existingTicket))
           {
            PrintFormat("❌ Impossible de fermer la position existante sur %s. On passe.", sym);
            continue;
           }
         // Laisser 2s au broker pour traiter la clôture
         Sleep(2000);
        }

      // 5.9) Ouvrir le nouvel ordre
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
         PrintFormat("✅ %s %s : Vol=%.2f | corr=%.3f | bias=%.1f%% | combo=%.3f | SL=%.%df",
                     (desiredOrder == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     sym, FIXED_VOLUME, corr, biasPair, combinedScore, digits);
        }
      else
        {
         PrintFormat("❌ Échec %s %s : %s",
                     (desiredOrder == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     sym, trade.ResultComment());
        }

      // 5.10) Pause avant le prochain symbole
      Sleep(PAUSE_MS);
     }

   Print("🏁 Script terminé avec succès");
  }
//+------------------------------------------------------------------+
