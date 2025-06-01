using System;

namespace TradingSystem.Core.Models
{
    public class Quote
    {
        public required string Ticker { get; set; }
        public DateTime Timestamp { get; set; }
        public decimal BidPrice { get; set; }
        public long BidSize { get; set; }
        public decimal AskPrice { get; set; }
        public long AskSize { get; set; }
    }
} 