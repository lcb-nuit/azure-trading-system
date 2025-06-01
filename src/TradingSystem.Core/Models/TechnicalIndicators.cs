namespace TradingSystem.Core.Models
{
    public class MACDResult { public double Value { get; set; } public bool CrossoverUp { get; set; } public bool CrossoverDown { get; set; } }
    public class StochasticResult { public double K { get; set; } public double D { get; set; } }
    public class TechnicalIndicators
    {
        public MACDResult MACD { get; set; }
        public StochasticResult Stochastic { get; set; }
        public double RSI { get; set; }
        public double MomentumScore { get; set; }
        public string[] Patterns { get; set; }
    }
} 