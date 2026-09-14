using System.Security.Cryptography;
using System.Text;

namespace GW2Bridge;

public interface IUserDataProtector
{
    byte[] Protect(byte[] data);
    byte[] Unprotect(byte[] data);
}

public sealed class CurrentUserDataProtector : IUserDataProtector
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("GW2CompanionBridge.PairingToken.v1");

    public byte[] Protect(byte[] data) => OperatingSystem.IsWindows()
        ? ProtectedData.Protect(data, Entropy, DataProtectionScope.CurrentUser)
        : data;

    public byte[] Unprotect(byte[] data) => OperatingSystem.IsWindows()
        ? ProtectedData.Unprotect(data, Entropy, DataProtectionScope.CurrentUser)
        : data;
}

public sealed class PairingTokenStore(string path, IUserDataProtector protector)
{
    public static PairingTokenStore CreateDefault()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var path = Path.Combine(root, "GW2CompanionBridge", "pairing-token.bin");
        return new PairingTokenStore(path, new CurrentUserDataProtector());
    }

    public string LoadOrCreate(bool reset)
    {
        try
        {
            if (!reset && File.Exists(path))
            {
                var saved = Encoding.UTF8.GetString(protector.Unprotect(File.ReadAllBytes(path)));
                if (IsValid(saved))
                    return saved;
                throw new InvalidDataException("The saved pairing token is invalid.");
            }

            var token = Base64Url(RandomNumberGenerator.GetBytes(32));
            var protectedToken = protector.Protect(Encoding.UTF8.GetBytes(token));
            var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException("Pairing storage has no directory.");
            Directory.CreateDirectory(directory);
            var temporaryPath = Path.Combine(directory, $"pairing-token-{Guid.NewGuid():N}.tmp");
            try
            {
                File.WriteAllBytes(temporaryPath, protectedToken);
                File.Move(temporaryPath, path, true);
            }
            finally
            {
                if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
            }
            return token;
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or CryptographicException)
        {
            throw new InvalidOperationException(
                $"Could not read or securely save the pairing token at '{path}'.", error);
        }
    }

    private static bool IsValid(string value) => value.Length >= 32 && value.All(character =>
        char.IsAsciiLetterOrDigit(character) || character is '-' or '_');

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}

/// <summary>A random installation identity. It is not derived from hardware and is not secret.</summary>
public sealed class BridgeIdentityStore(string path)
{
    public static BridgeIdentityStore CreateDefault()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return new BridgeIdentityStore(Path.Combine(root, "GW2CompanionBridge", "bridge-id.txt"));
    }

    public string LoadOrCreate()
    {
        if (File.Exists(path) && Guid.TryParse(File.ReadAllText(path).Trim(), out var saved))
            return saved.ToString("N");

        var value = Guid.NewGuid().ToString("N");
        var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException("Bridge identity storage has no directory.");
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $"bridge-id-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(temporaryPath, value, Encoding.UTF8);
            File.Move(temporaryPath, path, true);
        }
        finally
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
        }
        return value;
    }
}
