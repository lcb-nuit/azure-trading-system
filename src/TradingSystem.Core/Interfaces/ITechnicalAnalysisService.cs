using System.Threading.Tasks;
using TradingSystem.Core.Models;

namespace TradingSystem.Core.Interfaces
{
    public interface ITechnicalAnalysisService
    {
        Task<TechnicalIndicators> CalculateIndicatorsAsync(string ticker);
    }
} 