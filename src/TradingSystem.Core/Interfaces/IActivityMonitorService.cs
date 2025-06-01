using System.Collections.Generic;
using System.Threading.Tasks;
using TradingSystem.Core.Models;

namespace TradingSystem.Core.Interfaces
{
    public interface IActivityMonitorService
    {
        Task<List<ActivityAlert>> DetectAnomaliesAsync();
    }
    public class ActivityAlert
    {
        public string Ticker { get; set; }
        public double VolumeRatio { get; set; }
        public string Notes { get; set; }
    }
} 