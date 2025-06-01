using System;

namespace TradingSystem.Core.Models
{
    public class PriceAggregate
    {
        public string Ticker { get; set; }
        public DateTime Timestamp { get; set; }
        public decimal Open { get; set; }
        public decimal Close { get; set; }
        public decimal High { get; set; }
        public decimal Low { get; set; }
        public long Volume { get; set; }
    }
} 