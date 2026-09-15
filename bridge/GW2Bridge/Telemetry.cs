using System.Text.Json.Serialization;

namespace GW2Bridge;

public sealed record TelemetryEnvelope(
    int ProtocolVersion,
    long TimestampUnixMs,
    bool Connected,
    uint UiTick,
    bool PositionAvailable,
    CharacterTelemetry? Character,
    MapTelemetry? Map,
    PlayerTelemetry? Player,
    CameraTelemetry? Camera,
    UiTelemetry Ui,
    MountTelemetry Mount,
    string? StatusMessage = null,
    uint? UiVersion = null);

public sealed record CharacterTelemetry(
    string Name,
    int? Profession,
    int? Specialization,
    int? Race);

public sealed record MapTelemetry(int Id, uint Type, uint ShardId, uint InstanceId);

public sealed record PlayerTelemetry(
    float ContinentX,
    float ContinentY,
    float AvatarX,
    float AvatarY,
    float AvatarZ,
    float HeadingX,
    float HeadingY);

public sealed record CameraTelemetry(float FrontX, float FrontY, float FrontZ);
public sealed record UiTelemetry(bool InCombat, bool MapOpen, bool GameHasFocus);
public sealed record MountTelemetry(byte Index);

public sealed record MumbleSnapshot(
    uint UiVersion,
    uint UiTick,
    float[] AvatarPosition,
    float[] AvatarFront,
    float[] CameraPosition,
    float[] CameraFront,
    string IdentityJson,
    MumbleIdentity? Identity,
    MumbleContext? Context);

public sealed record MumbleIdentity(
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("profession")] int? Profession,
    [property: JsonPropertyName("spec")] int? Specialization,
    [property: JsonPropertyName("race")] int? Race,
    [property: JsonPropertyName("map_id")] int? MapId,
    [property: JsonPropertyName("world_id")] int? WorldId,
    [property: JsonPropertyName("team_color_id")] int? TeamColorId,
    [property: JsonPropertyName("commander")] bool? Commander,
    [property: JsonPropertyName("fov")] float? FieldOfView,
    [property: JsonPropertyName("uisz")] int? UiSize);

public sealed record MumbleContext(
    uint MapId,
    uint MapType,
    uint ShardId,
    uint Instance,
    uint BuildId,
    uint UiState,
    ushort CompassWidth,
    ushort CompassHeight,
    float CompassRotation,
    float PlayerX,
    float PlayerY,
    float MapCenterX,
    float MapCenterY,
    float MapScale,
    uint ProcessId,
    byte MountIndex)
{
    public bool IsMapOpen => (UiState & (1u << 0)) != 0;
    public bool GameHasFocus => (UiState & (1u << 3)) != 0;
    public bool IsCompetitive => (UiState & (1u << 4)) != 0;
    public bool InCombat => (UiState & (1u << 6)) != 0;
}
