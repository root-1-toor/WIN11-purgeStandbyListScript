<#
.SYNOPSIS
    Purges the Windows standby memory list (cached file pages).

.DESCRIPTION
    Calls NtSetSystemInformation with SystemMemoryListInformation to flush
    the standby list, same as RAMMap's "Empty Standby List" option.
    Requires Administrator + SeProfileSingleProcessPrivilege.

.NOTES
    Run from an elevated PowerShell session:
        .\Clear-StandbyList.ps1
#>

#Requires -RunAsAdministrator

$signature = @'
using System;
using System.Runtime.InteropServices;

public static class StandbyPurgeV2
{
    [DllImport("ntdll.dll", SetLastError = true)]
    private static extern int NtSetSystemInformation(int infoClass, IntPtr info, int length);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string system, string name, out long luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll,
        ref TOKEN_PRIVILEGES newState, int bufferLength, IntPtr previousState, IntPtr returnLength);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct TOKEN_PRIVILEGES
    {
        public int Count;
        public long Luid;
        public int Attr;
    }

    private const int SystemMemoryListInformation = 80;
    private const int MemoryPurgeStandbyList = 4;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x20;
    private const uint TOKEN_QUERY = 0x8;
    private const int SE_PRIVILEGE_ENABLED = 0x2;

    private static void EnablePrivilege(string privilege)
    {
        IntPtr token;
        if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle,
            TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
            throw new InvalidOperationException("OpenProcessToken failed: " + Marshal.GetLastWin32Error());

        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.Count = 1;
        tp.Attr = SE_PRIVILEGE_ENABLED;
        if (!LookupPrivilegeValue(null, privilege, out tp.Luid))
            throw new InvalidOperationException("LookupPrivilegeValue failed: " + Marshal.GetLastWin32Error());

        if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
            throw new InvalidOperationException("AdjustTokenPrivileges failed: " + Marshal.GetLastWin32Error());

        // AdjustTokenPrivileges returns TRUE even if the privilege wasn't assigned
        if (Marshal.GetLastWin32Error() == 1300) // ERROR_NOT_ALL_ASSIGNED
            throw new InvalidOperationException("Privilege not held by this token: " + privilege);
    }

    public static void Purge()
    {
        EnablePrivilege("SeProfileSingleProcessPrivilege");

        int command = MemoryPurgeStandbyList;
        IntPtr ptr = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            Marshal.WriteInt32(ptr, command);
            int status = NtSetSystemInformation(SystemMemoryListInformation, ptr, sizeof(int));
            if (status != 0)
                throw new InvalidOperationException("NtSetSystemInformation failed, NTSTATUS: 0x" + status.ToString("X8"));
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
    }
}
'@

Add-Type -TypeDefinition $signature -Language CSharp

function Get-MemSnapshot {
    $counters = @(
        '\Memory\Standby Cache Normal Priority Bytes',
        '\Memory\Standby Cache Reserve Bytes',
        '\Memory\Standby Cache Core Bytes',
        '\Memory\Modified Page List Bytes',
        '\Memory\Free & Zero Page List Bytes',
        '\Memory\Available MBytes'
    )
    $s = (Get-Counter $counters -ErrorAction SilentlyContinue).CounterSamples
    $get = { param($name) [math]::Round((($s | Where-Object Path -like "*$name*").CookedValue) / 1MB, 0) }

    $standby  = (& $get 'standby cache normal') + (& $get 'standby cache reserve') + (& $get 'standby cache core')
    $modified = & $get 'modified page list'
    $free     = & $get 'free & zero'
    $avail    = [math]::Round(($s | Where-Object Path -like '*available mbytes*').CookedValue, 0)

    [PSCustomObject]@{
        StandbyMB   = $standby
        ModifiedMB  = $modified
        CachedMB    = $standby + $modified   # what Task Manager calls "Cached"
        FreeMB      = $free
        AvailableMB = $avail
    }
}

function Show-MemSnapshot {
    param($snap, $label)
    Write-Host ""
    Write-Host "=== $label ===" -ForegroundColor Cyan
    Write-Host ("  Cached (standby + modified): {0,8:N0} MB" -f $snap.CachedMB)
    Write-Host ("    Standby list:              {0,8:N0} MB" -f $snap.StandbyMB)
    Write-Host ("    Modified list:             {0,8:N0} MB" -f $snap.ModifiedMB)
    Write-Host ("  Free memory:                 {0,8:N0} MB" -f $snap.FreeMB)
    Write-Host ("  Available memory:            {0,8:N0} MB" -f $snap.AvailableMB)
}

$before = Get-MemSnapshot
Show-MemSnapshot $before "Before purge"

[StandbyPurgeV2]::Purge()

Start-Sleep -Milliseconds 500
$after = Get-MemSnapshot
Show-MemSnapshot $after "After purge"

Write-Host ""
Write-Host ("Standby purged: {0:N0} MB  |  Free memory gained: {1:N0} MB" -f `
    ($before.StandbyMB - $after.StandbyMB), ($after.FreeMB - $before.FreeMB)) -ForegroundColor Green
