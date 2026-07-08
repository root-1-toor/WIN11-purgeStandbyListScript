# WIN11-purgeStandbyListScript
Give me my ram back

Admin tokens hold the privilege SeProfileSingleProcessPrivilege, but it starts out disabled — Windows makes processes explicitly opt in to sensitive privileges. So the method does the classic three-step dance: OpenProcessToken gets a handle to the current process's security token, LookupPrivilegeValue translates the privilege's name into its LUID, and AdjustTokenPrivileges flips it on. The check for error 1300 (ERROR_NOT_ALL_ASSIGNED) is there because AdjustTokenPrivileges has an infamous quirk: it returns success even when it enabled nothing, and only the last-error code tells the truth.

Purge — the actual work
With the privilege enabled, it allocates 4 bytes of unmanaged memory, writes the integer 4 into it (MemoryPurgeStandbyList — the command code meaning "drop the standby list"), and calls NtSetSystemInformation with information class 80 (SystemMemoryListInformation). The kernel then walks the standby list and moves every page to the free list. A nonzero NTSTATUS return means failure — that's where your 0xC0000061 (privilege not held) surfaced before the fix. The try/finally guarantees the unmanaged buffer is freed even if the call throws.


Get-MemSnapshot reads five performance counters — the three standby tiers (normal, reserve, core priority), the modified page list, and the free/zero page list — and packages them into an object. Standby + modified is exactly what Task Manager labels "Cached." Show-MemSnapshot just formats that nicely. The script snapshots, purges, sleeps half a second so the counters catch up, snapshots again, and prints the delta.

The standby list is file data Windows has already read and is keeping around in otherwise-idle RAM, in case something asks for it again. Those pages are already counted as available — any app that needs memory gets a standby page instantly repurposed. That's why "Available" barely moves when you purge: you're not freeing memory apps couldn't get, you're just throwing away cache. Useful for cold-cache benchmarking or the old gaming stutter bug; mostly cosmetic otherwise.
