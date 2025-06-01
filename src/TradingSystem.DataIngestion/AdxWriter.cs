using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Extensions.Options;
using Kusto.Data;
using Kusto.Ingest;
using Kusto.Data.Common;
using Kusto.Data.Net.Client;
using TradingSystem.Core.Interfaces;
using TradingSystem.Core.Configuration;
using TradingSystem.Core.Models;
using System.IO;
using System.Text.Json;
using System.Threading;

namespace TradingSystem.DataIngestion
{
    public class AdxWriter : IAdxWriter
    {
        private readonly AdxConfig _config;
        private readonly IKustoIngestClient _ingestClient;
        private readonly string _database;

        public AdxWriter(IOptions<AdxConfig> config)
        {
            _config = config.Value;
            var kcsb = new KustoConnectionStringBuilder(_config.ClusterUri);
            _ingestClient = KustoIngestFactory.CreateDirectIngestClient(kcsb);
            _database = _config.Database;
        }

        public async Task WriteMarketDataAsync(object data)
        {
            await IngestBatchAsync("market_data", data);
        }
        public async Task WriteTickDataAsync(object data)
        {
            await IngestBatchAsync("tick_data", data);
        }
        public async Task WriteSignalsAsync(object signals)
        {
            await IngestBatchAsync("trade_signals", signals);
        }

        public async Task WriteAggregatesAsync(List<PriceAggregate> aggs)
        {
            await IngestBatchAsync("market_data", aggs);
        }
        public async Task WriteQuotesAsync(List<Quote> quotes)
        {
            await IngestBatchAsync("quotes", quotes);
        }
        public async Task WriteTradesAsync(List<Trade> trades)
        {
            await IngestBatchAsync("trades", trades);
        }

        private async Task IngestBatchAsync<T>(string table, T batch)
        {
            int maxRetries = 3;
            int delayMs = 1000;
            for (int attempt = 1; attempt <= maxRetries; attempt++)
            {
                try
                {
                    // --- Custom serialization/mapping placeholder ---
                    // If you need to map/transform fields, do it here before serialization
                    var json = JsonSerializer.Serialize(batch, new JsonSerializerOptions
                    {
                        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                        WriteIndented = false
                    });
                    using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
                    var props = new KustoIngestionProperties(_database, table)
                    {
                        Format = DataSourceFormat.json
                    };
                    await _ingestClient.IngestFromStreamAsync(stream, props);
                    Console.WriteLine($"[ADX] Ingested batch to {table}: {json.Length} bytes");
                    return;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[ADX ERROR] Attempt {attempt} failed to ingest batch to {table}: {ex.Message}");
                    if (attempt == maxRetries)
                    {
                        // --- Dead-letter queue ---
                        var deadLetterDir = Path.Combine(AppContext.BaseDirectory, "deadletter");
                        Directory.CreateDirectory(deadLetterDir);
                        var fileName = $"deadletter_{table}_{DateTime.UtcNow:yyyyMMdd_HHmmss_fff}.json";
                        var filePath = Path.Combine(deadLetterDir, fileName);
                        try
                        {
                            var json = JsonSerializer.Serialize(batch, new JsonSerializerOptions { WriteIndented = true });
                            File.WriteAllText(filePath, json);
                            Console.WriteLine($"[ADX DEADLETTER] Wrote failed batch to {filePath}");
                        }
                        catch (Exception fileEx)
                        {
                            Console.WriteLine($"[ADX DEADLETTER ERROR] Could not write deadletter file: {fileEx.Message}");
                        }
                    }
                    else
                    {
                        // Exponential backoff
                        Thread.Sleep(delayMs);
                        delayMs *= 2;
                    }
                }
            }
        }

        public async Task<List<Dictionary<string, object>>> QueryAsync(string kustoQuery)
        {
            return await Task.Run(() =>
            {
                var results = new List<Dictionary<string, object>>();
                var kcsb = new KustoConnectionStringBuilder(_config.ClusterUri);
                using var queryProvider = KustoClientFactory.CreateCslQueryProvider(kcsb);
                using var reader = queryProvider.ExecuteQuery(_database, kustoQuery, new ClientRequestProperties());
                while (reader.Read())
                {
                    var row = new Dictionary<string, object>();
                    for (int i = 0; i < reader.FieldCount; i++)
                    {
                        row[reader.GetName(i)] = reader.GetValue(i);
                    }
                    results.Add(row);
                }
                return results;
            });
        }
    }
} 