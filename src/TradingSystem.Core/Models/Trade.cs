using System;

namespace TradingSystem.Core.Models
{
    public class Trade
    {
        public required string Ticker { get; set; }
        public DateTime Timestamp { get; set; }
        public decimal Price { get; set; }
        public long Size { get; set; }
    }
} 