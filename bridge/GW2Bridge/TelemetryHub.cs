namespace GW2Bridge;

public sealed class TelemetryHub(ITelemetrySource source, ILogger<TelemetryHub> logger) : BackgroundService
{
    private TelemetryEnvelope _latest = new(
        1, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), false, 0, false,
        null, null, null, null, new UiTelemetry(false, false, false), new MountTelemetry(0),
        "Waiting for Guild Wars 2 telemetry.");

    private bool? _lastConnected;
    private int? _lastMap;
    private string? _lastCharacter;

    public TelemetryEnvelope Latest => Volatile.Read(ref _latest);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var next = await source.ReadAsync(stoppingToken);
            Volatile.Write(ref _latest, next);
            ReportStateChange(next);
            await Task.Delay(TimeSpan.FromMilliseconds(40), stoppingToken);
        }
    }

    private void ReportStateChange(TelemetryEnvelope next)
    {
        if (_lastConnected != next.Connected)
        {
            logger.LogInformation(next.Connected ? "MumbleLink connected" : "GW2 disconnected");
            _lastConnected = next.Connected;
        }

        if (next.Map?.Id != _lastMap)
        {
            if (_lastMap is not null && next.Map is not null)
                logger.LogInformation("Map changed {PreviousMap} -> {CurrentMap}", _lastMap, next.Map.Id);
            else if (next.Map is not null)
                logger.LogInformation("Map ID: {MapId}", next.Map.Id);
            _lastMap = next.Map?.Id;
        }

        var characterName = next.Character?.Name;
        if (!string.IsNullOrWhiteSpace(characterName) && characterName != _lastCharacter)
        {
            logger.LogInformation("Character: {Character}", characterName);
            _lastCharacter = characterName;
        }
    }
}
