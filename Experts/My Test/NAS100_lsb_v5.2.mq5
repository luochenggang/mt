//+------------------------------------------------------------------+
//|                                 NAS100_DayTrend_AutoTime_v5.2.mq5 |
//|                                  Copyright 2026, Gemini Thought |
//|                Strategy: Auto-Session + Loss Recovery + Manual Exit |
//+------------------------------------------------------------------+
#property copyright "Gemini"
#property version   "5.02" // Updated version with Info Panel
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "1. Automated Time Control"
input int       InpPostOpenMins = 5;          // Minutes to wait after Open
input int       InpPreCloseMins = 10;         // Minutes to close before End

input group "2. Grid & Risk Control"
input double    InpLotSize       = 0.1;       // Base Lot Size
input int       InpGridStep      = 1500;      // Grid Step (Points)
input int       InpMaxDepth      = 6;         // Max Depth (Layers)
input int       InpMagic         = 888555;    // Magic Number

input group "3. Signal Buffers"
input int       InpPendingBuffer    = 200;    // Buffer for Pending Orders (Points)
input int       InpSLTriggerBuffer  = 50;     // Buffer for SL Modification (Points)

input group "4. Loss Recovery (Enhanced)"
input int       InpMaxRecoveryMult = 5;       // Max Initial Multiplier Limit
input bool      InpUseRecovery     = true;    // Enable Loss Recovery Mechanism

input group "5. Trend Filter"
input int       InpTrendEMA        = 0;       // Trend EMA Period (0 = Disabled)

input group "6. Manual Intervention (New)"
input double    InpManualExitPrice = 24818;      // Manual Exit Price (0=Disabled, close below this)

//--- Global Variables
CTrade          trade;
bool            g_IsSystemActive = false;
bool            g_IsHardStop     = false;
double          g_AnchorPrice    = 0.0;
double          g_BaseOpenPrice  = 0.0;
int             g_CurrentDay     = -1;
string          g_GV_Name        = "";      
int             g_hEMA           = INVALID_HANDLE; // Moving Average Handle

string GV_Base() { return "NAS_" + IntegerToString(InpMagic) + "_"; }

// Helper to save/load state
void SyncStateToDisk(bool save) {
    string gv_anchor = GV_Base() + "Anchor";
    string gv_base   = GV_Base() + "BasePrice";
    string gv_active = GV_Base() + "Active";

    if(save) {
        GlobalVariableSet(gv_anchor, g_AnchorPrice);
        GlobalVariableSet(gv_base, g_BaseOpenPrice);
        GlobalVariableSet(gv_active, (double)g_IsSystemActive);
    } else {
        if(GlobalVariableCheck(gv_anchor)) g_AnchorPrice = GlobalVariableGet(gv_anchor);
        if(GlobalVariableCheck(gv_base))   g_BaseOpenPrice = GlobalVariableGet(gv_base);
        if(GlobalVariableCheck(gv_active)) g_IsSystemActive = (bool)GlobalVariableGet(gv_active);
    }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_IOC); 
   
   g_GV_Name = "NAS_Rec_" + IntegerToString(InpMagic);
    
   // Initialize MA Indicator
   if(InpTrendEMA > 0)
      g_hEMA = iMA(_Symbol, _Period, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   
   Print(">>> NAS100 Trend+Recovery+Manual (v5.02) Loaded. Recovery Var Name: ", g_GV_Name);
   
   if(GlobalVariableCheck(g_GV_Name)) {
      Print(">>> Current Pending Recovery Multiplier: ", GlobalVariableGet(g_GV_Name));
   }
   
   // Load state from disk to survive timeframe switch
   SyncStateToDisk(false);
    
   // Check if positions actually exist to verify g_IsSystemActive
   if(PositionsTotal() > 0) {
       // Validation logic to ensure the EA knows it's still in a trade
       g_IsSystemActive = true; 
   }
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "GridLine_");
   ObjectsDeleteAll(0, "AnchorLine");
   ObjectsDeleteAll(0, "StopLine");
   ObjectsDeleteAll(0, "ManualExitLine"); // Delete Manual Line
   IndicatorRelease(g_hEMA);
   Comment(""); // Clear chart comment
}

//+------------------------------------------------------------------+
//| Main Loop                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime dt_now; 
   TimeToStruct(now, dt_now);

   // --- UPDATE UI PANEL ---
   UpdateInfoPanel(now);
   // -----------------------

   if(g_CurrentDay != dt_now.day) {
      ResetDailyState();
      g_CurrentDay = dt_now.day;
   }

   datetime session_start, session_end;
   if(!GetTodaySessionTimes(session_start, session_end)) return;

   datetime tradeStartTime = session_start + InpPostOpenMins * 60;
   datetime tradeEndTime   = session_end   - InpPreCloseMins * 60;

   // A. Close Session (Time up)
   if(now >= tradeEndTime) {
      if(g_IsSystemActive || PositionsTotal() > 0 || OrdersTotal() > 0) {
         if(g_IsSystemActive) {
             if(InpUseRecovery) {
                 SaveRecoveryState(); 
             }
             
             g_IsSystemActive = false; 
             SyncStateToDisk(true);
             
             Print(">>> [System] Session Time Up. Data Saved & State Synced. Closing all positions...");
         }
         
         CloseAllPositionsAndOrders();
      }
      return;
   }

   // B. Active Trading Session
   if(now >= tradeStartTime && now < tradeEndTime) {
      if(g_IsHardStop) return; // If Hard Stop triggered today, do not open new trades

      if(!g_IsSystemActive) {
         InitSession();
      }

      if(g_IsSystemActive) {
         RunStrategyLogic();
      }
   }
}

//+------------------------------------------------------------------+
//| UI Info Panel (New Function)                                     |
//+------------------------------------------------------------------+
void UpdateInfoPanel(datetime now) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double autoStopLine = g_AnchorPrice - (InpMaxDepth * InpGridStep * _Point);
    
    // Calculate P/L and Lots
    double totalPL = 0.0;
    double totalVol = 0.0;
    int positionsCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
       if(PositionSelectByTicket(PositionGetTicket(i))) {
          if(PositionGetInteger(POSITION_MAGIC) == InpMagic) {
             totalPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
             totalVol += PositionGetDouble(POSITION_VOLUME);
             positionsCount++;
          }
       }
    }

    // Recovery Info
    string recStatus = "Inactive";
    if(GlobalVariableCheck(g_GV_Name)) {
        recStatus = "Pending (x" + DoubleToString(GlobalVariableGet(g_GV_Name), 0) + ")";
    }

    // Build String
    string text = "---------- NAS100 GRID SYSTEM v5.2 ----------\n";
    text += StringFormat("Server Time  : %s\n", TimeToString(now, TIME_SECONDS));
    text += StringFormat("Trading      : %s\n", (g_IsHardStop ? "HARD STOP (Safety)" : (g_IsSystemActive ? "ACTIVE" : "WAITING")));
    text += "\n";
    text += StringFormat("Current Bid  : %.2f\n", bid);
    text += StringFormat("Anchor Price : %.2f\n", g_AnchorPrice);
    text += StringFormat("Base Open    : %.2f\n", g_BaseOpenPrice);
    text += "\n";
    text += "---------- LOGIC LIMITS ----------\n";
    text += StringFormat("Manual Exit  : %.2f %s\n", InpManualExitPrice, (InpManualExitPrice > 0 ? "" : "(Disabled)"));
    text += StringFormat("Auto Stop    : %.2f (Depth: %d)\n", autoStopLine, InpMaxDepth);
    text += "\n";
    text += "---------- LIVE POSITIONS ----------\n";
    text += StringFormat("Positions    : %d\n", positionsCount);
    text += StringFormat("Total Lots   : %.2f\n", totalVol);
    text += StringFormat("Floating P/L : %.2f\n", totalPL);
    text += StringFormat("Recovery     : %s\n", recStatus);

    Comment(text);
}

//+------------------------------------------------------------------+
//| Daily Session Initialization Logic                               |
//+------------------------------------------------------------------+
void InitSession() {
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // --- Logic: Pre-Open Check ---
   // If Manual Exit Price is set and current price is below it, block trading for today
   if(InpManualExitPrice > 0.0 && currentAsk < InpManualExitPrice) {
      PrintFormat(">>> [Open Block] Warning! Current Price (%.2f) below Manual Exit Price (%.2f).", currentAsk, InpManualExitPrice);
      Print(">>> System deems environment unsafe. Hard Stop triggered. No trading today.");
      
      g_IsHardStop = true; // Mark as stopped for the day
      return;              // Exit immediately
   }
   // ---------------------------

   // --- Trend Logic ---
   if(g_hEMA != INVALID_HANDLE) {
      double ema_buffer[];
      ArraySetAsSeries(ema_buffer, true);
      if(CopyBuffer(g_hEMA, 0, 0, 1, ema_buffer) > 0) {
         double currentEMA = ema_buffer[0];
         
         // If price is below EMA, consider it weak/bearish, do not open Buy Grid
         if(currentAsk < currentEMA) {
            return; 
         }
      }
   }

   CloseAllPositionsAndOrders();
   
   double lotMultiplier = 1.0;
   if(InpUseRecovery && GlobalVariableCheck(g_GV_Name)) {
      lotMultiplier = GlobalVariableGet(g_GV_Name);
      PrintFormat(">>> [Trend Confirmed] Loading recovery history. Initial Multiplier: %.0f", lotMultiplier);
   }
   
   double finalLots = NormalizeDouble(InpLotSize * lotMultiplier, 2);
   
   // Get latest Ask again for precision
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(trade.Buy(finalLots, _Symbol, ask, 0, 0, "Init_Market_Rec")) {
      g_BaseOpenPrice = ask;
      g_AnchorPrice = ask; 
      g_IsSystemActive = true;
      
      if(lotMultiplier > 1.0) GlobalVariableDel(g_GV_Name);
      
      Print(">>> Trend UP & Price above Manual Line. Base Position Opened. Lots:", finalLots, " BasePrice:", g_BaseOpenPrice);
      MaintainGridOrders(ask, g_AnchorPrice - (InpMaxDepth * InpGridStep * _Point));
   }
}

//+------------------------------------------------------------------+
//| Core Strategy Logic (Includes Manual Exit Check)                 |
//+------------------------------------------------------------------+
void RunStrategyLogic() {
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double autoStopLine = g_AnchorPrice - (InpMaxDepth * InpGridStep * _Point);
   
   // --- 1. Manual Exit Check (New) ---
   // If price (>0) is set AND current price is below it
   if(InpManualExitPrice > 0.0 && currentBid < InpManualExitPrice) {
      PrintFormat("!!! [DEBUG] MANUAL EXIT TRIGGERED | Bid: %.2f < ManualLine: %.2f", currentBid, InpManualExitPrice);
      Print("!!! Warning: Price broke [Manual Exit Line] ", InpManualExitPrice, ". Triggering Forced Close.");
      
      // Record loss to ensure logic consistency
      if(InpUseRecovery) SaveRecoveryState();
      
      CloseAllPositionsAndOrders();
      g_IsHardStop = true;       // Stop for the day
      g_IsSystemActive = false;
      return;
   }
   
   // --- 2. Auto Max Depth Stop Check ---
   if(currentBid < autoStopLine) {
      PrintFormat("!!! [DEBUG] AUTO STOP TRIGGERED | Bid: %.2f < AutoStopLine: %.2f | Anchor: %.2f", currentBid, autoStopLine, g_AnchorPrice);
      Print("!!! Warning: Price broke [Max Depth] ", autoStopLine, ". Triggering Forced Close.");
      
      if(InpUseRecovery) SaveRecoveryState();
      
      CloseAllPositionsAndOrders();
      g_IsHardStop = true;
      g_IsSystemActive = false;
      return;
   }
   
   UpdateAnchorAndSL(currentBid);
   MaintainGridOrders(currentAsk, autoStopLine);
   DrawLines(autoStopLine);
}

void SaveRecoveryState() {
   double totalFloatingProfit = 0.0;
   double maxLotFound = 0.0; 
   
   Print("--- [DEBUG] Starting Recovery Calculation ---");
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
            double profit = PositionGetDouble(POSITION_PROFIT);
            double swap = PositionGetDouble(POSITION_SWAP);
            double comm = PositionGetDouble(POSITION_COMMISSION);
            double netP = profit + swap + comm;
            
            PrintFormat("   [DEBUG] Ticket %d | Profit: %.2f | Swap: %.2f | Comm: %.2f | Net: %.2f", 
                        PositionGetInteger(POSITION_TICKET), profit, swap, comm, netP);

            totalFloatingProfit += netP;
            
            double currentPosLot = PositionGetDouble(POSITION_VOLUME);
            if(currentPosLot > maxLotFound) maxLotFound = currentPosLot;
         }
      }
   }
   
   if(totalFloatingProfit < -0.01) {
      double loss = MathAbs(totalFloatingProfit);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double oneGridValue = InpLotSize * InpGridStep * tickValue;
      
      if(oneGridValue <= 0) oneGridValue = 1.0;
      
      double lossBasedMult = MathCeil(loss / oneGridValue);
      double lotBasedMult = 1.0;
      if(InpLotSize > 0) lotBasedMult = MathCeil(maxLotFound / InpLotSize);
      
      double finalMult = MathMax(lossBasedMult, lotBasedMult);
      
      if(finalMult > InpMaxRecoveryMult) finalMult = InpMaxRecoveryMult;
      if(finalMult < 1.0) finalMult = 1.0;
      
      GlobalVariableSet(g_GV_Name, finalMult);
      PrintFormat(">>> [Loss Record] P/L:%.2f, MaxLot:%.2f. CalcMult:%.0f, LotMult:%.0f. Final:%.0f", 
                  totalFloatingProfit, maxLotFound, lossBasedMult, lotBasedMult, finalMult);
   } else {
      if(GlobalVariableCheck(g_GV_Name)) GlobalVariableDel(g_GV_Name);
      Print(">>> [Loss Record] No current loss (Profit >= 0). Multiplier reset to 1.");
   }
}

bool GetTodaySessionTimes(datetime &start_out, datetime &end_out) {
   datetime now = TimeCurrent();
   MqlDateTime dt_now; TimeToStruct(now, dt_now);
   datetime s_start, s_end;
   if(SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt_now.day_of_week, 0, s_start, s_end)) {
      MqlDateTime dt_end, dt_start;
      TimeToStruct(s_end, dt_end); TimeToStruct(s_start, dt_start);
      dt_end.year = dt_now.year; dt_end.mon = dt_now.mon; dt_end.day = dt_now.day;
      dt_start.year = dt_now.year; dt_start.mon = dt_now.mon; dt_start.day = dt_now.day;
      start_out = StructToTime(dt_start);
      end_out   = StructToTime(dt_end);
      if(end_out <= start_out) end_out += 24 * 3600;
      return true;
   }
   return false;
}

void ResetDailyState() {
   g_IsSystemActive = false;
   g_IsHardStop = false;
   g_AnchorPrice = 0;
   g_BaseOpenPrice = 0;
}


void UpdateAnchorAndSL(double currentBid) {
   // 1. Calculate the global standard grid line (Reference base for all positions)
   int rawGridIndex = (int)MathFloor((currentBid - g_BaseOpenPrice) / (InpGridStep * _Point));
   double rawGridLine = g_BaseOpenPrice + (rawGridIndex * InpGridStep * _Point);
   
   // Update the highest Anchor price (For drawing or logic)
   if(rawGridLine > g_AnchorPrice) {
      PrintFormat("--- [DEBUG] Anchor Moved UP! Old: %.2f | New: %.2f | Bid: %.2f", g_AnchorPrice, rawGridLine, currentBid);
      g_AnchorPrice = rawGridLine; 
      SyncStateToDisk(true); // Persist immediately
   }

   // 2. Calculate the Global "Tight" Stop Loss Level (Standard Logic)
   // This represents the "floor" of the current grid level.
   double effectivePrice = currentBid - (InpSLTriggerBuffer * _Point); 
   int safeGridIndex = (int)MathFloor((effectivePrice - g_BaseOpenPrice) / (InpGridStep * _Point)); 
   double globalStandardSL = g_BaseOpenPrice + (safeGridIndex * InpGridStep * _Point);
   
   // --- Iterate through all positions for Differentiated Management ---
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
            
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            
            // --- NEW: Calculate how many grids of profit this specific position has ---
            double profitPoints = currentBid - openPrice;
            // Floor calculation to get integer grid count (e.g., 1.8 grids -> 1, 2.5 grids -> 2)
            int profitGridCount = (int)MathFloor(profitPoints / (InpGridStep * _Point));
            
            // --- CORE: Tiered / Differentiated Stop Loss Logic ---
            double targetSL = 0.0;
            double safetyMargin = 0.0;

            
            // [Normal/Low Profit Strategy]: Standard Tight Trailing
            // Strategy: Keep SL close to the current grid floor to secure break-even/small profit.
            targetSL = globalStandardSL;
            safetyMargin = InpGridStep * _Point * 0.8; // Keep original 0.8 margin

            // --- Execution Checks ---
            // 1. Gatekeeper: New SL must be > Open Price + Safety Margin
            // (This prevents slippage from closing orders too early)
            if(targetSL > openPrice + safetyMargin) {
               
               // 2. Direction Check: SL can only move UP (never regress)
               if(targetSL > currentSL + _Point || currentSL == 0) {
                  
                  double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                  
                  // 3. Minimum Distance Check (Server Requirement)
                  if(currentBid - targetSL > minStopLevel) {
                     PrintFormat(">>> [Tiered SL] Ticket:%d | ProfitGrids:%d | Mode:%s | OldSL:%.2f -> NewSL:%.2f", 
                                 ticket, profitGridCount, (profitGridCount>=2 ? "Loose" : "Tight"), currentSL, targetSL);
                                 
                     trade.PositionModify(ticket, targetSL, 0);
                  }
               }
            }
         }
      }
   }
}

void MaintainGridOrders(double currentAsk, double hardStopPrice) {
   int startGridIndex = (int)MathCeil((hardStopPrice - g_BaseOpenPrice) / (InpGridStep * _Point));
   int maxGridIndex = (int)MathFloor((g_AnchorPrice - g_BaseOpenPrice) / (InpGridStep * _Point)) + InpMaxDepth;

   for(int i = startGridIndex; i <= maxGridIndex; i++) {
      double gridLevel = NormalizeDouble(g_BaseOpenPrice + (i * InpGridStep * _Point), _Digits);
      if(gridLevel <= hardStopPrice + _Point || gridLevel <= 0) continue;

      bool hasPosition = false;
      for(int p = PositionsTotal() - 1; p >= 0; p--) {
         if(PositionSelectByTicket(PositionGetTicket(p)) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
            if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - gridLevel) < InpGridStep * _Point * 0.2) { hasPosition = true; break; }
         }
      }
      if(hasPosition) continue;

      bool hasPending = false;
      for(int o = OrdersTotal() - 1; o >= 0; o--) {
         if(OrderSelect(OrderGetTicket(o)) && OrderGetInteger(ORDER_MAGIC) == InpMagic) {
            if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - gridLevel) < InpGridStep * _Point * 0.2) { hasPending = true; break; }
         }
      }
      if(hasPending) continue; 

      double triggerPrice = gridLevel - (InpPendingBuffer * _Point);
      if(currentAsk < triggerPrice) {
         PrintFormat(">>> [DEBUG] Placing Grid Order. Level: %.2f | Trigger: %.2f | Ask: %.2f", gridLevel, triggerPrice, currentAsk);
         trade.BuyStop(InpLotSize, gridLevel, _Symbol, 0, 0, ORDER_TIME_DAY, 0, "Grid_Stop");
      }
   }
}

void CloseAllPositionsAndOrders() {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) && OrderGetInteger(ORDER_MAGIC) == InpMagic) trade.OrderDelete(t);
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic) trade.PositionClose(t);
   }
}

void DrawLines(double stopPrice) {
   // Draw Auto Anchor Line
   string anchorName = "AnchorLine";
   if(ObjectFind(0, anchorName) < 0) ObjectCreate(0, anchorName, OBJ_HLINE, 0, 0, g_AnchorPrice);
   ObjectSetDouble(0, anchorName, OBJPROP_PRICE, g_AnchorPrice);
   ObjectSetInteger(0, anchorName, OBJPROP_COLOR, clrBlue);
   
   // Draw Auto Stop Line (Max Depth)
   string stopName = "StopLine";
   if(ObjectFind(0, stopName) < 0) ObjectCreate(0, stopName, OBJ_HLINE, 0, 0, stopPrice);
   ObjectSetDouble(0, stopName, OBJPROP_PRICE, stopPrice);
   ObjectSetInteger(0, stopName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, stopName, OBJPROP_STYLE, STYLE_DOT);
   
   // --- Draw Manual Exit Line (New) ---
   string manualName = "ManualExitLine";
   if(InpManualExitPrice > 0.0) {
      if(ObjectFind(0, manualName) < 0) ObjectCreate(0, manualName, OBJ_HLINE, 0, 0, InpManualExitPrice);
      ObjectSetDouble(0, manualName, OBJPROP_PRICE, InpManualExitPrice);
      ObjectSetInteger(0, manualName, OBJPROP_COLOR, clrYellow); // Set to distinct Yellow
      ObjectSetInteger(0, manualName, OBJPROP_WIDTH, 2);         // Thicker line
   } else {
      // If parameter changed back to 0, delete the line
      if(ObjectFind(0, manualName) >= 0) ObjectDelete(0, manualName);
   }
}