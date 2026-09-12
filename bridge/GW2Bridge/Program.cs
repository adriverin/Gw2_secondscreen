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
var pairingToken = Base64Url(RandomNumberGenerator.GetBytes(32));
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

app.MapGet("/health", () => Results.Ok(new { status = "ok", protocolVersion = 1 }));
app.Map("/telemetry", async context =>
{
    var suppliedToken = context.Request.Query["token"].ToString();
    if (string.IsNullOrEmpty(suppliedToken) ||
        !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(suppliedToken), Encoding.UTF8.GetBytes(pairingToken)))
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
            await Task.Delay(TimeSpan.FromMilliseconds(67), context.RequestAborted);
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
var payload = JsonSerializer.Serialize(new { version = 1, host, port = options.Port, token = pairingToken }, BridgeJson.Options);
Console.WriteLine("GW2 Companion Bridge");
Console.WriteLine(options.Simulate ? "SIMULATION MODE" : "MumbleLink mode");
if (!options.Simulate)
    Console.WriteLine($"MumbleLink mapping: {options.MumbleName}");
Console.WriteLine($"Listening: {host}:{options.Port}");
Console.WriteLine("Pairing payload (scan with the iPhone app or enter manually):");
Console.WriteLine(payload);
using (var qrData = QRCodeGenerator.GenerateQrCode(payload, QRCodeGenerator.ECCLevel.Q))
using (var qrCode = new AsciiQRCode(qrData))
{
    Console.WriteLine(qrCode.GetGraphic(1, "██", "  "));
}
Console.WriteLine("The pairing token is intentionally shown only for local pairing and is never logged again.");

await app.RunAsync();

static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

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

public sealed record BridgeOptions(int Port, bool Simulate, string MumbleName)
{
    public static BridgeOptions Parse(string[] args)
    {
        var simulate = args.Contains("--simulate", StringComparer.OrdinalIgnoreCase);
        var port = 38291;
        var portIndex = Array.IndexOf(args, "--port");
        if (portIndex >= 0 && portIndex + 1 < args.Length && int.TryParse(args[portIndex + 1], out var parsed) && parsed is > 0 and <= 65535)
            port = parsed;
        var mumbleName = "MumbleLink";
        var mumbleIndex = Array.IndexOf(args, "--mumble-name");
        if (mumbleIndex >= 0 && mumbleIndex + 1 < args.Length && !string.IsNullOrWhiteSpace(args[mumbleIndex + 1]))
            mumbleName = args[mumbleIndex + 1];
        return new BridgeOptions(port, simulate, mumbleName);
    }
}

public static class BridgeJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };
}
