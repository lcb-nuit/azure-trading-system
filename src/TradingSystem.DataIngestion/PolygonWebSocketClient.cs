using System;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TradingSystem.Core.Models;
using TradingSystem.Core.Interfaces;
using TradingSystem.Core.Configuration;
using Websocket.Client;
using System.Net.WebSockets;

namespace TradingSystem.DataIngestion
{
    public class PolygonWebSocketClient : IPolygonWebSocketClient, IDisposable
    {
        private readonly PolygonConfig _config;
        private WebsocketClient _client = null!;
        private readonly ConcurrentQueue<string> _messageQueue = new();
        private Task _workerTask = Task.CompletedTask;
        private bool _running = false;

        public event Action<PriceAggregate>? OnAggregateReceived;
        public event Action<Quote>? OnQuoteReceived;
        public event Action<Trade>? OnTradeReceived;

        public PolygonWebSocketClient(IOptions<PolygonConfig> config)
        {
            _config = config.Value;
        }

        public async Task ConnectAsync()
        {
            var url = new Uri(_config.WebSocketUrl);
            _client = new WebsocketClient(url);
            _client.ReconnectTimeout = TimeSpan.FromSeconds(30);
            _client.MessageReceived.Subscribe(msg =>
            {
                if (!string.IsNullOrEmpty(msg.Text))
                    _messageQueue.Enqueue(msg.Text);
            });

            await _client.Start();
            await AuthenticateAndSubscribeAsync();
            _running = true;
            _workerTask = Task.Run(ProcessMessagesAsync);
        }

        private async Task AuthenticateAndSubscribeAsync()
        {
            // Authenticate
            var authMsg = $"{{\"action\":\"auth\",\"params\":\"{_config.ApiKey}\"}}";
            await _client.SendInstant(authMsg);
            // Subscribe
            if (_config.Channels != null && _config.Channels.Count > 0)
            {
                var channels = string.Join(",", _config.Channels);
                var subMsg = $"{{\"action\":\"subscribe\",\"params\":\"{channels}\"}}";
                await _client.SendInstant(subMsg);
            }
        }

        private async Task ProcessMessagesAsync()
        {
            while (_running)
            {
                while (_messageQueue.TryDequeue(out var msg))
                {
                    try
                    {
                        // Polygon sends arrays of messages
                        var doc = JsonDocument.Parse(msg);
                        if (doc.RootElement.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var element in doc.RootElement.EnumerateArray())
                            {
                                DispatchMessage(element);
                            }
                        }
                        else
                        {
                            DispatchMessage(doc.RootElement);
                        }
                    }
                    catch (Exception)
                    {
                        // TODO: Add logging or reconnect logic
                    }
                }
                await Task.Delay(5); // Tune as needed
            }
        }

        private void DispatchMessage(JsonElement element)
        {
            if (!element.TryGetProperty("ev", out var evProp)) return;
            var ev = evProp.GetString();
            switch (ev)
            {
                case "A": // Aggregate
                    var agg = JsonSerializer.Deserialize<PriceAggregate>(element.GetRawText());
                    if (agg != null)
                        OnAggregateReceived?.Invoke(agg);
                    break;
                case "Q": // Quote
                    var quote = JsonSerializer.Deserialize<Quote>(element.GetRawText());
                    if (quote != null)
                        OnQuoteReceived?.Invoke(quote);
                    break;
                case "T": // Trade
                    var trade = JsonSerializer.Deserialize<Trade>(element.GetRawText());
                    if (trade != null)
                        OnTradeReceived?.Invoke(trade);
                    break;
                default:
                    break;
            }
        }

        public async Task DisconnectAsync()
        {
            _running = false;
            if (_client != null)
                await _client.Stop(WebSocketCloseStatus.NormalClosure, "Client disconnect");
            if (_workerTask != null)
                await _workerTask;
        }

        public void Dispose()
        {
            _running = false;
            _client?.Dispose();
        }
    }
} 