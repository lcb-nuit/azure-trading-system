namespace TradingSystem.Core.Models
{
    public class VolumeAnalysisResult
    {
        public string Ticker { get; set; }
        public bool SellersExhausted { get; set; }
        public bool BuyersSteppingIn { get; set; }
        public string Notes { get; set; }
    }
} 