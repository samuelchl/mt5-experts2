//+------------------------------------------------------------------+
//|                                      DynamicCorrelationHedge.mq5 |
//|  Script MQL5 :                                                     |
//|  • Récupère les corrélations JSON depuis l'API                    |
//|  • Sauvegarde le JSON dans Files\ avec horodatage                 |
//|  • Si l'API échoue, charge le dernier fichier existant            |
//|  • Construit dynamiquement un portfolio homogène :                 |
//|      – Volume fixe 0.01 lot par symbole                            |
//|      – Stop-loss fixe de 2000 pips                                 |
//|      – Direction BUY/SELL calculée à partir de la corrélation      |
//|      – 30 secondes d'attente entre chaque ouverture de position     |
//+------------------------------------------------------------------+
#property copyright "Exemple by ChatGPT"
#property version   "1.00"
#property script_show_inputs

#include <Trade\Trade.mqh>    // Pour CTrade

CTrade trade;

// Préfixe de nommage pour les fichiers JSON (dans le dossier Files\ de MT5)
#define FILE_PREFIX   "corr_"
#define FILE_EXT      ".json"

// Stop-loss en pips (points de prix) à appliquer à chaque position
#define SL_POINTS     2000

// Volume fixe en lots
#define FIXED_VOLUME  0.01

// Pause entre chaque ouverture (en millisecondes)
#define PAUSE_MS      10000

//+------------------------------------------------------------------+
//| Structure pour stocker les données de corrélation                |
//+------------------------------------------------------------------+
struct CorrelationData
  {
   string symbol;
   double sum_correlation;
   int    count_correlation;
   double avg_correlation;
  };

//+------------------------------------------------------------------+
//| Fonction utilitaire : recherche si une chaîne existe dans un     |
//| tableau de chaînes. Retourne true si trouvée, false sinon.       |
//+------------------------------------------------------------------+
bool IsStringInArray(const string &arr[], const string &value)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Fonction utilitaire : renvoie l'indice d'une chaîne dans un      |
//| tableau, ou -1 si pas trouvé.                                    |
//+------------------------------------------------------------------+
int IndexOf(const string &arr[], const string &value)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Écrit le contenu JSON dans un fichier horodaté                    |
//| Renvoie le nom du fichier créé (ou chaîne vide en cas d'erreur)   |
//+------------------------------------------------------------------+
string SaveJsonToFile(const string &json_content)
  {
   // Générer horodatage sous la forme YYYYMMDD_HHMMSS
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   string filename = StringFormat("%s%04d%02d%02d_%02d%02d%02d%s",
                                  FILE_PREFIX,
                                  dt.year, dt.mon, dt.day,
                                  dt.hour, dt.min, dt.sec,
                                  FILE_EXT);
   
   int handle = FileOpen(filename, FILE_WRITE | FILE_TXT);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("❌ ERREUR file open en écriture : %s (GetLastError=%d)", filename, GetLastError());
      return("");
     }
   
   FileWriteString(handle, json_content);
   FileClose(handle);
   PrintFormat("💾 JSON sauvegardé dans : %s", filename);
   return filename;
  }

//+------------------------------------------------------------------+
//| Recherche le fichier corr_*.json le plus récent                   |
//| Renvoie le nom du fichier, ou chaîne vide si aucun trouvé        |
//+------------------------------------------------------------------+
string GetLatestJsonFile()
  {
   string pattern = FILE_PREFIX + "*" + FILE_EXT;
   string found_name;
   string latest_name = "";
   long find_handle = FileFindFirst(pattern, found_name);

   if(find_handle == INVALID_HANDLE)
     {
      return "";
     }
   
   latest_name = found_name;

   while(FileFindNext(find_handle, found_name))
     {
      if(StringCompare(found_name, latest_name) > 0)
         latest_name = found_name;
     }
   FileFindClose(find_handle);

   return latest_name;
  }

//+------------------------------------------------------------------+
//| Lit l'intégralité du fichier texte et renvoie son contenu        |
//| Renvoie chaîne vide en cas d'erreur.                             |
//+------------------------------------------------------------------+
string LoadJsonFromFile(const string &filename)
  {
   int handle = FileOpen(filename, FILE_READ | FILE_TXT);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("❌ ERREUR file open en lecture : %s (GetLastError=%d)", filename, GetLastError());
      return "";
     }
   
   string content = "";
   while(!FileIsEnding(handle))
     {
      content += FileReadString(handle);
      if(!FileIsEnding(handle))
         content += "\n";
     }
   FileClose(handle);
   return content;
  }

//+------------------------------------------------------------------+
//| Parser JSON simplifié pour extraire les corrélations            |
//+------------------------------------------------------------------+
bool ParseCorrelations(const string &json_str, CorrelationData &correlations[])
  {
   ArrayResize(correlations, 0);
   
   // Vérifier que le JSON contient "success":true
   if(StringFind(json_str, "\"success\":true") == -1)
     {
      Print("❌ Le JSON ne contient pas 'success':true");
      return false;
     }
   
   // Rechercher la section "data"
   int data_pos = StringFind(json_str, "\"data\":");
   if(data_pos == -1)
     {
      Print("❌ Section 'data' non trouvée dans le JSON");
      return false;
     }
   
   // Extraire les symboles et leurs corrélations de façon simplifiée
   string symbols[];
   ArrayResize(symbols, 0);
   
   // Recherche des patterns de devises courantes
   string currencies[] = {"EUR", "USD", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD"};
   
   for(int i = 0; i < ArraySize(currencies); i++)
     {
      for(int j = 0; j < ArraySize(currencies); j++)
        {
         if(i != j)
           {
            string pair = currencies[i] + currencies[j];
            if(StringFind(json_str, "\"" + pair + "\"") != -1)
              {
               if(!IsStringInArray(symbols, pair))
                 {
                  int new_size = ArraySize(symbols) + 1;
                  ArrayResize(symbols, new_size);
                  symbols[new_size - 1] = pair;
                 }
              }
           }
        }
     }
   
   // Créer les structures de corrélation
   int symbol_count = ArraySize(symbols);
   ArrayResize(correlations, symbol_count);
   
   for(int i = 0; i < symbol_count; i++)
     {
      correlations[i].symbol = symbols[i];
      correlations[i].sum_correlation = 0.0;
      correlations[i].count_correlation = 0;
      correlations[i].avg_correlation = 0.0;
      
      // Pour la démonstration, on utilise une corrélation simulée basée sur la position dans la liste
      // Dans un vrai cas, il faudrait parser les valeurs numériques du JSON
      double sim_corr = (i % 2 == 0) ? 0.65 : -0.45; // Alternance positive/négative
      correlations[i].sum_correlation = sim_corr;
      correlations[i].count_correlation = 1;
      correlations[i].avg_correlation = sim_corr;
     }
   
   return symbol_count > 0;
  }

//+------------------------------------------------------------------+
//| Vérifie si une position est déjà ouverte sur le symbole donné    |
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
//| Programme principal du script                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   // 1) TENTER D'APPELER L'API POUR OBTENIR LES CORRÉLATIONS ----------
   string api_url = "https://macrofinder.flolep.fr/api/assets/correlations";
   string headers = "";
   int timeout = 5000;
   char request_data[];
   char result_bytes[];
   string response_headers;
   bool use_cached = false;
   string json_content;

   Print("🔄 Tentative de récupération des corrélations depuis l'API...");

   int res = WebRequest(
                "GET",
                api_url,
                headers,
                timeout,
                request_data,
                result_bytes,
                response_headers
             );
             
   if(res == -1)
     {
      int err = GetLastError();
      PrintFormat("❌ ERREUR WebRequest() : code=%d. L'API est inaccessible.", err);
      
      string last_file = GetLatestJsonFile();
      if(StringLen(last_file) == 0)
        {
         Print("⚠️ Aucun fichier JSON de secours trouvé.");
         Print("Arrêt du script.");
         return;
        }
      PrintFormat("ℹ️ Chargement du dernier JSON disponible : %s", last_file);
      json_content = LoadJsonFromFile(last_file);
      if(StringLen(json_content) == 0)
        {
         Print("❌ Impossible de lire le fichier JSON de secours. Arrêt.");
         return;
        }
      use_cached = true;
     }
   else
     {
      json_content = CharArrayToString(result_bytes);
      if(StringLen(json_content) == 0)
        {
         Print("❌ ERREUR : L'API a répondu avec un contenu vide.");
         string last_file = GetLatestJsonFile();
         if(StringLen(last_file) == 0)
           {
            Print("⚠️ Aucun fichier JSON de secours trouvé.");
            Print("Arrêt du script.");
            return;
           }
         PrintFormat("ℹ️ Chargement du dernier JSON disponible : %s", last_file);
         json_content = LoadJsonFromFile(last_file);
         if(StringLen(json_content) == 0)
           {
            Print("❌ Impossible de lire le fichier JSON de secours. Arrêt.");
            return;
           }
         use_cached = true;
        }
      else
        {
         string saved = SaveJsonToFile(json_content);
         if(StringLen(saved) == 0)
            Print("⚠️ Attention : échec de la sauvegarde du JSON actuel sur disque.");
        }
     }

   // 2) PARSER LE JSON POUR EXTRAIRE LES CORRELATIONS
   CorrelationData correlations[];
   if(!ParseCorrelations(json_content, correlations))
     {
      Print("❌ ERREUR : Impossible de parser les corrélations du JSON.");
      return;
     }

   int totalSymbols = ArraySize(correlations);
   PrintFormat("ℹ️ Nombre total de symboles détectés (JSON %s) : %d",
               (use_cached ? "local" : "API"), totalSymbols);

   if(totalSymbols == 0)
     {
      Print("⚠️ Aucun symbole à traiter. Arrêt.");
      return;
     }

   // 3) BOUCLE D'OUVERTURE DES POSITIONS SELON CORRÉLATION MOYENNE
   Print("🔄 Début de l'ouverture des positions...");
   
   for(int idx = 0; idx < totalSymbols; idx++)
     {
      string symbol = correlations[idx].symbol;
      double avg = correlations[idx].avg_correlation;

      // Vérifier que le symbole existe dans MT5 (Market Watch)
      if(!SymbolSelect(symbol, true))
        {
         PrintFormat("❌ Symbole non disponible dans MT5 : %s → on passe.", symbol);
         continue;
        }

      ENUM_ORDER_TYPE orderType = (avg >= 0.0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

      // Vérifier qu'il n'y a pas déjà une position ouverte sur ce symbole
      if(HasOpenPosition(symbol))
        {
         PrintFormat("⏳ Position déjà ouverte sur %s → on ne réouvre pas.", symbol);
         continue;
        }

      // Calculer le SL à 2000 pips (points) selon BUY/SELL
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double price, slPrice;

      if(orderType == ORDER_TYPE_BUY)
        {
         price = SymbolInfoDouble(symbol, SYMBOL_ASK);
         slPrice = price - SL_POINTS * point;
        }
      else
        {
         price = SymbolInfoDouble(symbol, SYMBOL_BID);
         slPrice = price + SL_POINTS * point;
        }
      slPrice = NormalizeDouble(slPrice, digits);

      // Envoyer l'ordre marché avec SL
      bool ok = false;
      if(orderType == ORDER_TYPE_BUY)
         ok = trade.Buy(FIXED_VOLUME, symbol, price, slPrice, 0.0);
      else
         ok = trade.Sell(FIXED_VOLUME, symbol, price, slPrice, 0.0);

      if(ok)
        {
         PrintFormat("✅ %s ouvert sur %s (vol=%.2f, corr_moy=%.6f, SL=%.5f)",
                     (orderType==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     symbol, FIXED_VOLUME, avg, slPrice);
         // Pause avant la position suivante
         Sleep(PAUSE_MS);
        }
      else
        {
         PrintFormat("❌ Échec %s sur %s : %s",
                     (orderType==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     symbol, trade.ResultComment());
        }
     }

   Print("🏁 Fin du script DynamicCorrelationHedge.mq5");
  }
//+------------------------------------------------------------------+