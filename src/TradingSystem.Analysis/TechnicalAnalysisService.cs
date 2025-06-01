using System.Threading.Tasks;
using TradingSystem.Core.Models;
using TradingSystem.Core.Interfaces;

namespace TradingSystem.Analysis
{
    public class TechnicalAnalysisService : ITechnicalAnalysisService
    {
        public Task<TechnicalIndicators> CalculateIndicatorsAsync(string ticker) => Task.FromResult(new TechnicalIndicators());
    }
} 