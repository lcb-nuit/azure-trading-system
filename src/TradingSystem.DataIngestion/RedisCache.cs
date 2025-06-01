using System.Threading.Tasks;
using Microsoft.Extensions.Options;
using StackExchange.Redis;
using TradingSystem.Core.Interfaces;
using TradingSystem.Core.Configuration;

namespace TradingSystem.DataIngestion
{
    public class RedisCache : IRedisCache
    {
        private readonly ConnectionMultiplexer _redis;
        private readonly IDatabase _db;

        public RedisCache(IOptions<RedisConfig> config)
        {
            _redis = ConnectionMultiplexer.Connect(config.Value.ConnectionString);
            _db = _redis.GetDatabase();
        }

        public async Task SetAsync<T>(string key, T value)
        {
            var json = System.Text.Json.JsonSerializer.Serialize(value);
            await _db.StringSetAsync(key, json);
        }

        public async Task<T> GetAsync<T>(string key)
        {
            var value = await _db.StringGetAsync(key);
            if (value.IsNullOrEmpty) return default;
            return System.Text.Json.JsonSerializer.Deserialize<T>(value);
        }

        public async Task RemoveAsync(string key)
        {
            await _db.KeyDeleteAsync(key);
        }
    }
} 