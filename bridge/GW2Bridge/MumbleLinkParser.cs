using System.Buffers.Binary;
using System.Text;
using System.Text.Json;

namespace GW2Bridge;

public static class MumbleLinkLayout
{
    public const int UiVersion = 0;
    public const int UiTick = 4;
    public const int AvatarPosition = 8;
    public const int AvatarFront = 20;
    public const int AvatarTop = 32;
    public const int Name = 44;
    public const int CameraPosition = 556;
    public const int CameraFront = 568;
    public const int CameraTop = 580;
    public const int Identity = 592;
    public const int ContextLength = 1104;
    public const int Context = 1108;
    public const int Description = 1364;
    public const int TotalBytes = 5460;

    public static class ContextOffset
    {
        // GW2 leaves context_len at the original 48-byte Mumble value while also writing
        // its extended fields into the remainder of the fixed 256-byte context buffer.
        public const int MinimumAdvertisedBytes = 48;
        public const int MapId = 28;
        public const int MapType = 32;
        public const int ShardId = 36;
        public const int Instance = 40;
        public const int BuildId = 44;
        public const int UiState = 48;
        public const int CompassWidth = 52;
        public const int CompassHeight = 54;
        public const int CompassRotation = 56;
        public const int PlayerX = 60;
        public const int PlayerY = 64;
        public const int MapCenterX = 68;
        public const int MapCenterY = 72;
        public const int MapScale = 76;
        public const int ProcessId = 80;
        public const int MountIndex = 84;
        public const int RequiredBytes = 85;
    }
}

public sealed class MumbleLinkParser
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public bool TryParse(ReadOnlySpan<byte> bytes, out MumbleSnapshot? snapshot)
    {
        snapshot = null;
        if (bytes.Length < MumbleLinkLayout.Context)
        {
            return false;
        }

        var uiVersion = UInt32(bytes, MumbleLinkLayout.UiVersion);
        if (uiVersion > 100 || !VectorsAreFinite(bytes))
            return false;

        var tick = UInt32(bytes, MumbleLinkLayout.UiTick);
        var avatarPosition = Vector3(bytes, MumbleLinkLayout.AvatarPosition);
        var avatarFront = Vector3(bytes, MumbleLinkLayout.AvatarFront);
        var cameraPosition = Vector3(bytes, MumbleLinkLayout.CameraPosition);
        var cameraFront = Vector3(bytes, MumbleLinkLayout.CameraFront);
        var identityJson = Utf16String(bytes, MumbleLinkLayout.Identity, 256);
        MumbleIdentity? identity = null;
        if (!string.IsNullOrWhiteSpace(identityJson))
        {
            try
            {
                identity = JsonSerializer.Deserialize<MumbleIdentity>(identityJson, JsonOptions);
            }
            catch (JsonException)
            {
                // Identity is supplied by the game and can be empty/partially written.
            }
        }

        var advertisedLength = UInt32(bytes, MumbleLinkLayout.ContextLength);
        if (advertisedLength > 256) return false;
        var allocatedLength = Math.Min(256, bytes.Length - MumbleLinkLayout.Context);
        MumbleContext? context = advertisedLength >= MumbleLinkLayout.ContextOffset.MinimumAdvertisedBytes &&
                                 allocatedLength >= MumbleLinkLayout.ContextOffset.RequiredBytes
            ? ParseContext(bytes.Slice(MumbleLinkLayout.Context, allocatedLength))
            : null;
        if (context is not null && !ContextIsSane(context)) return false;

        snapshot = new MumbleSnapshot(
            uiVersion, tick, avatarPosition, avatarFront, cameraPosition, cameraFront,
            identityJson, identity, context);
        return true;
    }

    private static bool ContextIsSane(MumbleContext value) =>
        value.MapId <= 1_000_000 &&
        float.IsFinite(value.PlayerX) && float.IsFinite(value.PlayerY) &&
        float.IsFinite(value.MapCenterX) && float.IsFinite(value.MapCenterY) &&
        float.IsFinite(value.MapScale) && float.IsFinite(value.CompassRotation);

    private static bool VectorsAreFinite(ReadOnlySpan<byte> bytes)
    {
        foreach (var offset in new[] { MumbleLinkLayout.AvatarPosition, MumbleLinkLayout.AvatarFront,
                                      MumbleLinkLayout.CameraPosition, MumbleLinkLayout.CameraFront })
            for (var component = 0; component < 3; component++)
                if (!float.IsFinite(Single(bytes, offset + component * 4))) return false;
        return true;
    }

    private static MumbleContext ParseContext(ReadOnlySpan<byte> context) => new(
        UInt32(context, MumbleLinkLayout.ContextOffset.MapId),
        UInt32(context, MumbleLinkLayout.ContextOffset.MapType),
        UInt32(context, MumbleLinkLayout.ContextOffset.ShardId),
        UInt32(context, MumbleLinkLayout.ContextOffset.Instance),
        UInt32(context, MumbleLinkLayout.ContextOffset.BuildId),
        UInt32(context, MumbleLinkLayout.ContextOffset.UiState),
        UInt16(context, MumbleLinkLayout.ContextOffset.CompassWidth),
        UInt16(context, MumbleLinkLayout.ContextOffset.CompassHeight),
        Single(context, MumbleLinkLayout.ContextOffset.CompassRotation),
        Single(context, MumbleLinkLayout.ContextOffset.PlayerX),
        Single(context, MumbleLinkLayout.ContextOffset.PlayerY),
        Single(context, MumbleLinkLayout.ContextOffset.MapCenterX),
        Single(context, MumbleLinkLayout.ContextOffset.MapCenterY),
        Single(context, MumbleLinkLayout.ContextOffset.MapScale),
        UInt32(context, MumbleLinkLayout.ContextOffset.ProcessId),
        context[MumbleLinkLayout.ContextOffset.MountIndex]);

    private static float[] Vector3(ReadOnlySpan<byte> bytes, int offset) =>
        [Single(bytes, offset), Single(bytes, offset + 4), Single(bytes, offset + 8)];

    private static string Utf16String(ReadOnlySpan<byte> bytes, int offset, int characterCapacity)
    {
        var byteCount = Math.Min(characterCapacity * 2, Math.Max(0, bytes.Length - offset));
        var slice = bytes.Slice(offset, byteCount);
        var terminator = byteCount;
        for (var i = 0; i + 1 < slice.Length; i += 2)
        {
            if (slice[i] == 0 && slice[i + 1] == 0)
            {
                terminator = i;
                break;
            }
        }

        return Encoding.Unicode.GetString(slice[..terminator]);
    }

    private static ushort UInt16(ReadOnlySpan<byte> bytes, int offset) =>
        BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(offset, 2));

    private static uint UInt32(ReadOnlySpan<byte> bytes, int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(offset, 4));

    private static float Single(ReadOnlySpan<byte> bytes, int offset) =>
        BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(bytes.Slice(offset, 4)));
}
