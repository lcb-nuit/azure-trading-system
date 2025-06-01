namespace TradingSystem.Core.Models
{
    public class VolumeAnalysisResult
    {
        public required string Ticker { get; set; }
        public bool SellersExhausted { get; set; }
        public bool BuyersSteppingIn { get; set; }
        public required string Notes { get; set; }
    }
} 