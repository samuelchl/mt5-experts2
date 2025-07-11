//+------------------------------------------------------------------+
//|                                         TestApiSymbolsMT5.mq5    |
//|  Script MQL5 : récupère les corrélations depuis l'API JSON,      |
//|   détecte dynamiquement les symboles, affiche leur nombre, puis  |
//|   vérifie si chaque symbole est disponible dans MT5 (Market Watch)|
//+------------------------------------------------------------------+
#property copyright "Exemple by ChatGPT"
#property version   "1.00"
#property script_show_inputs

#include <Trade\Trade.mqh>    // pour CTrade (même si on ne trade pas ici, c'est un include standard)

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
//| Fonction pour parser un objet JSON simple                        |
//+------------------------------------------------------------------+
bool ParseJsonObject(const string json_str, string &symbols[])
  {
   ArrayResize(symbols, 0);
   
   // Recherche simple de patterns dans le JSON
   // Cette approche basique fonctionne pour la structure de données attendue
   int pos = 0;
   string search_key = "\"data\":";
   int data_pos = StringFind(json_str, search_key);
   if(data_pos == -1)
     {
      Print("❌ Champ 'data' non trouvé dans le JSON");
      return false;
     }
   
   // Commencer après "data":{
   pos = data_pos + StringLen(search_key);
   
   // Extraire les clés principales (symboles)
   while(pos < StringLen(json_str))
     {
      // Chercher les guillemets ouvrants pour les clés
      int quote_start = StringFind(json_str, "\"", pos);
      if(quote_start == -1) break;
      
      quote_start++; // Passer le guillemet ouvrant
      int quote_end = StringFind(json_str, "\"", quote_start);
      if(quote_end == -1) break;
      
      string potential_symbol = StringSubstr(json_str, quote_start, quote_end - quote_start);
      
      // Vérifier si c'est un symbole de devise (format basique)
      if(StringLen(potential_symbol) >= 6 && 
         StringFind(potential_symbol, "USD") != -1 || 
         StringFind(potential_symbol, "EUR") != -1 ||
         StringFind(potential_symbol, "GBP") != -1 ||
         StringFind(potential_symbol, "JPY") != -1 ||
         StringFind(potential_symbol, "CHF") != -1 ||
         StringFind(potential_symbol, "CAD") != -1 ||
         StringFind(potential_symbol, "AUD") != -1 ||
         StringFind(potential_symbol, "NZD") != -1)
        {
         if(!IsStringInArray(symbols, potential_symbol))
           {
            int new_size = ArraySize(symbols) + 1;
            ArrayResize(symbols, new_size);
            symbols[new_size - 1] = potential_symbol;
           }
        }
      
      pos = quote_end + 1;
     }
   
   return ArraySize(symbols) > 0;
  }

//+------------------------------------------------------------------+
//| Programme principal du script                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   // 1) --- Appel HTTP pour récupérer le JSON depuis l'API ----------
   string url = "https://macrofinder.flolep.fr/api/assets/correlations";
   string headers = "";
   int timeout = 5000;
   char request_data[];
   char result_bytes[];
   string response_headers;
   
   Print("🔄 Tentative de connexion à l'API...");
   
   int res = WebRequest(
                    "GET",
                    url,
                    headers,
                    timeout,
                    request_data,
                    result_bytes,
                    response_headers
                );
                
   if(res == -1)
     {
      int error_code = GetLastError();
      PrintFormat("❌ ERREUR WebRequest() : code=%d. Vérifiez l'URL et l'autorisation WebRequest dans MT5.", error_code);
      PrintFormat("💡 Conseil : Ajoutez l'URL dans Outils > Options > Expert Advisors > 'Autoriser WebRequest pour les URL suivantes'");
      return;
     }

   // Convertir les octets reçus en string JSON
   string response = CharArrayToString(result_bytes);
   if(StringLen(response) == 0)
     {
      Print("❌ ERREUR : Réponse vide de l'API.");
      return;
     }

   Print("✅ Réponse reçue de l'API");
   PrintFormat("📊 Taille de la réponse : %d caractères", StringLen(response));

   // 2) --- Parser le JSON avec méthode simplifiée ----------
   string symbols[];
   if(!ParseJsonObject(response, symbols))
     {
      Print("❌ ERREUR : Impossible de parser le JSON ou aucun symbole trouvé.");
      Print("🔍 Début de la réponse JSON :");
      Print(StringSubstr(response, 0, MathMin(500, StringLen(response))));
      return;
     }

   // 3) --- Afficher le nombre de devises trouvées --------------------
   int totalSymbols = ArraySize(symbols);
   PrintFormat("ℹ️ Nombre total de symboles détectés dans JSON : %d", totalSymbols);

   if(totalSymbols == 0)
     {
      Print("⚠️ Aucun symbole de devise détecté dans la réponse JSON");
      return;
     }

   // 4) --- Vérifier si chaque symbole est disponible dans MT5 ----------
   Print("🔍 Vérification de la disponibilité des symboles dans MT5 :");
   
   int available_count = 0;
   int unavailable_count = 0;
   
   for(int k = 0; k < totalSymbols; k++)
     {
      string sym = symbols[k];
      bool selectable = SymbolSelect(sym, true);
      
      if(selectable)
        {
         PrintFormat("✅ Symbole disponible dans MT5 : %s", sym);
         available_count++;
        }
      else
        {
         PrintFormat("❌ Symbole NON disponible dans MT5 : %s", sym);
         unavailable_count++;
        }
     }
   
   Print("📈 Résumé :");
   PrintFormat("  • Symboles disponibles : %d", available_count);
   PrintFormat("  • Symboles non disponibles : %d", unavailable_count);
   PrintFormat("  • Total analysé : %d", totalSymbols);
  }
//+------------------------------------------------------------------+