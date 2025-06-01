using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using TradingSystem.Core.Models;

namespace TradingSystem.Analysis
{
    public class StubAnalysisService
    {
        public int BatchErrorCount { get; private set; } = 0;
        public int BatchCountAggregates { get; private set; } = 0;
        public int BatchCountQuotes { get; private set; } = 0;
        public int BatchCountTrades { get; private set; } = 0;

        public void OnAggregate(PriceAggregate agg)
        {
            Console.WriteLine($"[Analysis] Aggregate: {agg?.Ticker} {agg?.Timestamp} {agg?.Close}");
        }
        public void OnQuote(Quote quote)
        {
            Console.WriteLine($"[Analysis] Quote: {quote?.Ticker} {quote?.BidPrice}/{quote?.AskPrice}");
        }
        public void OnTrade(Trade trade)
        {
            Console.WriteLine($"[Analysis] Trade: {trade?.Ticker} {trade?.Price} x {trade?.Size}");
        }

        public void OnBatchAggregates(List<PriceAggregate> aggs)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                BatchCountAggregates += aggs.Count;
                if (aggs.Count > 0)
                {
                    var avgPrice = aggs.Average(a => (double)a.Close);
                    var totalVolume = aggs.Sum(a => a.Volume);
                    var minPrice = aggs.Min(a => a.Low);
                    var maxPrice = aggs.Max(a => a.High);
                    Console.WriteLine($"[BatchAnalysis] {aggs.Count} aggregates | AvgPrice: {avgPrice:F2} | TotalVol: {totalVolume} | Min: {minPrice} | Max: {maxPrice}");
                }
            }
            catch (Exception ex)
            {
                BatchErrorCount++;
                Console.WriteLine($"[Error] BatchAnalysis agg: {ex.Message}");
            }
            finally { sw.Stop(); Console.WriteLine($"[BatchAnalysis] Aggregates batch latency: {sw.ElapsedMilliseconds} ms"); }
        }
        public void OnBatchQuotes(List<Quote> quotes)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                BatchCountQuotes += quotes.Count;
                if (quotes.Count > 0)
                {
                    var avgBid = quotes.Average(q => (double)q.BidPrice);
                    var avgAsk = quotes.Average(q => (double)q.AskPrice);
                    var minSpread = quotes.Min(q => q.AskPrice - q.BidPrice);
                    var maxSpread = quotes.Max(q => q.AskPrice - q.BidPrice);
                    Console.WriteLine($"[BatchAnalysis] {quotes.Count} quotes | AvgBid: {avgBid:F2} | AvgAsk: {avgAsk:F2} | MinSpread: {minSpread} | MaxSpread: {maxSpread}");
                }
            }
            catch (Exception ex)
            {
                BatchErrorCount++;
                Console.WriteLine($"[Error] BatchAnalysis quote: {ex.Message}");
            }
            finally { sw.Stop(); Console.WriteLine($"[BatchAnalysis] Quotes batch latency: {sw.ElapsedMilliseconds} ms"); }
        }
        public void OnBatchTrades(List<Trade> trades)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                BatchCountTrades += trades.Count;
                if (trades.Count > 0)
                {
                    var avgPrice = trades.Average(t => (double)t.Price);
                    var totalSize = trades.Sum(t => t.Size);
                    var minPrice = trades.Min(t => t.Price);
                    var maxPrice = trades.Max(t => t.Price);
                    Console.WriteLine($"[BatchAnalysis] {trades.Count} trades | AvgPrice: {avgPrice:F2} | TotalSize: {totalSize} | Min: {minPrice} | Max: {maxPrice}");
                }
            }
            catch (Exception ex)
            {
                BatchErrorCount++;
                Console.WriteLine($"[Error] BatchAnalysis trade: {ex.Message}");
            }
            finally { sw.Stop(); Console.WriteLine($"[BatchAnalysis] Trades batch latency: {sw.ElapsedMilliseconds} ms"); }
        }
    }
} 