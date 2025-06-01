using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace TradingSystem.Web.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AnalyticsController : ControllerBase
    {
        [HttpGet("live")]
        public async Task<IActionResult> GetLiveAnalytics()
        {
            // TODO: Replace with real live analytics (from Redis, in-memory, etc.)
            var live = new Dictionary<string, object>
            {
                ["ActiveTrades"] = 5,
                ["CurrentEquity"] = 105000.25,
                ["OpenPL"] = 1200.50,
                ["RecentSignal"] = "BUY",
                ["LastUpdate"] = System.DateTime.UtcNow
            };
            return Ok(live);
        }
    }
} 