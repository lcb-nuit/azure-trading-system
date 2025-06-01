using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using TradingSystem.Core.Models;
using TradingSystem.Backtesting;

namespace TradingSystem.Web.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class BacktestController : ControllerBase
    {
        private readonly IWebHostEnvironment _env;

        public class IndicatorSeries
        {
            public string Name { get; set; } = string.Empty;
            public List<object> X { get; set; } = new();
            public List<decimal> Y { get; set; } = new();
        }
        public class PriceAggregateDto
        {
            public DateTime Timestamp { get; set; }
            public decimal Open { get; set; }
            public decimal High { get; set; }
            public decimal Low { get; set; }
            public decimal Close { get; set; }
            public long Volume { get; set; }
        }
        public class BacktestResponse
        {
            public List<BacktestTrade> Trades { get; set; } = new();
            public List<decimal> EquityCurve { get; set; } = new();
            public List<decimal> Drawdown { get; set; } = new();
            public BacktestMetrics Metrics { get; set; } = new();
            public List<PriceAggregateDto> PriceAggregates { get; set; } = new();
            public List<IndicatorSeries> Indicators { get; set; } = new();
        }

        public BacktestController(IWebHostEnvironment env)
        {
            _env = env;
        }

        [HttpGet("latest")]
        public IActionResult GetLatestBacktest()
        {
            try
            {
                // Find the latest backtest files
                var directory = new DirectoryInfo(_env.ContentRootPath);
                var files = directory.GetFiles("backtest_trades_*.json")
                    .OrderByDescending(f => f.LastWriteTime)
                    .FirstOrDefault();

                if (files == null)
                    return NotFound("No backtest results found");

                // Read trades
                var trades = JsonSerializer.Deserialize<List<BacktestTrade>>(
                    System.IO.File.ReadAllText(files.FullName),
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
                );

                if (trades == null)
                    return NotFound("Invalid backtest data");

                // Calculate equity curve and drawdown
                var response = new BacktestResponse { Trades = trades };
                decimal runningEquity = 0;
                decimal peak = 0;
                
                foreach (var trade in trades)
                {
                    runningEquity += trade.NetProfitLoss ?? 0;
                    response.EquityCurve.Add(runningEquity);
                    
                    peak = Math.Max(peak, runningEquity);
                    var drawdown = peak > 0 ? (peak - runningEquity) / peak * 100 : 0;
                    response.Drawdown.Add(drawdown);
                }

                // Calculate metrics
                response.Metrics = new BacktestMetrics();
                response.Metrics.Compute(trades);

                // Load price aggregates (try to find a matching file)
                var aggFile = directory.GetFiles("backtest_aggregates_*.json").OrderByDescending(f => f.LastWriteTime).FirstOrDefault();
                List<PriceAggregateDto> priceAggregates = new();
                if (aggFile != null)
                {
                    priceAggregates = JsonSerializer.Deserialize<List<PriceAggregateDto>>(
                        System.IO.File.ReadAllText(aggFile.FullName),
                        new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
                    ) ?? new();
                }
                response.PriceAggregates = priceAggregates;
                // Dummy indicator data (replace with real indicators as needed)
                response.Indicators = new List<IndicatorSeries>
                {
                    new IndicatorSeries
                    {
                        Name = "SMA 20",
                        X = priceAggregates.Select(p => (object)p.Timestamp).ToList(),
                        Y = priceAggregates.Select((p, i) => i >= 19 ? priceAggregates.Skip(i-19).Take(20).Average(x => x.Close) : 0).ToList()
                    }
                };

                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, $"Error retrieving backtest data: {ex.Message}");
            }
        }
    }
} 