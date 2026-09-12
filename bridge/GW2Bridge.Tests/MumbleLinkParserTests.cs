using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using GW2Bridge;
using Xunit;

namespace GW2Bridge.Tests;

public sealed class MumbleLinkParserTests
{
    [Fact]
    public void ParsesExplicitOffsetsIdentityAndUiFlags()
    {
        var bytes = new byte[MumbleLinkLayout.TotalBytes];
        WriteUInt32(bytes, MumbleLinkLayout.UiTick, 182930);
        WriteVector(bytes, MumbleLinkLayout.AvatarPosition, 12.1f, 4.2f, -18.5f);
        WriteVector(bytes, MumbleLinkLayout.AvatarFront, .4f, 0, -.9f);
        WriteVector(bytes, MumbleLinkLayout.CameraFront, .1f, .2f, .8f);
        WriteUtf16(bytes, MumbleLinkLayout.Identity, "{\"name\":\"Example Character\",\"profession\":7,\"spec\":66,\"race\":2}");
        // GW2 advertises only the original 48-byte context even though it writes
        // extended fields such as playerX/playerY and mountIndex after that point.
        WriteUInt32(bytes, MumbleLinkLayout.ContextLength, 48);
        var context = MumbleLinkLayout.Context;
        WriteUInt32(bytes, context + MumbleLinkLayout.ContextOffset.MapId, 15);
        WriteUInt32(bytes, context + MumbleLinkLayout.ContextOffset.MapType, 5);
        WriteUInt32(bytes, context + MumbleLinkLayout.ContextOffset.UiState, (1u << 0) | (1u << 3) | (1u << 6));
        WriteSingle(bytes, context + MumbleLinkLayout.ContextOffset.PlayerX, 11000.2f);
        WriteSingle(bytes, context + MumbleLinkLayout.ContextOffset.PlayerY, 13200.7f);
        bytes[context + MumbleLinkLayout.ContextOffset.MountIndex] = 8;

        var success = new MumbleLinkParser().TryParse(bytes, out var result);

        Assert.True(success);
        Assert.NotNull(result);
        Assert.Equal(182930u, result.UiTick);
        Assert.Equal("Example Character", result.Identity?.Name);
        Assert.Equal(15u, result.Context?.MapId);
        Assert.Equal(11000.2f, result.Context?.PlayerX);
        Assert.Equal(13200.7f, result.Context?.PlayerY);
        Assert.Equal((byte)8, result.Context?.MountIndex);
        Assert.True(result.Context?.InCombat);
        Assert.True(result.Context?.IsMapOpen);
        Assert.True(result.Context?.GameHasFocus);
    }

    [Fact]
    public void MalformedIdentityAndShortContextAreSafe()
    {
        var bytes = new byte[MumbleLinkLayout.TotalBytes];
        WriteUtf16(bytes, MumbleLinkLayout.Identity, "{not json");
        WriteUInt32(bytes, MumbleLinkLayout.ContextLength, 40);

        Assert.True(new MumbleLinkParser().TryParse(bytes, out var result));
        Assert.Null(result!.Identity);
        Assert.Null(result.Context);
    }

    [Fact]
    public async Task SerializesProtocolWithCamelCaseFields()
    {
        using var source = new SimulatedTelemetrySource();
        var telemetry = await source.ReadAsync(CancellationToken.None);
        var json = JsonSerializer.Serialize(telemetry, BridgeJson.Options);

        Assert.Contains("\"protocolVersion\":1", json);
        Assert.Contains("\"positionAvailable\":true", json);
        Assert.Contains("\"continentX\":", json);
        Assert.Contains("\"inCombat\":false", json);
        Assert.DoesNotContain("Pairing", json);
    }

    private static void WriteUInt32(byte[] bytes, int offset, uint value) =>
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(offset, 4), value);

    private static void WriteSingle(byte[] bytes, int offset, float value) =>
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(offset, 4), BitConverter.SingleToInt32Bits(value));

    private static void WriteVector(byte[] bytes, int offset, float x, float y, float z)
    {
        WriteSingle(bytes, offset, x);
        WriteSingle(bytes, offset + 4, y);
        WriteSingle(bytes, offset + 8, z);
    }

    private static void WriteUtf16(byte[] bytes, int offset, string value) =>
        Encoding.Unicode.GetBytes(value).CopyTo(bytes, offset);
}

public sealed class TickStalenessDetectorTests
{
    [Fact]
    public void ReportsUnchangedTickAsStaleAfterThreshold()
    {
        var detector = new TickStalenessDetector(TimeSpan.FromSeconds(2));
        var start = DateTimeOffset.UnixEpoch;
        Assert.False(detector.IsStale(10, start));
        Assert.False(detector.IsStale(10, start.AddSeconds(1.9)));
        Assert.True(detector.IsStale(10, start.AddSeconds(2)));
        Assert.False(detector.IsStale(11, start.AddSeconds(3)));
    }
}
