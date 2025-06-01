using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.Azure.Kusto.Data;
using TradingSystem.Core.Configuration;
using TradingSystem.Core.Models;
using TradingSystem.Analysis;
using System.IO;
using System.Text.Json;
using System.Text;
using TradingSystem.Backtesting;
using TradingSystem.Core.Interfaces;

namespace TradingSystem.Backtesting
{
    class Program
    {
        static async Task Main(string[] args)
        {
            // Load config
            var config = new ConfigurationBuilder()
                .AddJsonFile("appsettings.json")
                .Build();
            var services = new ServiceCollection();
            services.Configure<ProcessingConfig>(config.GetSection("Processing"));
            services.Configure<BacktestConfig>(config.GetSection("Backtest"));
            services.Configure<AdxConfig>(config.GetSection("ADX"));
            services.AddSingleton<StubAnalysisService>();
            services.AddScoped<ITechnicalAnalysisService, TechnicalAnalysisService>();
            services.AddScoped<ISignalGenerationService, SignalGenerationService>();
            var provider = services.BuildServiceProvider();
            var processingConfig = provider.GetRequiredService<IOptions<ProcessingConfig>>().Value;
            var backtestConfig = provider.GetRequiredService<IOptions<BacktestConfig>>().Value;
            var adxConfig = provider.GetRequiredService<IOptions<AdxConfig>>().Value;
            var analysis = provider.GetRequiredService<StubAnalysisService>();
            var taService = provider.GetRequiredService<ITechnicalAnalysisService>();
            var signalService = provider.GetRequiredService<ISignalGenerationService>();

            // Connect to ADX
            var kcsb = new KustoConnectionStringBuilder(adxConfig.ClusterUri);
            var queryProvider = KustoClientFactory.CreateCslQueryProvider(kcsb);

            // Query historical data (aggregates only for demo)
            var query = $@"
{backtestConfig.ADXTableAggregates}
| where timestamp between (datetime({backtestConfig.StartDate:yyyy-MM-dd}) .. datetime({backtestConfig.EndDate:yyyy-MM-dd}))
| where ticker in ({string.Join(",", backtestConfig.Tickers.Select(t => $"'{t}'"))})
| order by timestamp asc
";
            var reader = queryProvider.ExecuteQuery(adxConfig.Database, query);
            var aggs = new List<PriceAggregate>();
            while (reader.Read())
            {
                aggs.Add(new PriceAggregate
                {
                    Ticker = reader["ticker"].ToString(),
                    Timestamp = (DateTime)reader["timestamp"],
                    Open = Convert.ToDecimal(reader["open"]),
                    Close = Convert.ToDecimal(reader["close"]),
                    High = Convert.ToDecimal(reader["high"]),
                    Low = Convert.ToDecimal(reader["low"]),
                    Volume = Convert.ToInt64(reader["volume"])
                });
            }
            Console.WriteLine($"Loaded {aggs.Count} aggregates from ADX");

            // Parameter sweep support
            var sweepConfigs = backtestConfig.ParameterSweep ?? new List<ParameterSweepConfig> { new ParameterSweepConfig { VolumeSpikeThreshold = processingConfig.VolumeSpikeThreshold, SignalConfidenceThreshold = processingConfig.SignalConfidenceThreshold } };
            foreach (var sweep in sweepConfigs)
            {
                Console.WriteLine($"Running backtest with VolumeSpikeThreshold={sweep.VolumeSpikeThreshold}, SignalConfidenceThreshold={sweep.SignalConfidenceThreshold}");
                // (Optionally) update processingConfig here if needed
                // Trade simulation and metrics
                var trades = new List<BacktestTrade>();
                var metrics = new BacktestMetrics();
                BacktestTrade openTrade = null;
                decimal equity = 0;
                decimal maxEquity = 0;
                decimal minEquity = 0;
                int wins = 0, losses = 0;
                int batchSize = processingConfig.BatchSize;
                var batch = new List<PriceAggregate>();
                foreach (var agg in aggs)
                {
                    try
                    {
                        // Use real technical analysis and signal generation
                        var indicators = await taService.CalculateIndicatorsAsync(agg.Ticker); // You may want to pass price history
                        var signal = await signalService.GenerateSignalAsync(agg.Ticker, indicators);
                        // Simulate trade logic: open on EntryLong, close on Exit
                        if (openTrade == null && signal.Type == Core.Models.SignalType.EntryLong)
                        {
                            openTrade = new BacktestTrade
                            {
                                Ticker = agg.Ticker,
                                EntryTime = agg.Timestamp,
                                EntryPrice = agg.Close + (decimal)backtestConfig.SlippagePerTrade,
                                Direction = "Long",
                                OrderType = backtestConfig.OrderType,
                                Size = backtestConfig.PositionSize,
                                Slippage = backtestConfig.SlippagePerTrade,
                                Commission = backtestConfig.CommissionPerTrade,
                                EntryConfidence = signal.Confidence
                            };
                        }
                        else if (openTrade != null && signal.Type == Core.Models.SignalType.Exit)
                        {
                            openTrade.ExitTime = agg.Timestamp;
                            openTrade.ExitPrice = agg.Close - (decimal)backtestConfig.SlippagePerTrade;
                            openTrade.ExitConfidence = signal.Confidence;
                            trades.Add(openTrade);
                            var pl = openTrade.NetProfitLoss ?? 0;
                            equity += pl;
                            if (pl > 0) wins++; else losses++;
                            maxEquity = Math.Max(maxEquity, equity);
                            minEquity = Math.Min(minEquity, equity);
                            openTrade = null;
                        }
                        batch.Add(agg);
                        if (batch.Count >= batchSize)
                        {
                            analysis.OnBatchAggregates(new List<PriceAggregate>(batch));
                            batch.Clear();
                        }
                    }
                    catch (Exception ex)
                    {
                        metrics.DeadLetterQueue.Add(openTrade);
                        Console.WriteLine($"[DeadLetter] {ex.Message}");
                    }
                }
                if (batch.Count > 0)
                    analysis.OnBatchAggregates(batch);
                if (openTrade != null)
                {
                    // Force close at end
                    openTrade.ExitTime = aggs.Last().Timestamp;
                    openTrade.ExitPrice = aggs.Last().Close;
                    trades.Add(openTrade);
                    var pl = openTrade.NetProfitLoss ?? 0;
                    equity += pl;
                    if (pl > 0) wins++; else losses++;
                    maxEquity = Math.Max(maxEquity, equity);
                    minEquity = Math.Min(minEquity, equity);
                }
                // Compute metrics
                metrics.Compute(trades);
                // Export results to CSV
                var csvPath = $"backtest_trades_{sweep.VolumeSpikeThreshold}_{sweep.SignalConfidenceThreshold}.csv";
                var sb = new StringBuilder();
                sb.AppendLine("Ticker,EntryTime,EntryPrice,ExitTime,ExitPrice,Direction,OrderType,Size,Slippage,Commission,GrossPL,NetPL,Duration");
                foreach (var t in trades)
                {
                    sb.AppendLine($"{t.Ticker},{t.EntryTime:o},{t.EntryPrice},{t.ExitTime:o},{t.ExitPrice},{t.Direction},{t.OrderType},{t.Size},{t.Slippage},{t.Commission},{t.GrossProfitLoss},{t.NetProfitLoss},{t.Duration}");
                }
                File.WriteAllText(csvPath, sb.ToString());
                Console.WriteLine($"Exported trades to {csvPath}");
                // Export results to JSON
                var jsonPath = $"backtest_trades_{sweep.VolumeSpikeThreshold}_{sweep.SignalConfidenceThreshold}.json";
                File.WriteAllText(jsonPath, JsonSerializer.Serialize(trades, new JsonSerializerOptions { WriteIndented = true }));
                Console.WriteLine($"Exported trades to {jsonPath}");
                // Export summary HTML
                var htmlPath = $"backtest_summary_{sweep.VolumeSpikeThreshold}_{sweep.SignalConfidenceThreshold}.html";
                var html = $@"<html><body><h1>Backtest Summary</h1><ul><li>Trades: {metrics.TotalTrades}</li><li>Wins: {metrics.WinCount}</li><li>Losses: {metrics.LossCount}</li><li>WinRate: {(metrics.TotalTrades > 0 ? (double)metrics.WinCount / metrics.TotalTrades : 0):P2}</li><li>TotalPL: {metrics.TotalPL}</li><li>MaxDrawdown: {metrics.MaxDrawdown}</li><li>SharpeRatio: {metrics.SharpeRatio:F2}</li></ul></body></html>";
                File.WriteAllText(htmlPath, html);
                Console.WriteLine($"Exported summary to {htmlPath}");
                // Dead letter queue
                if (metrics.DeadLetterQueue.Count > 0)
                {
                    var deadPath = $"backtest_deadletter_{sweep.VolumeSpikeThreshold}_{sweep.SignalConfidenceThreshold}.json";
                    File.WriteAllText(deadPath, JsonSerializer.Serialize(metrics.DeadLetterQueue, new JsonSerializerOptions { WriteIndented = true }));
                    Console.WriteLine($"Exported dead letter queue to {deadPath}");
                }
                // Export price aggregates for dashboard
                var aggJsonPath = $"backtest_aggregates_{sweep.VolumeSpikeThreshold}_{sweep.SignalConfidenceThreshold}.json";
                File.WriteAllText(aggJsonPath, JsonSerializer.Serialize(aggs, new JsonSerializerOptions { WriteIndented = true }));
                Console.WriteLine($"Exported price aggregates to {aggJsonPath}");
            }
        }
    }
}
