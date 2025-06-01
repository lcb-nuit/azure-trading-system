using System.Threading.Tasks;
using TradingSystem.Core.Models;

namespace TradingSystem.Core.Interfaces
{
    public interface ISignalGenerationService
    {
        Task<TradeSignal> GenerateSignalAsync(string ticker, TechnicalIndicators indicators);
    }
} 