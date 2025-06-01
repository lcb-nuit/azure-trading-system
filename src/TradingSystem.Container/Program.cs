using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using TradingSystem.Core.Interfaces;
using TradingSystem.DataIngestion;
using TradingSystem.Analysis;
using TradingSystem.Core.Models; 
using Microsoft.Extensions.Configuration;
using TradingSystem.Core.Configuration;
using System;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Diagnostics;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((hostingContext, config) =>
    {
        config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
    })
    .ConfigureServices((context, services) =>
    {
        // Bind configuration
        services.Configure<PolygonConfig>(context.Configuration.GetSection("Polygon"));
        services.Configure<RedisConfig>(context.Configuration.GetSection("Redis"));
        services.Configure<AdxConfig>(context.Configuration.GetSection("ADX"));
        services.Configure<ProcessingConfig>(context.Configuration.GetSection("Processing"));
        // Register services
        services.AddSingleton<IPolygonWebSocketClient, PolygonWebSocketClient>();
        services.AddSingleton<IRedisCache, RedisCache>();
        services.AddSingleton<IAdxWriter, AdxWriter>();
        services.AddScoped<IStockUniverseService, StockUniverseService>();
        services.AddScoped<IActivityMonitorService, ActivityMonitorService>();
        services.AddScoped<ITechnicalAnalysisService, TechnicalAnalysisService>();
        services.AddScoped<ISignalGenerationService, SignalGenerationService>();
        services.AddSingleton<StubAnalysisService>();
        // TODO: Add hosted/background services for ingestion and processing
    })
    .Build();

// TEST CODE: Subscribe to Polygon events and print summaries
var wsClient = host.Services.GetRequiredService<IPolygonWebSocketClient>();
var redis = host.Services.GetRequiredService<IRedisCache>();
var analysis = host.Services.GetRequiredService<StubAnalysisService>();
var adxWriter = host.Services.GetRequiredService<IAdxWriter>();

// Batching buffers
var aggBatch = new List<PriceAggregate>();
var quoteBatch = new List<Quote>();
var tradeBatch = new List<Trade>();
var aggLock = new object();
var quoteLock = new object();
var tradeLock = new object();
// Analysis batch buffers
var aggAnalysisBatch = new List<PriceAggregate>();
var quoteAnalysisBatch = new List<Quote>();
var tradeAnalysisBatch = new List<Trade>();
var aggAnalysisLock = new object();
var quoteAnalysisLock = new object();
var tradeAnalysisLock = new object();

// Batch flush interval and size
var processingConfig = host.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<TradingSystem.Core.Configuration.ProcessingConfig>>().Value;
int batchSize = processingConfig.BatchSize;
var batchInterval = TimeSpan.FromMilliseconds(processingConfig.BatchIntervalMs);
int metricsInterval = processingConfig.MetricsIntervalMs;
var lastFlush = Stopwatch.StartNew();

// Batch flush task
_ = Task.Run(async () => {
    while (true)
    {
        if (lastFlush.Elapsed >= batchInterval)
        {
            try
            {
                // Redis batch flush
                List<PriceAggregate> aggToFlush;
                List<Quote> quoteToFlush;
                List<Trade> tradeToFlush;
                lock (aggLock) { aggToFlush = new List<PriceAggregate>(aggBatch); aggBatch.Clear(); }
                lock (quoteLock) { quoteToFlush = new List<Quote>(quoteBatch); quoteBatch.Clear(); }
                lock (tradeLock) { tradeToFlush = new List<Trade>(tradeBatch); tradeBatch.Clear(); }
                var tasks = new List<Task>();
                foreach (var agg in aggToFlush)
                {
                    try { tasks.Add(redis.SetAsync($"agg:{agg.Ticker}:{agg.Timestamp:O}", agg)); } catch (Exception ex) { Console.WriteLine($"[Error] Redis agg: {ex.Message}"); }
                }
                foreach (var quote in quoteToFlush)
                {
                    try { tasks.Add(redis.SetAsync($"quote:{quote.Ticker}:{quote.Timestamp:O}", quote)); } catch (Exception ex) { Console.WriteLine($"[Error] Redis quote: {ex.Message}"); }
                }
                foreach (var trade in tradeToFlush)
                {
                    try { tasks.Add(redis.SetAsync($"trade:{trade.Ticker}:{trade.Timestamp:O}", trade)); } catch (Exception ex) { Console.WriteLine($"[Error] Redis trade: {ex.Message}"); }
                }
                await Task.WhenAll(tasks);
                // ADX batch flush
                try { if (aggToFlush.Count > 0) await adxWriter.WriteAggregatesAsync(aggToFlush); } catch (Exception ex) { Console.WriteLine($"[ADX ERROR] Aggregates: {ex.Message}"); }
                try { if (quoteToFlush.Count > 0) await adxWriter.WriteQuotesAsync(quoteToFlush); } catch (Exception ex) { Console.WriteLine($"[ADX ERROR] Quotes: {ex.Message}"); }
                try { if (tradeToFlush.Count > 0) await adxWriter.WriteTradesAsync(tradeToFlush); } catch (Exception ex) { Console.WriteLine($"[ADX ERROR] Trades: {ex.Message}"); }
                // Analysis batch flush
                List<PriceAggregate> aggAnalysisToFlush;
                List<Quote> quoteAnalysisToFlush;
                List<Trade> tradeAnalysisToFlush;
                lock (aggAnalysisLock) { aggAnalysisToFlush = new List<PriceAggregate>(aggAnalysisBatch); aggAnalysisBatch.Clear(); }
                lock (quoteAnalysisLock) { quoteAnalysisToFlush = new List<Quote>(quoteAnalysisBatch); quoteAnalysisBatch.Clear(); }
                lock (tradeAnalysisLock) { tradeAnalysisToFlush = new List<Trade>(tradeAnalysisBatch); tradeAnalysisBatch.Clear(); }
                try { if (aggAnalysisToFlush.Count > 0) analysis.OnBatchAggregates(aggAnalysisToFlush); } catch (Exception ex) { Console.WriteLine($"[Error] BatchAnalysis agg: {ex.Message}"); }
                try { if (quoteAnalysisToFlush.Count > 0) analysis.OnBatchQuotes(quoteAnalysisToFlush); } catch (Exception ex) { Console.WriteLine($"[Error] BatchAnalysis quote: {ex.Message}"); }
                try { if (tradeAnalysisToFlush.Count > 0) analysis.OnBatchTrades(tradeAnalysisToFlush); } catch (Exception ex) { Console.WriteLine($"[Error] BatchAnalysis trade: {ex.Message}"); }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Error] Batch flush: {ex.Message}");
            }
            lastFlush.Restart();
        }
        await Task.Delay(100);
    }
});

wsClient.OnAggregateReceived += agg => {
    if (agg != null)
    {
        lock (aggLock) { aggBatch.Add(agg); if (aggBatch.Count >= batchSize) lastFlush.Restart(); }
        lock (aggAnalysisLock) { aggAnalysisBatch.Add(agg); if (aggAnalysisBatch.Count >= batchSize) lastFlush.Restart(); }
        try { analysis.OnAggregate(agg); } catch (Exception ex) { Console.WriteLine($"[Error] Analysis agg: {ex.Message}"); }
    }
};
wsClient.OnQuoteReceived += quote => {
    if (quote != null)
    {
        lock (quoteLock) { quoteBatch.Add(quote); if (quoteBatch.Count >= batchSize) lastFlush.Restart(); }
        lock (quoteAnalysisLock) { quoteAnalysisBatch.Add(quote); if (quoteAnalysisBatch.Count >= batchSize) lastFlush.Restart(); }
        try { analysis.OnQuote(quote); } catch (Exception ex) { Console.WriteLine($"[Error] Analysis quote: {ex.Message}"); }
    }
};
wsClient.OnTradeReceived += trade => {
    if (trade != null)
    {
        lock (tradeLock) { tradeBatch.Add(trade); if (tradeBatch.Count >= batchSize) lastFlush.Restart(); }
        lock (tradeAnalysisLock) { tradeAnalysisBatch.Add(trade); if (tradeAnalysisBatch.Count >= batchSize) lastFlush.Restart(); }
        try { analysis.OnTrade(trade); } catch (Exception ex) { Console.WriteLine($"[Error] Analysis trade: {ex.Message}"); }
    }
};

// Start the WebSocket client
await wsClient.ConnectAsync();

// Monitor queue size every 5 seconds (if possible)
_ = Task.Run(async () => {
    while (true)
    {
        if (wsClient is TradingSystem.DataIngestion.PolygonWebSocketClient poly)
        {
            var queueField = typeof(TradingSystem.DataIngestion.PolygonWebSocketClient).GetField("_messageQueue", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            if (queueField?.GetValue(poly) is System.Collections.ICollection queue)
            {
                Console.WriteLine($"[Monitor] Message queue size: {queue.Count}");
            }
        }
        await Task.Delay(5000);
    }
});

// Periodic metrics logging
_ = Task.Run(async () => {
    while (true)
    {
        Console.WriteLine($"[Metrics] BatchCountAggregates: {analysis.BatchCountAggregates}, BatchCountQuotes: {analysis.BatchCountQuotes}, BatchCountTrades: {analysis.BatchCountTrades}, BatchErrorCount: {analysis.BatchErrorCount}");
        await Task.Delay(metricsInterval);
    }
});

Console.WriteLine("Press Enter to exit...");
Console.ReadLine();

await wsClient.DisconnectAsync();
