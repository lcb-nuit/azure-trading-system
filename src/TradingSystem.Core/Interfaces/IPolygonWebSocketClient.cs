using System;
using System.Threading.Tasks;
using TradingSystem.Core.Models;

namespace TradingSystem.Core.Interfaces
{
    public interface IPolygonWebSocketClient
    {
        event Action<PriceAggregate> OnAggregateReceived;
        event Action<Quote> OnQuoteReceived;
        event Action<Trade> OnTradeReceived;
        Task ConnectAsync();
        Task DisconnectAsync();
    }
} 