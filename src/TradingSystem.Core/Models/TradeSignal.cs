using System;

namespace TradingSystem.Core.Models
{
    public enum SignalType { EntryLong, Exit, Hold }
    public class TradeSignal
    {
        public DateTime Timestamp { get; set; }
        public string Ticker { get; set; }
        public SignalType Type { get; set; }
        public double Confidence { get; set; }
    }
} 