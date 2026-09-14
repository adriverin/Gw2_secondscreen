using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using GW2Bridge;
using QRCoder;

var options = BridgeOptions.Parse(args);
if (options.ValidateMumble)
{
    await RunMumbleValidationAsync(options.MumbleName);
    return;
}
string pairingToken;
var pairingStore = PairingTokenStore.CreateDefault();
try
{
    pairingToken = pairingStore.LoadOrCreate(options.ResetPairing);
}
catch (InvalidOperationException error)
{
    Console.Error.WriteLine($"PAIRING STORAGE ERROR: {error.Message}");
    Console.Error.WriteLine("Fix access to the folder above or run once with --reset-pairing.");
    return;
}
var bridgeId = BridgeIdentityStore.CreateDefault().LoadOrCreate();
using ITelemetrySource source = options.Simulate
    ? new SimulatedTelemetrySource()
    : new MumbleLinkTelemetrySource(options.MumbleName);

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(console =>
{
    console.SingleLine = true;
    console.TimestampFormat = "HH:mm:ss ";
});
// Hosting.Diagnostics includes the complete query string, which contains the pairing token.
builder.Logging.AddFilter("Microsoft.AspNetCore.Hosting.Diagnostics", LogLevel.Warning);
builder.Logging.AddFilter("Microsoft.AspNetCore.Routing", LogLevel.Warning);
builder.WebHost.ConfigureKestrel(server => server.ListenAnyIP(options.Port));
builder.Services.AddSingleton(source);
builder.Services.AddSingleton<TelemetryHub>();
builder.Services.AddHostedService(services => services.GetRequiredService<TelemetryHub>());

var app = builder.Build();
var telemetryHub = app.Services.GetRequiredService<TelemetryHub>();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(20) });

app.MapGet("/health", () => Results.Ok(new {
    status = "ok", protocolVersion = 1, bridgeVersion = BridgeVersion(), bridgeId
}));
app.MapGet("/pairing/validate", (HttpContext context) =>
{
    var authorization = context.Request.Headers.Authorization.ToString();
    var suppliedToken = authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
        ? authorization[7..]
        : string.Empty;
    return IsValidToken(suppliedToken, pairingToken)
        ? Results.Ok(new { protocolVersion = 1, bridgeVersion = BridgeVersion(), bridgeId })
        : Results.Unauthorized();
});
app.Map("/telemetry", async context =>
{
    var suppliedToken = context.Request.Query["token"].ToString();
    if (!IsValidToken(suppliedToken, pairingToken))
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        return;
    }

    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    app.Logger.LogInformation("iPhone connected");
    try
    {
        while (!context.RequestAborted.IsCancellationRequested && socket.State == WebSocketState.Open)
        {
            var telemetry = telemetryHub.Latest;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(telemetry, BridgeJson.Options);
            await socket.SendAsync(bytes, WebSocketMessageType.Text, true, context.RequestAborted);
            await Task.Delay(TimeSpan.FromMilliseconds(50), context.RequestAborted);
        }
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
    catch (WebSocketException) { }
    finally
    {
        app.Logger.LogInformation("iPhone disconnected");
    }
});

var host = GetLanAddress();
PrintPairing(host, options.Port, pairingToken, bridgeId, options);
var runTask = app.RunAsync();
if (!Console.IsInputRedirected)
{
    while (!runTask.IsCompleted)
    {
        if (!Console.KeyAvailable)
        {
            await Task.Delay(100);
            continue;
        }
        switch (Console.ReadKey(intercept: true).Key)
        {
            case ConsoleKey.R:
                pairingToken = pairingStore.LoadOrCreate(true);
                Console.WriteLine();
                Console.WriteLine("Pairing code regenerated. Previously paired devices must scan again.");
                PrintPairing(host, options.Port, pairingToken, bridgeId, options);
                break;
            case ConsoleKey.D:
                PrintDiagnostics(telemetryHub.Latest);
                break;
            case ConsoleKey.Q:
                app.Lifetime.StopApplication();
                break;
        }
    }
}
await runTask;

static void PrintPairing(string host, int port, string token, string bridgeId, BridgeOptions options)
{
    var payload = JsonSerializer.Serialize(new { version = 1, host, port, token, bridgeId }, BridgeJson.Options);
    Console.WriteLine("GW2 Companion Bridge");
    Console.WriteLine();
    Console.WriteLine("Status:");
    Console.WriteLine(options.Simulate ? "Simulating Guild Wars 2 telemetry" : "Waiting for Guild Wars 2");
    Console.WriteLine();
    Console.WriteLine("Network:");
    Console.WriteLine($"{host}:{port}");
    Console.WriteLine($"Bridge ID: {bridgeId[..8].ToUpperInvariant()}…");
    Console.WriteLine();
    Console.WriteLine("Pair your phone:");
    Console.WriteLine(payload);
    using var qrData = QRCodeGenerator.GenerateQrCode(payload, QRCodeGenerator.ECCLevel.Q);
    using var qrCode = new AsciiQRCode(qrData);
    Console.WriteLine(qrCode.GetGraphic(1, "██", "  "));
    Console.WriteLine("Allow GW2 Companion Bridge on Private networks in Windows Firewall.");
    Console.WriteLine("The API key is never sent to this bridge. Pairing is reused after restarts.");
    Console.WriteLine("Press R to regenerate pairing code   Press D for diagnostics   Press Q to quit");
}

static void PrintDiagnostics(TelemetryEnvelope value)
{
    Console.WriteLine();
    Console.WriteLine("Diagnostics:");
    Console.WriteLine($"Guild Wars 2: {(value.Connected ? "connected" : "not providing telemetry")}");
    Console.WriteLine($"Telemetry: {(value.PositionAvailable ? "live" : value.StatusMessage ?? "unavailable")}");
    Console.WriteLine($"Character: {(string.IsNullOrWhiteSpace(value.Character?.Name) ? "unavailable" : value.Character.Name)}");
    Console.WriteLine($"Map ID: {value.Map?.Id.ToString() ?? "unavailable"}");
    Console.WriteLine($"Tick: {value.UiTick}   Mount: {value.Mount.Index}   Combat: {value.Ui.InCombat}");
}

static string BridgeVersion() => typeof(Program).Assembly.GetName().Version?.ToString() ?? "unknown";

static async Task RunMumbleValidationAsync(string mappingName)
{
    if (!OperatingSystem.IsWindows())
    {
        Console.Error.WriteLine("--validate-mumble requires Windows and a running Guild Wars 2 client.");
        return;
    }
    Console.WriteLine("GW2 Companion Bridge — MumbleLink validation (Ctrl+C to stop)");
    using var reader = new MumbleLinkValidationReader(mappingName);
    while (true)
    {
        try
        {
            var value = reader.Read();
            Console.WriteLine();
            Console.WriteLine($"{DateTimeOffset.Now:T}");
            if (value?.Context is null)
            {
                Console.WriteLine("MumbleLink data appears invalid or Guild Wars 2 is not in the world.");
            }
            else
            {
                var context = value.Context;
                Console.WriteLine($"uiVersion {value.UiVersion}   uiTick {value.UiTick}");
                Console.WriteLine($"Character {value.Identity?.Name ?? "(unavailable)"}   Profession {value.Identity?.Profession?.ToString() ?? "?"}   Map ID {context.MapId}");
                Console.WriteLine($"playerX {context.PlayerX:F3}   playerY {context.PlayerY:F3}");
                Console.WriteLine($"avatar XYZ [{string.Join(", ", value.AvatarPosition.Select(number => number.ToString("F3")))}]");
                Console.WriteLine($"avatar front [{string.Join(", ", value.AvatarFront.Select(number => number.ToString("F3")))}]");
                Console.WriteLine($"camera front [{string.Join(", ", value.CameraFront.Select(number => number.ToString("F3")))}]");
                Console.WriteLine($"uiState 0x{context.UiState:X}   mountIndex {context.MountIndex}");
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Console.WriteLine($"MumbleLink unavailable: {error.Message}");
        }
        await Task.Delay(TimeSpan.FromSeconds(1));
    }
}

static bool IsValidToken(string supplied, string expected)
{
    var suppliedBytes = Encoding.UTF8.GetBytes(supplied);
    var expectedBytes = Encoding.UTF8.GetBytes(expected);
    return suppliedBytes.Length == expectedBytes.Length &&
           CryptographicOperations.FixedTimeEquals(suppliedBytes, expectedBytes);
}

static string GetLanAddress()
{
    foreach (var network in NetworkInterface.GetAllNetworkInterfaces())
    {
        if (network.OperationalStatus != OperationalStatus.Up || network.NetworkInterfaceType == NetworkInterfaceType.Loopback)
            continue;
        foreach (var address in network.GetIPProperties().UnicastAddresses)
        {
            if (address.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address.Address))
                return address.Address.ToString();
        }
    }
    return "127.0.0.1";
}

public sealed record BridgeOptions(int Port, bool Simulate, string MumbleName, bool ResetPairing, bool ValidateMumble)
{
    public static BridgeOptions Parse(string[] args)
    {
        var simulate = args.Contains("--simulate", StringComparer.OrdinalIgnoreCase);
        var resetPairing = args.Contains("--reset-pairing", StringComparer.OrdinalIgnoreCase);
        var validateMumble = args.Contains("--validate-mumble", StringComparer.OrdinalIgnoreCase);
        var port = 38291;
        var portIndex = Array.IndexOf(args, "--port");
        if (portIndex >= 0 && portIndex + 1 < args.Length && int.TryParse(args[portIndex + 1], out var parsed) && parsed is > 0 and <= 65535)
            port = parsed;
        var mumbleName = "MumbleLink";
        var mumbleIndex = Array.IndexOf(args, "--mumble-name");
        if (mumbleIndex >= 0 && mumbleIndex + 1 < args.Length && !string.IsNullOrWhiteSpace(args[mumbleIndex + 1]))
            mumbleName = args[mumbleIndex + 1];
        return new BridgeOptions(port, simulate, mumbleName, resetPairing, validateMumble);
    }
}

public static class BridgeJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };
}
