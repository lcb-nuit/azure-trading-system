namespace TradingSystem.Core.Configuration
{
    public class PolygonConfig
    {
        public required string ApiKey { get; set; }
        public required string WebSocketUrl { get; set; }
        public required List<string> Channels { get; set; }
    }
} 