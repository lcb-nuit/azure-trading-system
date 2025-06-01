using System.Collections.Generic;
using System.Threading.Tasks;
using TradingSystem.Core.Models;
using TradingSystem.Core.Interfaces;

namespace TradingSystem.Analysis
{
    public class StockUniverseService : IStockUniverseService
    {
        public Task<List<Stock>> RefreshUniverseAsync() => Task.FromResult(new List<Stock>());
    }
} 