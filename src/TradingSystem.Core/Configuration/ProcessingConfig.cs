namespace TradingSystem.Core.Configuration
{
    public class ProcessingConfig
    {
        public int BatchSize { get; set; }
        public int BatchIntervalMs { get; set; }
        public int MetricsIntervalMs { get; set; }
        public int MaxQueueSize { get; set; }
        public int WorkerCount { get; set; }
        public int VolumeSpikeThreshold { get; set; }
        public double PriceChangeThreshold { get; set; }
        public double SignalConfidenceThreshold { get; set; }
        public int AnalysisIntervalMs { get; set; }
        public int UniverseRefreshIntervalMs { get; set; }
        public int ActivityDetectionIntervalMs { get; set; }
        public int TechnicalAnalysisIntervalMs { get; set; }
        public int SignalGenerationIntervalMs { get; set; }
        public bool AlertEnabled { get; set; }
        public required string AlertEmail { get; set; }
        public required string AlertSlackWebhook { get; set; }
        public int AlertVolumeThreshold { get; set; }
        public int AlertLatencyThresholdMs { get; set; }
        public required string LogLevel { get; set; }
        public int MaxErrorCountBeforeAlert { get; set; }
        public bool DeadLetterQueueEnabled { get; set; }
    }
} 