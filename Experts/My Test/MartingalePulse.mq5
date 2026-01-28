//+------------------------------------------------------------------+
//|                                              MP by SPLpulse.mq5 |
//|                          Copyright 2025, SPLpulse |
//|                                  https://www.splpulse.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, SPLpulse"
#property link      "https://www.splpulse.com"
#property version   "1.10"
#property description "A versatile Expert Advisor combining multiple trading strategies with advanced risk management."
#property description "Features include Martingale, dynamic lot sizing, trailing profit, trading sessions, and daily profit/drawdown limits."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- MP by SPLpulse

//--- CTrade and CPositionInfo instances
CTrade trade;
CPositionInfo position;

//--- Enumeration for Entry Strategy
enum ENUM_ENTRY_STRATEGY
{
    MARKET_ORDER, // Entry via Market Order
    STOP_ORDER,   // Entry via Stop Order
    LIMIT_ORDER   // Entry via Limit Order
};

//--- Enumeration for Price Action Strategy
enum ENUM_PRICE_ACTION_TYPE
{
    HFT_TICK_MOMENTUM,     // HFT Momentum
    CANDLESTICK_ENGULFING, // Strategy based on engulfing candlestick pattern
    RSI_REVERSAL,          // RSI crosses back from overbought/oversold
    EMA_CROSSOVER          // Candle closes across the EMA
};

//--- Enumeration for Martingale Strategy
enum ENUM_MARTINGALE_TYPE
{
    CLASSIC_MULTIPLIER,   // lot = previous_lot * multiplier
    MULTIPLIER_WITH_SUM,  // lot = (previous_lot * multiplier) + initial_lot
    SUM_WITH_INITIAL      // lot = previous_lot + initial_lot
};

//--- Enumeration for Drawdown Type
enum ENUM_DRAWDOWN_TYPE
{
    FIXED_AMOUNT, // Drawdown as a fixed of daily starting balance
    PERCENTAGE    // Drawdown as a percentage of daily starting balance
};

//--- Enumeration for Lot Sizing Mode
enum ENUM_LOT_SIZE_MODE
{
    FIXED_LOT,          // Use a fixed initial lot size
    PERCENT_OF_BALANCE // Calculate initial lot based on risk percentage of balance
};

//--- Enumeration for Drawdown Time Calculation
enum ENUM_DRAWDOWN_TIME_MODE
{
    SERVER_TIME, // Based on Broker's Server Time (resets at 00:00)
    CUSTOM_TIME  // Based on a custom UTC time range
};

//--- Enumeration for Trailing Stop Type
enum ENUM_TRAILING_STOP_TYPE
{
    TRAILING_IN_MONEY, // Trailing stop in deposit currency
    TRAILING_IN_POINTS // Trailing stop in points
};


//--- EA Inputs
sinput group "1. Core Trading Strategy"
sinput ENUM_PRICE_ACTION_TYPE InpPriceActionType = EMA_CROSSOVER; // Price Action Strategy
sinput ENUM_ENTRY_STRATEGY InpEntryStrategy = MARKET_ORDER;              // Entry Strategy
sinput int   InpPendingOrderDistancePoints = 500; // Distance for pending orders from current price
sinput int   InpPendingUpdateInterval = 100; // Seconds to wait before updating pending orders
sinput int    InpTradeCooldownSeconds = 3; // Cooldown in seconds between trades (0 = disabled)

sinput group "2. Indicator Settings"
sinput ENUM_TIMEFRAMES InpChartTimeframe = PERIOD_CURRENT; // Timeframe for Indicators
sinput int   InpTickMomentumCount = 6;     // Ticks for HFT Momentum
sinput int   InpEmaPeriod = 15;        // EMA Period for Crossover
sinput int   InpRsiPeriod = 14;        // RSI Period
sinput int   InpRsiOverbought = 70;      // RSI Overbought Level
sinput int   InpRsiOversold = 30;        // RSI Oversold Level

sinput group "3. Lot Sizing & Martingale"
sinput ENUM_LOT_SIZE_MODE InpLotSizeMode = PERCENT_OF_BALANCE; // Lot Sizing Mode
sinput double InpFixedInitialLot = 0.01;     // Initial Lot Size (for Fixed Lot mode)
sinput double InpRiskPercentage = 1.0;       // Risk Percentage of Balance (for Percent mode)
sinput ENUM_MARTINGALE_TYPE InpMartingaleType = CLASSIC_MULTIPLIER; // Martingale Type
sinput double InpMartingaleMultiplier = 2.0; // Martingale Multiplier on Loss
sinput int    InpMaxOrdersPerRound = 5;      // Maximum orders per Martingale round
sinput double InpMaxLotSize = 5.0;       // Maximum Lot Size

sinput group "4. Trade Management"
sinput int    InpStopLossPoints = 1000;    // Stop Loss in Points
sinput double InpRiskRewardRatio = 2;    // Risk:Reward Ratio (e.g., 1.5 means TP is 1.5 * SL)
sinput bool   InpEnableTrailingStop = false;   // Enable Trailing Stop
sinput ENUM_TRAILING_STOP_TYPE InpTrailingStopType = TRAILING_IN_POINTS; // Trailing Stop Type
sinput int    InpTrailingStartPoints = 200;    // Start trailing when profit is >= this amount in Points
sinput int    InpTrailingStopPoints = 100;     // Trail distance from current price in Points
sinput double InpTrailingStartMoney = 50;      // Start trailing when profit is >= this amount in Money
sinput double InpTrailingStopMoney = 10;       // Trail distance from current price in Money

sinput group "5. Time & Session Management"
sinput bool   InpEnableTradingSessions = true;     // Enable Trading Sessions (false = trade 24/7)
sinput bool   InpCloseAtSessionEnd = true;         // Close all trades at the end of a session
sinput string InpMondayTimes = "01:00-23:00"; // Monday Trading Times
sinput string InpTuesdayTimes = "01:00-23:00";     // Tuesday Trading Times
sinput string InpWednesdayTimes = "01:00-23:00";   // Wednesday Trading Times
sinput string InpThursdayTimes = "01:00-23:00";    // Thursday Trading Times
sinput string InpFridayTimes = "01:00-23:00";      // Friday Trading Times
sinput string InpSaturdayTimes = "00:00-00:00";    // Saturday Trading Times
sinput string InpSundayTimes = "00:00-00:00";      // Sunday Trading Times (HH:MM-HH:MM;...)

sinput group "6. Daily Risk Management"
sinput bool   InpEnableDailyProfitLimit = true;      // Enable Daily Profit Limit
sinput double InpDailyProfitLimitAmount = 1000.0;    // Daily Profit Limit Amount (in deposit currency)
sinput bool   InpEnableDrawdown = true;            // Enable Drawdown Protection
sinput ENUM_DRAWDOWN_TYPE InpDrawdownType = PERCENTAGE; // Drawdown Calculation Type
sinput double InpDrawdownFixedAmount = 300.0;      // Max Drawdown (Fixed Amount)
sinput double InpDrawdownPercentage = 5.0;         // Max Drawdown (Percentage)
sinput ENUM_DRAWDOWN_TIME_MODE InpDrawdownTimeMode = SERVER_TIME; // Drawdown Calculation Time
sinput string InpDrawdownStartTimeUTC = "00:01";         // Custom Start Time (UTC)
sinput string InpDrawdownEndTimeUTC = "23:59";         // Custom End Time (UTC)

sinput group "7. EA Identification"
sinput ulong  InpMagicNumber = 105091;     // Magic Number for this EA

//--- Global variables
double   g_current_lot_size;       // To hold the current lot size, considering Martingale
int      g_order_count_in_round = 0; // Counter for trades in the current round
datetime g_last_pending_update_time = 0; // Timer for updating pending orders
bool     g_is_currently_in_session = false; // To track session state
bool     g_is_closing_for_reversal = false; // State flag for handling reversals
datetime g_last_trade_close_time = 0;     // Timestamp of the last trade closure for cooldown

//--- Global variables for Risk Management
double   g_initial_balance_for_day = 0;
int      g_last_reset_day_of_year = 0;     // For SERVER_TIME mode
int      g_last_reset_day_of_year_utc = 0; // For CUSTOM_TIME mode
bool     g_risk_limit_reached_today = false;
bool     g_stop_message_printed = false; // To prevent log flooding when trading is suspended

//--- Indicator handles
int rsi_handle = INVALID_HANDLE;
int ema_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Forward declarations                                           |
//+------------------------------------------------------------------+
bool IsWithinTradingSession();
int CloseAllOpenPositions();
int CancelPendingOrders();
void CheckRiskManagement();
double NormalizeLotSize(double lot);
double CalculateLotSizeBasedOnRisk();
int TimeToMinutes(string time_str);
void HandleMartingale(double profit, double closed_volume);
void HandleTrailingStop();
void SetInitialSLTP(ulong position_ticket);
bool HasSufficientMargin(double lots);
int GetTradeSignal();
void ExecuteTrade(int signal);
double CalculateMaxAffordableLot();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize trade object
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10); // Set allowable slippage in points
    trade.SetTypeFilling(ORDER_FILLING_FOK); // Set order filling type
    trade.SetAsyncMode(false); // Force synchronous execution to prevent race conditions

    //--- Initialize lot size
    if(InpLotSizeMode == FIXED_LOT)
    {
        g_current_lot_size = InpFixedInitialLot;
    }
    else // PERCENT_OF_BALANCE
    {
        g_current_lot_size = CalculateLotSizeBasedOnRisk();
    }
    
    g_current_lot_size = NormalizeLotSize(g_current_lot_size);
    
    //--- Check initial lot size
    if(g_current_lot_size < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
    {
        g_current_lot_size = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        Print("Initial lot size was too small. Adjusted to minimum allowed: ", g_current_lot_size);
    }
    
    //--- Use the selected timeframe, or the current chart's if PERIOD_CURRENT is selected
    ENUM_TIMEFRAMES timeframe = (InpChartTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpChartTimeframe;

    //--- Initialize Indicator Handles
    rsi_handle = iRSI(_Symbol, timeframe, InpRsiPeriod, PRICE_CLOSE);
    if(rsi_handle == INVALID_HANDLE)
    {
        Print("Error creating RSI indicator handle - ", GetLastError());
        return(INIT_FAILED);
    }
    
    ema_handle = iMA(_Symbol, timeframe, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(ema_handle == INVALID_HANDLE)
    {
        Print("Error creating EMA indicator handle - ", GetLastError());
        return(INIT_FAILED);
    }

    //--- Set initial session state
    g_is_currently_in_session = IsWithinTradingSession();
    
    //--- Initialize Risk Management variables
    MqlDateTime dt_server;
    TimeCurrent(dt_server);
    g_last_reset_day_of_year = dt_server.day_of_year;
    
    MqlDateTime dt_utc;
    datetime now_utc = TimeGMT();
    TimeToStruct(now_utc, dt_utc);
    g_last_reset_day_of_year_utc = dt_utc.day_of_year;

    g_initial_balance_for_day = AccountInfoDouble(ACCOUNT_BALANCE);
    g_risk_limit_reached_today = false;

    Print("EA Initialized. Lot Mode: ", EnumToString(InpLotSizeMode), ", Initial Lot: ", g_current_lot_size);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    if(rsi_handle != INVALID_HANDLE)
        IndicatorRelease(rsi_handle);
    if(ema_handle != INVALID_HANDLE)
        IndicatorRelease(ema_handle);
        
    Print("EA Deinitialized. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check risk management limits first
    CheckRiskManagement();
    
    //--- If a risk limit has been reached, halt all further operations for the day
    if(g_risk_limit_reached_today)
    {
        if(!g_stop_message_printed)
        {
            Print("Trading suspended for the day because a daily profit or drawdown limit was reached.");
            g_stop_message_printed = true;
        }
        return;
    }

    //--- If we are waiting for a reversal trade to close, do nothing else.
    if(g_is_closing_for_reversal)
    {
        return;
    }

    //--- Check for trade cooldown period ---
    if(InpTradeCooldownSeconds > 0 && TimeCurrent() - g_last_trade_close_time < InpTradeCooldownSeconds)
    {
        return; // Still in cooldown, do not proceed to check for new trades.
    }

    //--- Session Management Logic
    if(InpEnableTradingSessions)
    {
        g_is_currently_in_session = IsWithinTradingSession();

        if (!g_is_currently_in_session) // If we are OUTSIDE of the allowed session
        {
            if (InpCloseAtSessionEnd)
            {
                int closed_positions = CloseAllOpenPositions();
                int cancelled_orders = CancelPendingOrders();
                if(closed_positions > 0 || cancelled_orders > 0)
                {
                   Print("Closed ", closed_positions, " positions and cancelled ", cancelled_orders, " orders at session end.");
                }
            }
            return; // Halt further trading logic for this tick
        }
    }

    //--- Handle trailing stop for open positions
    if(InpEnableTrailingStop)
    {
        HandleTrailingStop();
    }

    //--- Update pending orders if the strategy is not Market Order and interval has passed
    if(InpEntryStrategy != MARKET_ORDER && TimeCurrent() - g_last_pending_update_time >= InpPendingUpdateInterval)
    {
        UpdatePendingOrders();
        g_last_pending_update_time = TimeCurrent();
    }
    
    //--- Main trading logic: get signal and act on it
    int signal = GetTradeSignal();
    
    if(signal != 0) // If there's a buy or sell signal
    {
        // Check if a position already exists
        if(position.SelectByMagic(_Symbol, InpMagicNumber))
        {
            // Reversal logic: If signal is opposite to current position, close it.
            if((signal == 1 && position.PositionType() == POSITION_TYPE_SELL) ||
               (signal == -1 && position.PositionType() == POSITION_TYPE_BUY))
            {
                trade.PositionClose(position.Ticket());
                g_is_closing_for_reversal = true; // Set flag and wait for confirmation via OnTradeTransaction
                return; // Exit. New trade will be opened on a subsequent tick.
            }
        }
        else // No position exists, so we can consider opening a new one
        {
            if(TotalPositionsAndOrders() == 0) // Ensure no pending orders either
            {
                ExecuteTrade(signal);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check daily profit and drawdown limits                           |
//+------------------------------------------------------------------+
void CheckRiskManagement()
{
    bool should_reset = false;

    // --- 1. Check if it's time to reset the daily stats ---
    if(InpDrawdownTimeMode == SERVER_TIME)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        if(dt.day_of_year != g_last_reset_day_of_year)
        {
            should_reset = true;
            g_last_reset_day_of_year = dt.day_of_year;
        }
    }
    else // CUSTOM_TIME
    {
        MqlDateTime dt_utc;
        datetime now_utc = TimeGMT();
        TimeToStruct(now_utc, dt_utc);
        
        int start_minutes = TimeToMinutes(InpDrawdownStartTimeUTC);
        int current_utc_minutes = dt_utc.hour * 60 + dt_utc.min;

        // Reset if it's a new UTC day and we have passed the designated start time
        if(dt_utc.day_of_year != g_last_reset_day_of_year_utc && current_utc_minutes >= start_minutes)
        {
            should_reset = true;
            g_last_reset_day_of_year_utc = dt_utc.day_of_year;
        }
    }
    
    if(should_reset)
    {
        g_initial_balance_for_day = AccountInfoDouble(ACCOUNT_BALANCE);
        g_risk_limit_reached_today = false;
        g_stop_message_printed = false;
        Print("New trading day detected. Daily profit and drawdown stats reset.");
    }

    // --- 2. If a limit was already hit in the current period, do nothing else ---
    if(g_risk_limit_reached_today)
    {
        return;
    }

    // --- 3. Determine if we are within the active period for checking limits ---
    bool is_active_period = true; // Default for SERVER_TIME mode
    if(InpDrawdownTimeMode == CUSTOM_TIME)
    {
         MqlDateTime dt_utc;
         datetime now_utc = TimeGMT();
         TimeToStruct(now_utc, dt_utc);

         int start_minutes = TimeToMinutes(InpDrawdownStartTimeUTC);
         int end_minutes = TimeToMinutes(InpDrawdownEndTimeUTC);
         int current_utc_minutes = dt_utc.hour * 60 + dt_utc.min;
        
         if(start_minutes != -1 && end_minutes != -1)
         {
            is_active_period = (current_utc_minutes >= start_minutes && current_utc_minutes <= end_minutes);
         }
         else
         {
            is_active_period = false; // Invalid time format
            if(!g_stop_message_printed) Print("Invalid Custom Drawdown Time format. Risk management is disabled.");
         }
    }
    
    if(!is_active_period)
    {
        return; // Not in the time window to check for DD/profit limits
    }

    // --- 4. Perform the actual Profit and Drawdown checks ---
    // Daily Profit Limit Check
    if(InpEnableDailyProfitLimit)
    {
        double current_daily_profit = AccountInfoDouble(ACCOUNT_EQUITY) - g_initial_balance_for_day;
        if(current_daily_profit >= InpDailyProfitLimitAmount)
        {
            Print("Daily profit limit of ", InpDailyProfitLimitAmount, " reached. Closing all positions and stopping for the day.");
            CloseAllOpenPositions();
            CancelPendingOrders();
            g_risk_limit_reached_today = true;
            return;
        }
    }

    // Drawdown Protection Check (based on daily starting balance)
    if(InpEnableDrawdown)
    {
        double current_daily_loss = g_initial_balance_for_day - AccountInfoDouble(ACCOUNT_EQUITY);
        if(current_daily_loss < 0) current_daily_loss = 0;
        
        double drawdown_limit = 0;
        if(InpDrawdownType == FIXED_AMOUNT)
        {
            drawdown_limit = InpDrawdownFixedAmount;
        }
        else // PERCENTAGE
        {
            drawdown_limit = g_initial_balance_for_day * (InpDrawdownPercentage / 100.0);
        }
        
        if(current_daily_loss >= drawdown_limit && drawdown_limit > 0)
        {
            Print("Maximum drawdown limit of ", drawdown_limit, " reached. Closing all positions and stopping for the day.");
            CloseAllOpenPositions();
            CancelPendingOrders();
            g_risk_limit_reached_today = true;
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Generates a trade signal. Returns 1 for buy, -1 for sell, 0 for none.|
//+------------------------------------------------------------------+
int GetTradeSignal()
{
    bool buy_signal = false;
    bool sell_signal = false;
    
    ENUM_TIMEFRAMES timeframe = (InpChartTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpChartTimeframe;

    switch(InpPriceActionType)
    {
        case HFT_TICK_MOMENTUM:
        {
            if(InpTickMomentumCount < 2) break;
            MqlTick ticks_array[];
            ArrayResize(ticks_array, InpTickMomentumCount);
            if(CopyTicks(_Symbol, ticks_array, COPY_TICKS_ALL, 0, InpTickMomentumCount) < InpTickMomentumCount) break;
            bool is_upward = true, is_downward = true;
            for(int i = 1; i < InpTickMomentumCount; i++)
            {
                if(ticks_array[i].bid <= ticks_array[i-1].bid) is_upward = false;
                if(ticks_array[i].ask >= ticks_array[i-1].ask) is_downward = false;
            }
            if(is_upward) buy_signal = true;
            else if(is_downward) sell_signal = true;
            break;
        }
        case CANDLESTICK_ENGULFING:
        {
            static datetime last_bar_time = 0;
            datetime current_bar_time = iTime(_Symbol, timeframe, 0);
            if(last_bar_time == current_bar_time) break;
            last_bar_time = current_bar_time;
            MqlRates rates[2];
            if(CopyRates(_Symbol, timeframe, 1, 2, rates) < 2) break;
            if(rates[0].close < rates[0].open && rates[1].close > rates[1].open && rates[1].close > rates[0].open && rates[1].open < rates[0].close)
                buy_signal = true;
            else if(rates[0].close > rates[0].open && rates[1].close < rates[1].open && rates[1].close < rates[0].open && rates[1].open > rates[0].close)
                sell_signal = true;
            break;
        }
        case RSI_REVERSAL:
        {
            static datetime last_bar_time = 0;
            datetime current_bar_time = iTime(_Symbol, timeframe, 0);
            if(last_bar_time == current_bar_time) break;
            last_bar_time = current_bar_time;
            double rsi_buffer[2];
            if(CopyBuffer(rsi_handle, 0, 1, 2, rsi_buffer) < 2) break;
            if(rsi_buffer[0] < InpRsiOversold && rsi_buffer[1] >= InpRsiOversold) buy_signal = true;
            else if(rsi_buffer[0] > InpRsiOverbought && rsi_buffer[1] <= InpRsiOverbought) sell_signal = true;
            break;
        }
        case EMA_CROSSOVER:
        {
            static datetime last_bar_time = 0;
            datetime current_bar_time = iTime(_Symbol, timeframe, 0);
            if(last_bar_time == current_bar_time) break;
            last_bar_time = current_bar_time;
            MqlRates rates[2];
            double ema_buffer[2];
            if(CopyRates(_Symbol, timeframe, 1, 2, rates) < 2) break;
            if(CopyBuffer(ema_handle, 0, 1, 2, ema_buffer) < 2) break;
            if(rates[0].close < ema_buffer[0] && rates[1].close > ema_buffer[1]) buy_signal = true;
            else if(rates[0].close > ema_buffer[0] && rates[1].close < ema_buffer[1]) sell_signal = true;
            break;
        }
    }

    if(buy_signal) return 1;
    if(sell_signal) return -1;
    return 0;
}

//+------------------------------------------------------------------+
//| Executes a trade based on the provided signal.                   |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
    if(signal == 0) return;

    // --- Margin-Based Lot Capping at the last moment ---
    double max_affordable_lot = CalculateMaxAffordableLot();
    if(g_current_lot_size > max_affordable_lot)
    {
       Print("Martingale lot ", DoubleToString(g_current_lot_size,2), " exceeds available margin. Capping at ", DoubleToString(max_affordable_lot,2));
       g_current_lot_size = max_affordable_lot;
       g_current_lot_size = NormalizeLotSize(g_current_lot_size); // Re-normalize after capping
    }

    if(!HasSufficientMargin(g_current_lot_size))
    {
        Print("Insufficient margin for lot size ", g_current_lot_size, ". Skipping trade.");
        return;
    }

    MqlTick current_tick;
    if(!SymbolInfoTick(_Symbol, current_tick)) return;

    double ask = current_tick.ask;
    double bid = current_tick.bid;
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double stop_loss_offset = InpStopLossPoints * point;
    double take_profit_offset = InpStopLossPoints * InpRiskRewardRatio * point;
    double pending_distance = InpPendingOrderDistancePoints * point;

    if(signal == 1) // Buy Signal
    {
        switch(InpEntryStrategy)
        {
            case MARKET_ORDER:
                trade.Buy(g_current_lot_size, _Symbol, ask, 0, 0, "MP by SPLpulse");
                break;
            case STOP_ORDER:
                trade.BuyStop(g_current_lot_size, ask + pending_distance, _Symbol, (ask + pending_distance) - stop_loss_offset, (ask + pending_distance) + take_profit_offset, 0, 0, "MP by SPLpulse");
                break;
            case LIMIT_ORDER:
                trade.BuyLimit(g_current_lot_size, ask - pending_distance, _Symbol, (ask - pending_distance) - stop_loss_offset, (ask - pending_distance) + take_profit_offset, 0, 0, "MP by SPLpulse");
                break;
        }
    }
    else if(signal == -1) // Sell Signal
    {
        switch(InpEntryStrategy)
        {
            case MARKET_ORDER:
                trade.Sell(g_current_lot_size, _Symbol, bid, 0, 0, "MP by SPLpulse");
                break;
            case STOP_ORDER:
                trade.SellStop(g_current_lot_size, bid - pending_distance, _Symbol, (bid - pending_distance) + stop_loss_offset, (bid - pending_distance) - take_profit_offset, 0, 0, "MP by SPLpulse");
                break;
            case LIMIT_ORDER:
                trade.SellLimit(g_current_lot_size, bid + pending_distance, _Symbol, (bid + pending_distance) + stop_loss_offset, (bid + pending_distance) - take_profit_offset, 0, 0, "MP by SPLpulse");
                break;
        }
    }
}


//+------------------------------------------------------------------+
//| Trade Transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
    //--- Check if the transaction is related to our EA
    ulong magic_number = 0;
    
    //--- Get magic number based on transaction type
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
    {
        if(HistoryDealSelect(trans.deal))
            magic_number = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
    }
    else if(trans.type == TRADE_TRANSACTION_ORDER_ADD && trans.order != 0)
    {
        if(OrderSelect(trans.order))
            magic_number = OrderGetInteger(ORDER_MAGIC);
    }
    
    //--- Only proceed if this transaction belongs to our EA
    if(magic_number == InpMagicNumber)
    {
        //--- Check if a deal was added (a trade was executed)
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
        {
            long deal_entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            
            //--- A new position has been opened
            if(deal_entry == DEAL_ENTRY_IN && InpEntryStrategy == MARKET_ORDER)
            {
                ulong position_ticket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                SetInitialSLTP(position_ticket);
            }
            //--- A position was closed
            else if(deal_entry == DEAL_ENTRY_OUT)
            {
                g_is_closing_for_reversal = false; // Reset the flag now that close is confirmed.
                g_last_trade_close_time = TimeCurrent(); // Set cooldown timer
                double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                double closed_volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                HandleMartingale(profit, closed_volume);
            }
        }
        
        //--- Logic to close opposite pending order if one has been triggered
        if(InpEntryStrategy != MARKET_ORDER && trans.type == TRADE_TRANSACTION_DEAL_ADD)
        {
            if(PositionsTotal() > 0 && position.SelectByMagic(_Symbol, InpMagicNumber))
            {
                CancelPendingOrders();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Sets the initial Stop Loss and Take Profit on a new position     |
//+------------------------------------------------------------------+
void SetInitialSLTP(ulong position_ticket)
{
    if(!position.SelectByTicket(position_ticket)) return;
    
    // Ensure it's our position, just in case
    if(position.Magic() != InpMagicNumber) return;

    // Get fresh market and symbol info right before modification
    MqlTick current_tick;
    if(!SymbolInfoTick(_Symbol, current_tick))
    {
        Print("Could not get current tick to set SL/TP for position #", position_ticket);
        return;
    }
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    
    double open_price = position.PriceOpen();
    double sl_offset = InpStopLossPoints * point;
    double tp_offset = InpStopLossPoints * InpRiskRewardRatio * point;
    
    double new_sl = 0;
    double new_tp = 0;

    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        new_sl = open_price - sl_offset;
        new_tp = open_price + tp_offset;

        // --- Safety Check: Ensure SL is not too close to the current Bid price ---
        double min_valid_sl = current_tick.bid - (stops_level * point);
        if (new_sl > min_valid_sl)
        {
            new_sl = min_valid_sl;
            Print("Adjusting SL for position #", position_ticket, " to meet broker's minimum distance.");
        }
    }
    else // POSITION_TYPE_SELL
    {
        new_sl = open_price + sl_offset;
        new_tp = open_price - tp_offset;
        
        // --- Safety Check: Ensure SL is not too close to the current Ask price ---
        double min_valid_sl = current_tick.ask + (stops_level * point);
        if (new_sl < min_valid_sl)
        {
            new_sl = min_valid_sl;
            Print("Adjusting SL for position #", position_ticket, " to meet broker's minimum distance.");
        }
    }

    if(trade.PositionModify(position_ticket, NormalizeDouble(new_sl, _Digits), NormalizeDouble(new_tp, _Digits)))
    {
        Print("Successfully set initial SL/TP for position #", position_ticket);
    }
    else
    {
        Print("Failed to set initial SL/TP for position #", position_ticket, ". Error: ", GetLastError());
    }
}


//+------------------------------------------------------------------+
//| Handle Martingale Logic                                          |
//+------------------------------------------------------------------+
void HandleMartingale(double profit, double closed_volume)
{
    // First, determine the correct initial lot for this cycle, in case we need it for resets or SUM strategies.
    double initial_lot;
    if (InpLotSizeMode == FIXED_LOT)
    {
        initial_lot = InpFixedInitialLot;
    }
    else
    {
        initial_lot = CalculateLotSizeBasedOnRisk();
    }


    if (profit < 0) // --- LOSS ---
    {
        g_order_count_in_round++;
        Print("Trade #", g_order_count_in_round, " in this round closed with a loss.");

        if (g_order_count_in_round >= InpMaxOrdersPerRound)
        {
            Print("Maximum orders per round (", InpMaxOrdersPerRound, ") reached. Resetting martingale cycle.");
            g_order_count_in_round = 0;
            g_current_lot_size = initial_lot; // Reset to the fresh initial lot
        }
        else
        {
            // Apply Martingale logic to get the next lot size
            switch (InpMartingaleType)
            {
                case CLASSIC_MULTIPLIER:
                    g_current_lot_size = closed_volume * InpMartingaleMultiplier;
                    break;
                case MULTIPLIER_WITH_SUM:
                    g_current_lot_size = (closed_volume * InpMartingaleMultiplier) + initial_lot;
                    break;
                case SUM_WITH_INITIAL:
                    g_current_lot_size = closed_volume + initial_lot;
                    break;
            }
        }
    }
    else // --- PROFIT ---
    {
        Print("Trade closed with a profit. Resetting martingale cycle.");
        g_order_count_in_round = 0;
        g_current_lot_size = initial_lot; // Reset to the fresh initial lot
    }
    
    //--- Normalize the final lot size for the next trade
    g_current_lot_size = NormalizeLotSize(g_current_lot_size);
    Print("New lot size for next trade (before final margin check): ", g_current_lot_size);
}

//+------------------------------------------------------------------+
//| Normalize Lot Size                                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lot)
{
    double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double broker_max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double max_volume = MathMin(InpMaxLotSize, broker_max_volume);

    if(lot < min_volume) lot = min_volume;
    if(lot > max_volume) lot = max_volume;

    if(volume_step > 0)
    {
        lot = MathFloor(lot / volume_step) * volume_step;
    }
    
    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSizeBasedOnRisk()
{
    if(InpStopLossPoints <= 0)
    {
        Print("Cannot calculate risk-based lot size with Stop Loss set to 0. Using minimum lot size.");
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    }

    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = account_balance * (InpRiskPercentage / 100.0);

    // Calculate the value of one point for one lot
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size <= 0)
    {
        Print("Invalid tick size for symbol. Using minimum lot.");
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    }
    
    double point_value_per_lot = tick_value * (_Point / tick_size);
    if(point_value_per_lot <= 0)
    {
        Print("Invalid point value per lot for symbol. Using minimum lot.");
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    }

    // Calculate total loss for one lot if SL is hit
    double loss_per_lot = InpStopLossPoints * point_value_per_lot;

    if(loss_per_lot <= 0)
    {
        Print("Could not determine loss per lot for risk calculation. Using minimum lot size.");
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    }

    // Calculate the required lot size and return it without normalization here
    return risk_amount / loss_per_lot;
}

//+------------------------------------------------------------------+
//| Count total open positions and pending orders by this EA         |
//+------------------------------------------------------------------+
int TotalPositionsAndOrders()
{
    int count = 0;
    //--- Count open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Magic() == InpMagicNumber && position.Symbol() == _Symbol)
            {
                count++;
            }
        }
    }

    //--- Count pending orders
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong order_ticket = OrderGetTicket(i);
        if(OrderSelect(order_ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                            |
//+------------------------------------------------------------------+
int CancelPendingOrders()
{
    int cancelled_count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                if(trade.OrderDelete(ticket))
                {
                    cancelled_count++;
                }
            }
        }
    }
    return cancelled_count;
}

//+------------------------------------------------------------------+
//| Update all pending orders to trail the current price             |
//+------------------------------------------------------------------+
void UpdatePendingOrders()
{
    if(OrdersTotal() == 0) return; // No pending orders to update
    
    Print("Checking to update pending orders...");

    //--- Get current market prices
    MqlTick current_tick;
    if(!SymbolInfoTick(_Symbol, current_tick))
    {
        Print("Error getting current tick data for pending order update");
        return;
    }
    
    double ask = current_tick.ask;
    double bid = current_tick.bid;
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    //--- Calculate new SL, TP, and distance values
    double stop_loss_price_offset = InpStopLossPoints * point;
    double take_profit_price_offset = InpStopLossPoints * InpRiskRewardRatio * point;
    double pending_distance = InpPendingOrderDistancePoints * point;

    //--- Loop through all pending orders
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            //--- Check if the order belongs to this EA
            if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                ENUM_ORDER_TYPE_TIME type_time = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
                datetime expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
                double stoplimit_price = OrderGetDouble(ORDER_PRICE_STOPLIMIT);
                
                double new_price = 0;
                double new_sl = 0;
                double new_tp = 0;

                //--- Determine new prices based on order type
                switch(order_type)
                {
                    case ORDER_TYPE_BUY_STOP:
                        new_price = ask + pending_distance;
                        new_sl = new_price - stop_loss_price_offset;
                        new_tp = new_price + take_profit_price_offset;
                        break;
                    case ORDER_TYPE_SELL_STOP:
                        new_price = bid - pending_distance;
                        new_sl = new_price + stop_loss_price_offset;
                        new_tp = new_price - take_profit_price_offset;
                        break;
                    case ORDER_TYPE_BUY_LIMIT:
                        new_price = ask - pending_distance;
                        new_sl = new_price - stop_loss_price_offset;
                        new_tp = new_price + take_profit_price_offset;
                        break;
                    case ORDER_TYPE_SELL_LIMIT:
                        new_price = bid + pending_distance;
                        new_sl = new_price + stop_loss_price_offset;
                        new_tp = new_price - take_profit_price_offset;
                        break;
                    default:
                        continue; // Not a pending order we manage this way
                }
                
                //--- Normalize prices
                new_price = NormalizeDouble(new_price, _Digits);
                new_sl = NormalizeDouble(new_sl, _Digits);
                new_tp = NormalizeDouble(new_tp, _Digits);

                //--- Modify the order
                if(trade.OrderModify(ticket, new_price, new_sl, new_tp, type_time, expiration, stoplimit_price))
                {
                    Print("Successfully updated pending order #", ticket, " to new price ", new_price);
                }
                else
                {
                    Print("Error updating pending order #", ticket, ". Error code: ", GetLastError());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Trailing Stop Loss                                        |
//+------------------------------------------------------------------+
void HandleTrailingStop()
{
    //--- Check if there are any positions to trail
    if(PositionsTotal() <= 0) return;

    //--- Get tick and point info once
    MqlTick current_tick;
    if(!SymbolInfoTick(_Symbol, current_tick)) return;
    
    long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    //--- Loop through all open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            //--- Check if the position belongs to this EA and symbol
            if(position.Magic() == InpMagicNumber && position.Symbol() == _Symbol)
            {
                //--- Use selected trailing stop type
                switch(InpTrailingStopType)
                {
                    case TRAILING_IN_POINTS:
                    {
                        double new_sl_price = 0;
                        if(position.PositionType() == POSITION_TYPE_BUY)
                        {
                            double profit_in_points = (current_tick.bid - position.PriceOpen()) / _Point;
                            if (profit_in_points >= InpTrailingStartPoints)
                            {
                                new_sl_price = current_tick.bid - (InpTrailingStopPoints * _Point);
                                if(new_sl_price > (position.StopLoss() + _Point) && (current_tick.bid - new_sl_price) >= (stops_level * _Point))
                                {
                                    if(!trade.PositionModify(position.Ticket(), NormalizeDouble(new_sl_price, _Digits), position.TakeProfit()))
                                        Print("Error modifying BUY position #", position.Ticket(), " for trailing stop (Points). Error: ", GetLastError());
                                    else
                                        Print("Trailing stop for BUY #", position.Ticket(), " updated to ", NormalizeDouble(new_sl_price, _Digits));
                                }
                            }
                        }
                        else // SELL
                        {
                            double profit_in_points = (position.PriceOpen() - current_tick.ask) / _Point;
                            if (profit_in_points >= InpTrailingStartPoints)
                            {
                                new_sl_price = current_tick.ask + (InpTrailingStopPoints * _Point);
                                if((new_sl_price < (position.StopLoss() - _Point) || position.StopLoss() == 0) && (new_sl_price - current_tick.ask) >= (stops_level * _Point))
                                {
                                    if(!trade.PositionModify(position.Ticket(), NormalizeDouble(new_sl_price, _Digits), position.TakeProfit()))
                                        Print("Error modifying SELL position #", position.Ticket(), " for trailing stop (Points). Error: ", GetLastError());
                                    else
                                        Print("Trailing stop for SELL #", position.Ticket(), " updated to ", NormalizeDouble(new_sl_price, _Digits));
                                }
                            }
                        }
                        break;
                    }
                    case TRAILING_IN_MONEY:
                    {
                        double current_profit = position.Profit();
                        
                        if(current_profit < InpTrailingStartMoney)
                        {
                            continue; // Skip to the next position
                        }
                        
                        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                        if(tick_size == 0 || tick_value == 0) continue;
                        
                        double value_per_point_1_lot = tick_value * (_Point / tick_size);
                        if(value_per_point_1_lot == 0) continue;
                        
                        double value_per_point_position = value_per_point_1_lot * position.Volume();
                        if(value_per_point_position == 0) continue;
                        
                        double points_offset = InpTrailingStopMoney / value_per_point_position;
                        double price_offset = points_offset * _Point;

                        double new_sl_price = 0;
                        
                        if(position.PositionType() == POSITION_TYPE_BUY)
                        {
                            new_sl_price = current_tick.bid - price_offset;
                            if(new_sl_price > (position.StopLoss() + _Point) && (current_tick.bid - new_sl_price) >= (stops_level * _Point))
                            {
                                if(!trade.PositionModify(position.Ticket(), NormalizeDouble(new_sl_price, _Digits), position.TakeProfit()))
                                    Print("Error modifying BUY position #", position.Ticket(), " for trailing stop (Money). Error: ", GetLastError());
                                else
                                    Print("Trailing stop for BUY #", position.Ticket(), " updated to ", NormalizeDouble(new_sl_price, _Digits));
                            }
                        }
                        else if(position.PositionType() == POSITION_TYPE_SELL)
                        {
                            new_sl_price = current_tick.ask + price_offset;
                            if((new_sl_price < (position.StopLoss() - _Point) || position.StopLoss() == 0) && (new_sl_price - current_tick.ask) >= (stops_level * _Point))
                            {
                                if(!trade.PositionModify(position.Ticket(), NormalizeDouble(new_sl_price, _Digits), position.TakeProfit()))
                                    Print("Error modifying SELL position #", position.Ticket(), " for trailing stop (Money). Error: ", GetLastError());
                                else
                                    Print("Trailing stop for SELL #", position.Ticket(), " updated to ", NormalizeDouble(new_sl_price, _Digits));
                            }
                        }
                        break;
                    }
                } // end switch
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper function to convert HH:MM string to minutes of the day    |
//+------------------------------------------------------------------+
int TimeToMinutes(string time_str)
{
    string parts[];
    if(StringSplit(time_str, ':', parts) != 2) return -1; // Invalid format
    int hour = (int)StringToInteger(parts[0]);
    int minute = (int)StringToInteger(parts[1]);
    if(hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1; // Invalid time
    return (hour * 60 + minute);
}

//+------------------------------------------------------------------+
//| Check if the current time is within a defined trading session    |
//+------------------------------------------------------------------+
bool IsWithinTradingSession()
{
    MqlDateTime current_time;
    TimeCurrent(current_time); // Gets server time

    int current_day_of_week = current_time.day_of_week; // 0=Sunday, 1=Monday, ...
    int current_minutes_of_day = current_time.hour * 60 + current_time.min;

    string session_string = "";
    //--- Get the correct session string for the current day
    switch(current_day_of_week)
    {
        case 0: session_string = InpSundayTimes; break;
        case 1: session_string = InpMondayTimes; break;
        case 2: session_string = InpTuesdayTimes; break;
        case 3: session_string = InpWednesdayTimes; break;
        case 4: session_string = InpThursdayTimes; break;
        case 5: session_string = InpFridayTimes; break;
        case 6: session_string = InpSaturdayTimes; break;
    }

    //--- If the string is empty or indicates closed, return false
    if(session_string == "" || session_string == "00:00-00:00") return false;

    //--- Split the string by ';' to handle multiple sessions in one day
    string session_parts[];
    int num_sessions = StringSplit(session_string, ';', session_parts);

    for(int i = 0; i < num_sessions; i++)
    {
        //--- Split each session part by '-' to get start and end times
        string time_range[];
        if(StringSplit(session_parts[i], '-', time_range) != 2) continue; // Skip invalid range format

        int start_minutes = TimeToMinutes(time_range[0]);
        int end_minutes = TimeToMinutes(time_range[1]);
        
        if (start_minutes == -1 || end_minutes == -1) continue; // Invalid time format

        //--- Check if current time falls within the session range
        if(current_minutes_of_day >= start_minutes && current_minutes_of_day < end_minutes)
        {
            return true; // We are in a valid session
        }
    }

    //--- If no matching session was found after checking all ranges
    return false;
}

//+------------------------------------------------------------------+
//| Close all open positions managed by this EA                      |
//+------------------------------------------------------------------+
int CloseAllOpenPositions()
{
    int closed_count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Magic() == InpMagicNumber && position.Symbol() == _Symbol)
            {
                if(trade.PositionClose(position.Ticket()))
                {
                    closed_count++;
                }
            }
        }
    }
    return closed_count;
}

//+------------------------------------------------------------------+
//| Checks if there is enough free margin to open a trade            |
//+------------------------------------------------------------------+
bool HasSufficientMargin(double lots)
{
    double margin_required;
    // For a buy position (margin is usually symmetrical for buy/sell)
    if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin_required))
    {
        Print("Could not calculate margin. Assuming insufficient funds.");
        return false;
    }

    if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin_required)
    {
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calculates the maximum lot size affordable with current free margin.|
//+------------------------------------------------------------------+
double CalculateMaxAffordableLot()
{
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double one_lot_margin;

    // Calculate margin required for 1.0 lot
    if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), one_lot_margin))
    {
        Print("Could not calculate margin for 1.0 lot. Cannot determine max affordable lot.");
        return 0.0; // Return 0 to prevent trading
    }

    if (one_lot_margin <= 0.0001) // Check for zero or very small margin to avoid division by zero
    {
        Print("Margin for 1 lot is zero. Cannot determine max affordable lot.");
        return 0.0;
    }

    // Max lot is free margin divided by margin for one lot. Subtract a small amount for buffer.
    double max_lot = (free_margin / one_lot_margin) * 0.98; // Use 98% of free margin for buffer
    
    return max_lot;
}