using Microsoft.AspNetCore.Mvc;
using TradingSystem.DataIngestion;
using Microsoft.Extensions.Options;
using TradingSystem.Core.Configuration;

namespace TradingSystem.Web.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AdxAnalyticsController : ControllerBase
    {
        private readonly AdxWriter _adxWriter;

        public AdxAnalyticsController(IOptions<AdxConfig> adxConfig)
        {
            _adxWriter = new AdxWriter(adxConfig);
        }

        [HttpGet("summary")]
        public async Task<IActionResult> GetSummary()
        {
            // Example: total trades, average price, etc.
            string query = @"
market_data
| summarize count() as TotalRows, avg(close) as AvgClose by ticker
";
            var results = await _adxWriter.QueryAsync(query);
            return Ok(results);
        }

        [HttpPost("custom-query")]
        public async Task<IActionResult> CustomQuery([FromBody] string kustoQuery)
        {
            var results = await _adxWriter.QueryAsync(kustoQuery);
            return Ok(results);
        }

        [HttpGet("equity-curve")]
        public async Task<IActionResult> GetEquityCurve()
        {
            string query = @"
market_data
| summarize Equity = sum(close) by timestamp
| order by timestamp asc
";
            var results = await _adxWriter.QueryAsync(query);
            return Ok(results);
        }

        [HttpGet("drawdown")]
        public async Task<IActionResult> GetDrawdown()
        {
            string query = @"
let equity = market_data | summarize Equity = sum(close) by timestamp | order by timestamp asc;
equity
| extend Peak = row_cumsum(max_of(Equity, 0))
| extend Drawdown = iif(Peak > 0, (Peak - Equity) / Peak * 100, 0)
| project timestamp, Drawdown
";
            var results = await _adxWriter.QueryAsync(query);
            return Ok(results);
        }

        [HttpGet("pl-by-day")]
        public async Task<IActionResult> GetPLByDay()
        {
            string query = @"
market_data
| summarize DailyPL = sum(close - open) by bin(timestamp, 1d)
| order by timestamp asc
";
            var results = await _adxWriter.QueryAsync(query);
            return Ok(results);
        }

        [HttpGet("trade-stats")]
        public async Task<IActionResult> GetTradeStats()
        {
            string query = @"
trades
| summarize TotalTrades = count(), WinCount = countif(netProfitLoss > 0), LossCount = countif(netProfitLoss <= 0), WinRate = toreal(countif(netProfitLoss > 0)) / count()
";
            var results = await _adxWriter.QueryAsync(query);
            return Ok(results);
        }

        [HttpGet("top-tickers")]
        public async Task<IActionResult> GetTopTickers()
        {
            string query = @"
market_data
| summarize TotalVolume = sum(volume), TotalPL = sum(close - open) by ticker
| top 10 by TotalVolume desc
";
            var results = await _adxWriter.QueryAsync(query);
            return Ok(results);
        }
    }
} 