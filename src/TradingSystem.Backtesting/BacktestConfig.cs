using System;
using System.Collections.Generic;

namespace TradingSystem.Backtesting
{
    public class BacktestConfig
    {
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }
        public string[] Tickers { get; set; }
        public string ADXTableAggregates { get; set; }
        public string ADXTableTrades { get; set; }
        public string ADXTableQuotes { get; set; }
        public double SlippagePerTrade { get; set; }
        public double CommissionPerTrade { get; set; }
        public int PositionSize { get; set; }
        public double Leverage { get; set; }
        public string OrderType { get; set; }
        public List<ParameterSweepConfig> ParameterSweep { get; set; }
        public bool EnableOrderBookSimulation { get; set; }
        public bool EnableMultiAsset { get; set; }
        public bool EnableParameterSweep { get; set; }
        public bool EnableWalkForward { get; set; }
        public bool EnablePortfolioRisk { get; set; }
        public bool EnableAzureUploads { get; set; }
        public int MaxAssets { get; set; }
        public int MaxParallelJobs { get; set; }
        public string DataSource { get; set; }
        public List<string> OutputReports { get; set; }
        public bool UploadSummaryToAzure { get; set; }
    }

    public class ParameterSweepConfig
    {
        public int VolumeSpikeThreshold { get; set; }
        public double SignalConfidenceThreshold { get; set; }
    }
} 