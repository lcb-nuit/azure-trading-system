using System.Threading.Tasks;
using TradingSystem.Core.Models;
using TradingSystem.Core.Interfaces;

namespace TradingSystem.Analysis
{
    public class SignalGenerationService : ISignalGenerationService
    {
        public Task<TradeSignal> GenerateSignalAsync(string ticker, TechnicalIndicators indicators) => Task.FromResult(new TradeSignal { Ticker = ticker });
    }
} 