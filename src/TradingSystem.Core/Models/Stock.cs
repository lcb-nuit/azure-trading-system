namespace TradingSystem.Core.Models
{
    public class Stock
    {
        public string Ticker { get; set; }
        public decimal Price { get; set; }
        public long FloatShares { get; set; }
        public long Volume { get; set; }
        public decimal High { get; set; }
        public decimal Low { get; set; }
        public decimal Close { get; set; }
    }
} 