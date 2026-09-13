using System.IO.MemoryMappedFiles;
using System.Runtime.Versioning;

namespace GW2Bridge;

public interface ITelemetrySource : IDisposable
{
    ValueTask<TelemetryEnvelope> ReadAsync(CancellationToken cancellationToken);
}

public sealed class TickStalenessDetector(TimeSpan staleAfter)
{
    private uint? _lastTick;
    private DateTimeOffset _lastChange;

    public bool IsStale(uint tick, DateTimeOffset now)
    {
        if (_lastTick != tick)
        {
            _lastTick = tick;
            _lastChange = now;
            return false;
        }

        return now - _lastChange >= staleAfter;
    }
}

public sealed class MumbleLinkTelemetrySource : ITelemetrySource
{
    private readonly string _mappingName;
    private readonly MumbleLinkParser _parser = new();
    // Brief frame/tick pauses occur during loading screens and when Windows throttles
    // the game in the background. Do not hide the last good position immediately.
    private readonly TickStalenessDetector _staleness = new(TimeSpan.FromSeconds(5));
    private MemoryMappedFile? _mapping;
    private MemoryMappedViewAccessor? _view;

    public MumbleLinkTelemetrySource(string mappingName = "MumbleLink")
    {
        _mappingName = mappingName;
    }

    public ValueTask<TelemetryEnvelope> ReadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!OperatingSystem.IsWindows())
        {
            return ValueTask.FromResult(Disconnected("MumbleLink is only available on Windows."));
        }

        try
        {
            EnsureMapping();
            var data = new byte[MumbleLinkLayout.TotalBytes];
            _view!.ReadArray(0, data, 0, data.Length);
            if (!_parser.TryParse(data, out var snapshot) || snapshot is null || snapshot.Context is null)
            {
                return ValueTask.FromResult(Disconnected("Waiting for Guild Wars 2 telemetry."));
            }

            var stale = snapshot.UiTick == 0 || _staleness.IsStale(snapshot.UiTick, DateTimeOffset.UtcNow);
            var envelope = ToEnvelope(snapshot, !stale);
            return ValueTask.FromResult(envelope);
        }
        catch (FileNotFoundException)
        {
            DisposeMapping();
            return ValueTask.FromResult(Disconnected("Guild Wars 2 is not running."));
        }
        catch (IOException)
        {
            DisposeMapping();
            return ValueTask.FromResult(Disconnected("MumbleLink became unavailable."));
        }
        catch (UnauthorizedAccessException)
        {
            DisposeMapping();
            return ValueTask.FromResult(Disconnected(
                "MumbleLink access was denied. Run Guild Wars 2 and the bridge at the same elevation level."));
        }
    }

    [SupportedOSPlatform("windows")]
    private void EnsureMapping()
    {
        if (_mapping is not null)
        {
            return;
        }

        // GW2 writes into a mapping owned by a MumbleLink consumer. Creating and retaining
        // the mapping lets the bridge work even when no other overlay has created it first.
        _mapping = MemoryMappedFile.CreateOrOpen(
            _mappingName,
            MumbleLinkLayout.TotalBytes,
            MemoryMappedFileAccess.ReadWrite);
        _view = _mapping.CreateViewAccessor(0, MumbleLinkLayout.TotalBytes, MemoryMappedFileAccess.Read);
    }

    private static TelemetryEnvelope ToEnvelope(MumbleSnapshot snapshot, bool positionAvailable)
    {
        var context = snapshot.Context!;
        var identity = snapshot.Identity;
        // GW2 avatar X/Z is projected to the horizontal heading plane.
        var headingX = snapshot.AvatarFront[0];
        var headingY = -snapshot.AvatarFront[2];
        return new TelemetryEnvelope(
            1,
            DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            true,
            snapshot.UiTick,
            positionAvailable && !context.IsCompetitive,
            new CharacterTelemetry(identity?.Name ?? string.Empty, identity?.Profession, identity?.Specialization, identity?.Race),
            new MapTelemetry((int)context.MapId, context.MapType, context.ShardId, context.Instance),
            new PlayerTelemetry(context.PlayerX, context.PlayerY,
                snapshot.AvatarPosition[0], snapshot.AvatarPosition[1], snapshot.AvatarPosition[2], headingX, headingY),
            new CameraTelemetry(snapshot.CameraFront[0], snapshot.CameraFront[1], snapshot.CameraFront[2]),
            new UiTelemetry(context.InCombat, context.IsMapOpen, context.GameHasFocus),
            new MountTelemetry(context.MountIndex),
            context.IsCompetitive ? "Position is unavailable in this competitive map." :
                positionAvailable ? null : "Telemetry is stale.");
    }

    private static TelemetryEnvelope Disconnected(string message) => new(
        1, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), false, 0, false,
        null, null, null, null, new UiTelemetry(false, false, false), new MountTelemetry(0), message);

    private void DisposeMapping()
    {
        _view?.Dispose();
        _mapping?.Dispose();
        _view = null;
        _mapping = null;
    }

    public void Dispose() => DisposeMapping();
}

public sealed class SimulatedTelemetrySource : ITelemetrySource
{
    private readonly DateTimeOffset _started = DateTimeOffset.UtcNow;
    private uint _tick;

    public ValueTask<TelemetryEnvelope> ReadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var seconds = (DateTimeOffset.UtcNow - _started).TotalSeconds;
        // The east point of this ellipse crosses Queensdale hero challenge 0-7.
        const double centerX = 44615.5;
        const double centerY = 29863.7;
        const double radiusX = 520;
        const double radiusY = 330;
        var angle = seconds * 0.14;
        var x = (float)(centerX + Math.Cos(angle) * radiusX);
        var y = (float)(centerY + Math.Sin(angle) * radiusY);
        var hx = (float)-Math.Sin(angle);
        var hy = (float)Math.Cos(angle);
        _tick++;

        return ValueTask.FromResult(new TelemetryEnvelope(
            1, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), true, _tick, true,
            new CharacterTelemetry("Test Mesmer", 8, 0, 0),
            new MapTelemetry(15, 5, 1, 1),
            new PlayerTelemetry(x, y, 0, 0, 0, hx, hy),
            new CameraTelemetry(hx, 0, -hy),
            new UiTelemetry(false, false, true),
            new MountTelemetry(0)));
    }

    public void Dispose() { }
}
