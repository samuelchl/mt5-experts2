//+------------------------------------------------------------------+
//|                                    BalancedPortfolioHedge.mq5   |
//|  Script MQL5 : Portefeuille équilibré basé sur les corrélations  |
//|  • Exposition uniforme en devise de compte                       |
//|  • Pondération par force de corrélation                          |
//|  • Équilibrage automatique BUY/SELL                              |
//|  • Contrôle de l'exposition totale                               |
//|  • Optimisation risque/rendement                                  |
//+------------------------------------------------------------------+
#property copyright "Version Équilibrée"
#property version   "2.01"
#property script_show_inputs

#include <Trade\Trade.mqh>

// Paramètres du portefeuille équilibré
input double    TARGET_EXPOSURE     = 100.0;    // Exposition cible par position (devise de compte)
input double    MAX_PORTFOLIO_EXP   = 500.0;   // Exposition maximale du portefeuille
input double    MIN_CORRELATION     = 0.1;       // Corrélation minimale pour inclure (force)
input double    CORRELATION_WEIGHT  = 2.0;       // Multiplicateur de pondération
input int       SL_POINTS          = 1000;       // Stop Loss en points
input int       PAUSE_MS           = 10000;      // Pause entre positions (10s)
input bool      FORCE_BALANCE      = true;       // Forcer équilibrage BUY/SELL
input bool      ENABLE_HEDGING     = true;       // Activer les paires de couverture
input string    BASE_CURRENCY      = "EUR";      // Devise de base pour les corrélations

//MAX_PORTFOLIO_EXP  = 500.0    // Exposition totale max du portefeuille
//MIN_CORRELATION    = 0.5      // Ne choisir que les paires assez fortement corrélées
//CORRELATION_WEIGHT = 1.0      // Pas de sur‐pondération, on part sur un coefficient 1:1
//SL_POINTS          = 500      // Stop-loss réduit à 500 points (50 pips sur la plupart des paires)
//PAUSE_MS           = 1000     // Pause de 1 seconde entre chaque ordre
//FORCE_BALANCE      = false    // Ne pas forcer l’équilibre BUY/SELL dans un premier temps
//ENABLE_HEDGING     = false    // Désactiver la création automatique de paires de couverture
//BASE_CURRENCY      = "EUR"    // En supposant que votre compte est en EUR


CTrade trade;

// Préfixe pour fichiers JSON
#define FILE_PREFIX   "corr_"
#define FILE_EXT      ".json"

//+------------------------------------------------------------------+
//| Structure pour position équilibrée                               |
//+------------------------------------------------------------------+
struct BalancedPosition
  {
   string            symbol;
   double            correlation;
   double            weight;           // Poids basé sur la corrélation
   double            target_volume;    // Volume calculé
   double            exposure;         // Exposition réelle
   ENUM_ORDER_TYPE   direction;       // BUY ou SELL
   bool              is_hedge_pair;    // Fait partie d'une paire de couverture
   string            hedge_partner;    // Symbole partenaire pour hedging
  };

//+------------------------------------------------------------------+
//| Utilitaires de base                                              |
//+------------------------------------------------------------------+
bool IsStringInArray(const string &arr[], const string &value)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value) return true;
   return false;
  }

int IndexOf(const string &arr[], const string &value)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Utilitaires de parsing JSON                                      |
//+------------------------------------------------------------------+
string ExtractStringValue(const string &json, const string &key)
  {
   string search_pattern = "\"" + key + "\"";
   int start_pos = StringFind(json, search_pattern);
   if(start_pos == -1) return "";
   
   start_pos = StringFind(json, ":", start_pos);
   if(start_pos == -1) return "";
   
   start_pos++;
   while(start_pos < StringLen(json) && (StringGetCharacter(json, start_pos) == ' ' || StringGetCharacter(json, start_pos) == '\t'))
      start_pos++;
   
   if(StringGetCharacter(json, start_pos) == '"')
     {
      start_pos++;
      int end_pos = StringFind(json, "\"", start_pos);
      if(end_pos == -1) return "";
      return StringSubstr(json, start_pos, end_pos - start_pos);
     }
   
   return "";
  }

double ExtractDoubleValue(const string &json, const string &key)
  {
   string search_pattern = "\"" + key + "\"";
   int start_pos = StringFind(json, search_pattern);
   if(start_pos == -1) return 0.0;
   
   start_pos = StringFind(json, ":", start_pos);
   if(start_pos == -1) return 0.0;
   
   start_pos++;
   while(start_pos < StringLen(json) && (StringGetCharacter(json, start_pos) == ' ' || StringGetCharacter(json, start_pos) == '\t'))
      start_pos++;
   
   string number_str = "";
   while(start_pos < StringLen(json))
     {
      ushort char_code = StringGetCharacter(json, start_pos);
      if((char_code >= '0' && char_code <= '9') || char_code == '.' || char_code == '-')
        {
         number_str += CharToString((uchar)char_code);
         start_pos++;
        }
      else
         break;
     }
   
   return StringToDouble(number_str);
  }

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
      ushort char_code = StringGetCharacter(json, end_pos);
      if(char_code == '{') brace_count++;
      else if(char_code == '}') brace_count--;
      end_pos++;
     }
   
   if(brace_count == 0)
      return StringSubstr(json, start_pos, end_pos - start_pos);
   
   return "";
  }

//+------------------------------------------------------------------+
//| Gestion des fichiers JSON                                        |
//+------------------------------------------------------------------+
string SaveJsonToFile(const string &json_content)
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   string filename = StringFormat("%s%04d%02d%02d_%02d%02d%02d%s",
                                  FILE_PREFIX, dt.year, dt.mon, dt.day,
                                  dt.hour, dt.min, dt.sec, FILE_EXT);
   
   int handle = FileOpen(filename, FILE_WRITE | FILE_TXT);
   if(handle == INVALID_HANDLE) return "";
   
   FileWriteString(handle, json_content);
   FileClose(handle);
   PrintFormat("💾 JSON sauvegardé : %s", filename);
   return filename;
  }

string GetLatestJsonFile()
  {
   string pattern = FILE_PREFIX + "*" + FILE_EXT;
   string found_name, latest_name = "";
   long find_handle = FileFindFirst(pattern, found_name);
   
   if(find_handle == INVALID_HANDLE) return "";
   
   latest_name = found_name;
   while(FileFindNext(find_handle, found_name))
      if(StringCompare(found_name, latest_name) > 0)
         latest_name = found_name;
   
   FileFindClose(find_handle);
   return latest_name;
  }

string LoadJsonFromFile(const string &filename)
  {
   int handle = FileOpen(filename, FILE_READ | FILE_TXT);
   if(handle == INVALID_HANDLE) return "";
   
   string content = "";
   while(!FileIsEnding(handle))
     {
      content += FileReadString(handle);
      if(!FileIsEnding(handle)) content += "\n";
     }
   FileClose(handle);
   return content;
  }

//+------------------------------------------------------------------+
//| Calcul du volume normalisé par exposition                        |
//+------------------------------------------------------------------+
double CalculateNormalizedVolume(const string &symbol, double target_exposure)
  {
   // Obtenir la valeur d'un pip
   double pip_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Calculer la valeur d'un pip standard (0.0001 pour la plupart des paires)
   double standard_pip = (point * 10); // 1 pip = 10 points pour la plupart
   double pip_value_per_lot = pip_value / tick_size * standard_pip;
   
   // Volume pour atteindre l'exposition cible
   double volume = target_exposure / (pip_value_per_lot * 100); // 100 pips de référence
   
   // Normaliser selon les limites du symbole
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   volume = MathMax(volume, min_volume);
   volume = MathMin(volume, max_volume);
   volume = MathRound(volume / volume_step) * volume_step;
   
   return volume;
  }

//+------------------------------------------------------------------+
//| Parser JSON réel avec extraction des corrélations de l'API      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Récupère TOUTES les corrélations depuis l'API JSON et calcule   |
//| la corrélation moyenne par symbole.                              |
//| Remplit un tableau BalancedPosition[] avec symbol, corrélation   |
//| moyenne, weight, etc.                                            |
//+------------------------------------------------------------------+
bool ParseCorrelationsFromAPI(const string &json_str, BalancedPosition &positions[])
  {
   // 1) Vérifier que "success":true est bien présent
   if(StringFind(json_str, "\"success\":true") == -1 && StringFind(json_str, "\"success\": true") == -1)
     {
      Print("❌ JSON invalide : champ \"success\" non trouvé ou false");
      return false;
     }

   // 2) Extraire l'objet "data":
   string data_object = ExtractJsonObject(json_str, "data");
   if(StringLen(data_object) == 0)
     {
      Print("❌ Impossible d'extraire l'objet \"data\" du JSON.");
      return false;
     }

   // 3) Parcourir TOUTES les paires (clés de data) et les stocker
   //    dans un tableau dynamique de symboles, sans doublons.
   string allSymbols[];
   ArrayResize(allSymbols, 0);

   int pos = 0;
   while(true)
     {
      // Rechercher la prochaine accolade ouvrante '{' dans data_object
      int key_start = StringFind(data_object, "\"", pos);
      if(key_start == -1) break;
      int key_end = StringFind(data_object, "\"", key_start + 1);
      if(key_end == -1) break;

      // On extrait la sous-chaîne entre guillemets = le nom de la paire, ex. "AUDCAD"
      string sym = StringSubstr(data_object, key_start + 1, key_end - (key_start + 1));

      // Ignorer si ce n'est pas un symbole au format attendu (au moins 6 chars, lettres maj.)
// Si vous voulez un filtrage plus strict, vous pouvez vérifier que les 6 premières ou 3 premières sont un code de devise.
      if(StringLen(sym) >= 6)
        {
         if(!IsStringInArray(allSymbols, sym))
           {
            int newSize = ArraySize(allSymbols) + 1;
            ArrayResize(allSymbols, newSize);
            allSymbols[newSize - 1] = sym;
           }
        }

      pos = key_end + 1;
     }

   int totalSyms = ArraySize(allSymbols);
   if(totalSyms == 0)
     {
      Print("❌ Aucun symbole détecté dans \"data\".");
      return false;
     }

   // 4) Pour chaque symbole, nous allons accumuler ses corrélations vers TOUTES les autres
   //    On crée un tableau parallèle : mapCorrs[i] est une liste (string->double) pour allSymbols[i].
   double sumCorrs[];    // somme des corrélations
   int    countCorrs[];  // comptage du nombre de corrélations trouvées
   ArrayResize(sumCorrs, totalSyms);
   ArrayResize(countCorrs, totalSyms);
   for(int i = 0; i < totalSyms; i++)
     {
      sumCorrs[i] = 0.0;
      countCorrs[i] = 0;
     }

   // 5) Parcourir à nouveau data_object et extraire chaque paire de corrélations
   //    Structure du data_object (après ExtractJsonObject) : 
   //    "{ \"AUDCAD\":{ \"AUDCAD\":1, \"AUDCHF\":0.5895, …}, \"AUDCHF\": {…}, … }"
   pos = 0;
   while(true)
     {
      // Trouver la clé de base (ex. "AUDCAD") :
      int key_start = StringFind(data_object, "\"", pos);
      if(key_start == -1) break;
      int key_end = StringFind(data_object, "\"", key_start + 1);
      if(key_end == -1) break;

      string baseSym = StringSubstr(data_object, key_start + 1, key_end - (key_start + 1));
      pos = key_end + 1;

      // Rechercher l'accolade ouvrante de l'objet interne :
      int brace_open = StringFind(data_object, "{", pos);
      if(brace_open == -1) break;

      // Extrait l'objet complet pour cette paire : 
      int brace_count = 1;
      int idx       = brace_open + 1;
      while(idx < StringLen(data_object) && brace_count > 0)
        {
         ushort c = StringGetCharacter(data_object, idx);
         if(c == '{') brace_count++;
         else if(c == '}') brace_count--;
         idx++;
        }
      if(brace_count != 0) break; // déséquilibre des accolades : abort

      // La portion [brace_open … idx-1] contient { "AUDCAD":1, "AUDCHF":0.5895, ... }
      string inner = StringSubstr(data_object, brace_open, idx - brace_open);

      // 6) Dans cet "inner", extraire TOUTES les clés (corrSym) et leurs valeurs (corrVal)
      int innerPos = 0;
      while(true)
        {
         int ckey_start = StringFind(inner, "\"", innerPos);
         if(ckey_start == -1) break;
         int ckey_end = StringFind(inner, "\"", ckey_start + 1);
         if(ckey_end == -1) break;

         string corrSym = StringSubstr(inner, ckey_start + 1, ckey_end - (ckey_start + 1));
         innerPos = ckey_end + 1;

         // Trouver les deux points ":" après ckey_end
         int colonPos = StringFind(inner, ":", innerPos);
         if(colonPos == -1) break;
         innerPos = colonPos + 1;

         // Lire la valeur numérique (positif ou négatif, éventuellement décimal)
         string numstr = "";
         while(innerPos < StringLen(inner))
           {
            ushort ch = StringGetCharacter(inner, innerPos);
            if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
              {
               numstr += CharToString((uchar)ch);
               innerPos++;
              }
            else
               break;
           }
         double corrVal = StringToDouble(numstr);

         // 7) Ajouter cette corrélation à la moyenne de baseSym et de corrSym
         int idxBase = IndexOf(allSymbols, baseSym);
         int idxCorr = IndexOf(allSymbols, corrSym);

         if(idxBase >= 0 && idxCorr >= 0)
           {
            // On exclut la corrélation d'une paire avec elle-même (elle vaut 1, mais inutile pour le hedge)
            if(idxBase != idxCorr)
              {
               sumCorrs[idxBase]   += corrVal;
               countCorrs[idxBase]++;
               sumCorrs[idxCorr]   += corrVal;
               countCorrs[idxCorr]++;
              }
           }

         // Avance innerPos pour chercher la prochaine paire clé:valeur
        }

      // Avancer pos pour ne plus retomber sur la même clé  
      pos = idx;
     }

   // 8) Construire le tableau final positions[] avec symbol + corrélation moyenne + weight
   int finalCount = 0;
   for(int i = 0; i < totalSyms; i++)
     {
      if(countCorrs[i] > 0)
         finalCount++;
     }
   if(finalCount == 0)
     {
      Print("❌ Aucune corrélation hors self (1.0) n'a pu être calculée.");
      return false;
     }

   ArrayResize(positions, finalCount);
   int outIdx = 0;
   for(int i = 0; i < totalSyms; i++)
     {
      if(countCorrs[i] == 0) continue;

      double avgCorr = sumCorrs[i] / countCorrs[i];
      positions[outIdx].symbol           = allSymbols[i];
      positions[outIdx].correlation      = avgCorr;
      positions[outIdx].weight           = MathAbs(avgCorr) * CORRELATION_WEIGHT;
      positions[outIdx].target_volume    = 0.0;
      positions[outIdx].exposure         = 0.0;
      positions[outIdx].direction        = ORDER_TYPE_BUY;  // sera ajusté plus tard
      positions[outIdx].is_hedge_pair    = false;
      positions[outIdx].hedge_partner    = "";
      outIdx++;
     }

   PrintFormat("✅ %d paires chargées avec corrélation moyenne calculée.", finalCount);
   return true;
  }

//+------------------------------------------------------------------+
//| Optimisation de l'équilibrage du portefeuille                    |
//+------------------------------------------------------------------+
void OptimizePortfolioBalance(BalancedPosition &positions[])
  {
   int total_positions = ArraySize(positions);
   double total_exposure = 0.0;
   int buy_count = 0, sell_count = 0;
   
   Print("🔄 Optimisation de l'équilibrage du portefeuille...");
   
   // Phase 1: Filtrer par corrélation minimale et calculer volumes
   for(int i = 0; i < total_positions; i++)
     {
      if(MathAbs(positions[i].correlation) < MIN_CORRELATION)
        {
         positions[i].target_volume = 0.0; // Exclure
         PrintFormat("❌ Exclu (corrélation faible): %s (%.3f)", positions[i].symbol, positions[i].correlation);
         continue;
        }
      
      // Calculer volume basé sur exposition cible et pondération
      double base_volume = CalculateNormalizedVolume(positions[i].symbol, TARGET_EXPOSURE);
      positions[i].target_volume = base_volume * positions[i].weight;
      
      // Calculer exposition réelle
      double pip_value = SymbolInfoDouble(positions[i].symbol, SYMBOL_TRADE_TICK_VALUE);
      positions[i].exposure = positions[i].target_volume * pip_value * 100; // 100 pips de référence
      
      total_exposure += positions[i].exposure;
      PrintFormat("✅ Inclus: %s (corr=%.3f, poids=%.3f, vol=%.3f)", 
                  positions[i].symbol, positions[i].correlation, positions[i].weight, positions[i].target_volume);
     }
   
   // Phase 2: Ajuster si exposition totale dépasse la limite
   if(total_exposure > MAX_PORTFOLIO_EXP)
     {
      double reduction_factor = MAX_PORTFOLIO_EXP / total_exposure;
      PrintFormat("⚠️ Réduction de l'exposition totale : facteur %.3f", reduction_factor);
      
      for(int i = 0; i < total_positions; i++)
        {
         if(positions[i].target_volume > 0)
           {
            positions[i].target_volume *= reduction_factor;
            positions[i].exposure *= reduction_factor;
           }
        }
     }
   
   // Phase 3: Déterminer les directions pour équilibrage
   // Stratégie: Corrélations positives fortes → SELL, négatives fortes → BUY
   for(int i = 0; i < total_positions; i++)
     {
      if(positions[i].target_volume > 0)
        {
         if(positions[i].correlation > 0.0)
           {
            positions[i].direction = ORDER_TYPE_SELL;
            sell_count++;
           }
         else
           {
            positions[i].direction = ORDER_TYPE_BUY;
            buy_count++;
           }
        }
     }
   
   // Phase 4: Forcer équilibrage BUY/SELL si demandé
   if(FORCE_BALANCE && MathAbs(buy_count - sell_count) > 2)
     {
      Print("⚖️ Rééquilibrage forcé BUY/SELL...");
      // Inverser quelques positions pour équilibrer
      int diff = buy_count - sell_count;
      int to_flip = MathAbs(diff) / 2;
      
      if(diff > 0) // Trop de BUY
        {
         for(int i = 0; i < total_positions && to_flip > 0; i++)
           {
            if(positions[i].direction == ORDER_TYPE_BUY && positions[i].target_volume > 0)
              {
               positions[i].direction = ORDER_TYPE_SELL;
               to_flip--;
              }
           }
        }
      else // Trop de SELL
        {
         for(int i = 0; i < total_positions && to_flip > 0; i++)
           {
            if(positions[i].direction == ORDER_TYPE_SELL && positions[i].target_volume > 0)
              {
               positions[i].direction = ORDER_TYPE_BUY;
               to_flip--;
              }
           }
        }
     }
   
   // Phase 5: Créer des paires de couverture si activé
   if(ENABLE_HEDGING)
     {
      Print("🛡️ Création de paires de couverture...");
      for(int i = 0; i < total_positions - 1; i++)
        {
         if(positions[i].target_volume > 0 && !positions[i].is_hedge_pair)
           {
            for(int j = i + 1; j < total_positions; j++)
              {
               if(positions[j].target_volume > 0 && !positions[j].is_hedge_pair)
                 {
                  // Chercher des paires avec corrélations opposées
                  if(positions[i].correlation * positions[j].correlation < -0.5)
                    {
                     positions[i].is_hedge_pair = true;
                     positions[j].is_hedge_pair = true;
                     positions[i].hedge_partner = positions[j].symbol;
                     positions[j].hedge_partner = positions[i].symbol;
                     PrintFormat("🔗 Paire de couverture : %s ↔ %s", 
                                positions[i].symbol, positions[j].symbol);
                     break;
                    }
                 }
              }
           }
        }
     }
   
   // Affichage du résumé d'optimisation
   int active_positions = 0;
   double final_exposure = 0.0;
   int final_buy = 0, final_sell = 0;
   
   for(int i = 0; i < total_positions; i++)
     {
      if(positions[i].target_volume > 0)
        {
         active_positions++;
         final_exposure += positions[i].exposure;
         if(positions[i].direction == ORDER_TYPE_BUY) final_buy++;
         else final_sell++;
        }
     }
   
   PrintFormat("📊 Optimisation terminée:");
   PrintFormat("  • Positions actives: %d", active_positions);
   PrintFormat("  • Exposition totale: %.2f", final_exposure);
   PrintFormat("  • BUY: %d | SELL: %d", final_buy, final_sell);
   if(final_buy + final_sell > 0)
      PrintFormat("  • Ratio équilibrage: %.2f", (double)final_buy / (final_buy + final_sell));
  }

//+------------------------------------------------------------------+
//| Vérification des positions existantes                            |
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
//| Exécution des ordres optimisés                                   |
//+------------------------------------------------------------------+
void ExecuteBalancedOrders(BalancedPosition &positions[])
  {
   Print("🚀 Exécution des ordres équilibrés...");
   
   int executed = 0, skipped = 0, failed = 0;
   
   for(int i = 0; i < ArraySize(positions); i++)
     {
      if(positions[i].target_volume <= 0) continue;
      
      string symbol = positions[i].symbol;
      
      // Vérifier disponibilité MT5
      if(!SymbolSelect(symbol, true))
        {
         PrintFormat("❌ Symbole indisponible: %s", symbol);
         skipped++;
         continue;
        }
      
      // Vérifier position existante
      if(HasOpenPosition(symbol))
        {
         PrintFormat("⏳ Position existante: %s", symbol);
         skipped++;
         continue;
        }
      
      // Préparer l'ordre
      double volume = positions[i].target_volume;
      ENUM_ORDER_TYPE order_type = positions[i].direction;
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double price, sl_price;
      
      if(order_type == ORDER_TYPE_BUY)
        {
         price = SymbolInfoDouble(symbol, SYMBOL_ASK);
         sl_price = price - SL_POINTS * point;
        }
      else
        {
         price = SymbolInfoDouble(symbol, SYMBOL_BID);
         sl_price = price + SL_POINTS * point;
        }
      
      sl_price = NormalizeDouble(sl_price, digits);
      
      // Exécuter l'ordre
      bool success = false;
      if(order_type == ORDER_TYPE_BUY)
         success = trade.Buy(NormalizeDouble(volume,2), symbol, price, sl_price, 0.0);
      else
         success = trade.Sell(NormalizeDouble(volume,2), symbol, price, sl_price, 0.0);
      
      if(success)
        {
         string hedge_info = positions[i].is_hedge_pair ? 
                            StringFormat(" [Hedge: %s]", positions[i].hedge_partner) : "";
         
         PrintFormat("✅ %s %s: Vol=%.3f, Corr=%.3f, Exp=%.0f%s",
                     (order_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     symbol, NormalizeDouble(volume,2), positions[i].correlation, 
                     positions[i].exposure, hedge_info);
         executed++;
         Sleep(PAUSE_MS);
        }
      else
        {
         PrintFormat("❌ Échec %s %s: %s",
                     (order_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     symbol, trade.ResultComment());
         failed++;
        }
     }
   
   PrintFormat("📈 Résultats d'exécution:");
   PrintFormat("  • Exécutées: %d", executed);
   PrintFormat("  • Ignorées: %d", skipped);
   PrintFormat("  • Échouées: %d", failed);
  }

//+------------------------------------------------------------------+
//| Programme principal                                               |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("🎯 Début du script BalancedPortfolioHedge.mq5");
   
   // 1) Récupération des données JSON
   string api_url = "https://macrofinder.flolep.fr/api/assets/correlations";
   string headers = "";
   char request_data[], result_bytes[];
   string response_headers;
   string json_content;
   bool use_cached = false;
   
   Print("🔄 Récupération des corrélations...");
   
   int res = WebRequest("GET", api_url, headers, 5000, request_data, result_bytes, response_headers);
   
   if(res == -1)
     {
      PrintFormat("❌ API inaccessible (code: %d)", GetLastError());
      string last_file = GetLatestJsonFile();
      if(StringLen(last_file) == 0)
        {
         Print("❌ Aucun fichier de secours disponible");
         return;
        }
      json_content = LoadJsonFromFile(last_file);
      use_cached = true;
      PrintFormat("📁 Utilisation du fichier de secours: %s", last_file);
     }
   else
     {
      json_content = CharArrayToString(result_bytes);
      if(StringLen(json_content) > 0)
        {
         SaveJsonToFile(json_content);
         PrintFormat("✅ Données récupérées de l'API (%d caractères)", StringLen(json_content));
        }
     }
   
   if(StringLen(json_content) == 0)
     {
      Print("❌ Aucune donnée JSON disponible");
      return;
     }
   
   // 2) Analyse et optimisation avec parsing JSON réel
   BalancedPosition positions[];
   if(!ParseCorrelationsFromAPI(json_content, positions))
     {
      Print("❌ Échec du parsing JSON");
      return;
     }
   
   OptimizePortfolioBalance(positions);
   
   // 3) Exécution des ordres
   ExecuteBalancedOrders(positions);
   
   Print("🏁 Script terminé avec succès");
  }