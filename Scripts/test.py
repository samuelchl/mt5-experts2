#property script_show_inputs
import MetaTrader5 as mt5

from datetime import datetime

def OnStart():
    if not mt5.initialize():
        print("❌ Échec init :", mt5.last_error())
        return
    print("✅ Toto")
    ticks = mt5.copy_ticks_from("EURUSD", datetime.now(), 10, mt5.COPY_TICKS_ALL)
    print("Derniers ticks :", ticks)
    mt5.shutdown()

#--- GARANTIE D’APPEL -------------------------------------------------------
# si le wrapper ne déclenche pas OnStart() automatiquement,
# on l’appelle manuellement quand on lance le script Python
if __name__ == "__main__":
    OnStart()
