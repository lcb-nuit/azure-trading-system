using System;
using System.Collections.Generic;
using System.Linq;

namespace TradingSystem.Backtesting
{
    public class BacktestMetrics
    {
        public List<decimal> EquityCurve { get; set; } = new();
        public decimal MaxDrawdown { get; set; }
        public double SharpeRatio { get; set; }
        public int WinCount { get; set; }
        public int LossCount { get; set; }
        public int TotalTrades { get; set; }
        public decimal TotalPL { get; set; }
        public List<BacktestTrade> DeadLetterQueue { get; set; } = new();

        public void Compute(List<BacktestTrade> trades, double riskFreeRate = 0)
        {
            EquityCurve.Clear();
            decimal equity = 0;
            foreach (var t in trades)
            {
                equity += t.NetProfitLoss ?? 0;
                EquityCurve.Add(equity);
            }
            TotalPL = trades.Sum(t => t.NetProfitLoss ?? 0);
            TotalTrades = trades.Count;
            WinCount = trades.Count(t => (t.NetProfitLoss ?? 0) > 0);
            LossCount = trades.Count(t => (t.NetProfitLoss ?? 0) <= 0);
            MaxDrawdown = EquityCurve.Count > 0 ? EquityCurve.Max() - EquityCurve.Min() : 0;
            // Sharpe ratio
            var returns = EquityCurve.Skip(1).Zip(EquityCurve, (curr, prev) => (double)(curr - prev)).ToList();
            var avgReturn = returns.Count > 0 ? returns.Average() : 0;
            var stdDev = returns.Count > 1 ? Math.Sqrt(returns.Select(r => Math.Pow(r - avgReturn, 2)).Sum() / (returns.Count - 1)) : 0;
            SharpeRatio = stdDev > 0 ? (avgReturn - riskFreeRate) / stdDev : 0;
        }
    }
} 