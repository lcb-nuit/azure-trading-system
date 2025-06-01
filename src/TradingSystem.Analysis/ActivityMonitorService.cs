using System.Collections.Generic;
using System.Threading.Tasks;
using TradingSystem.Core.Models;
using TradingSystem.Core.Interfaces;

namespace TradingSystem.Analysis
{
    public class ActivityMonitorService : IActivityMonitorService
    {
        public Task<List<ActivityAlert>> DetectAnomaliesAsync() => Task.FromResult(new List<ActivityAlert>());
    }
} 