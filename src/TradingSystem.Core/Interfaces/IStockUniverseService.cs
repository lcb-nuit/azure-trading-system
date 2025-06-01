using System.Collections.Generic;
using System.Threading.Tasks;
using TradingSystem.Core.Models;

namespace TradingSystem.Core.Interfaces
{
    public interface IStockUniverseService
    {
        Task<List<Stock>> RefreshUniverseAsync();
    }
} 