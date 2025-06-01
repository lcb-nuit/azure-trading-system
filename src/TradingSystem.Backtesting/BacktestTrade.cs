using System;

namespace TradingSystem.Backtesting
{
    public class BacktestTrade
    {
        public string Ticker { get; set; }
        public DateTime EntryTime { get; set; }
        public decimal EntryPrice { get; set; }
        public DateTime? ExitTime { get; set; }
        public decimal? ExitPrice { get; set; }
        public string Direction { get; set; } // "Long" or "Short"
        public string OrderType { get; set; }
        public int Size { get; set; }
        public double Slippage { get; set; }
        public double Commission { get; set; }
        public decimal? GrossProfitLoss => (ExitPrice.HasValue && Direction == "Long") ? (ExitPrice - EntryPrice) * Size : (ExitPrice.HasValue && Direction == "Short") ? (EntryPrice - ExitPrice) * Size : null;
        public decimal? NetProfitLoss => GrossProfitLoss.HasValue ? GrossProfitLoss - (decimal)Commission - (decimal)Slippage : null;
        public TimeSpan? Duration => ExitTime.HasValue ? ExitTime - EntryTime : null;
        public double? EntryConfidence { get; set; }
        public double? ExitConfidence { get; set; }
    }
} 