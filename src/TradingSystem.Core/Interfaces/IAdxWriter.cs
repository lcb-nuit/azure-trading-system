using System.Threading.Tasks;
using System.Collections.Generic;
using TradingSystem.Core.Models;

namespace TradingSystem.Core.Interfaces
{
    public interface IAdxWriter
    {
        Task WriteMarketDataAsync(object data);
        Task WriteTickDataAsync(object data);
        Task WriteSignalsAsync(object signals);
        Task WriteAggregatesAsync(List<PriceAggregate> aggs);
        Task WriteQuotesAsync(List<Quote> quotes);
        Task WriteTradesAsync(List<Trade> trades);
    }
} 