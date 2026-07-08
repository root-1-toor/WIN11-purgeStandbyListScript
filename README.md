# WIN11-purgeStandbyListScript

Give me my RAM back 🙂

Purges the Windows standby memory list (cached file pages) — same as RAMMap's "Empty Standby List," but pure PowerShell with no external tools. Add it to Task Scheduler set to run once an hour for constant RAM bandwidth.

## Setup (Task Scheduler)

1. Open **Task Scheduler** → **Create Task**, give it a name
2. Under **Actions** → **New**, set:

   | Field | Value |
   |---|---|
   | Program/script | `powershell.exe` |
   | Add arguments | `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\to\script.ps1"` |
   | Start in | *(leave empty)* |

3. On the **General** tab:
   - ✅ Check **"Run with highest privileges"** — without it, the script gets a non-elevated token and the purge fails with `0xC0000061` (`STATUS_PRIVILEGE_NOT_HELD`)
   - *(Optional)* Switch the account to `SYSTEM` via **"Change User or Group..."** → type `SYSTEM` — lets the task run silently without you being logged in, and guarantees the privilege is there
4. Under **Triggers**, add a schedule (e.g., repeat every 1 hour)

## How it works

Admin tokens hold the privilege `SeProfileSingleProcessPrivilege`, but it starts out **disabled** — Windows makes processes explicitly opt in to sensitive privileges. So the script does the classic three-step dance:

1. `OpenProcessToken` — gets a handle to the current process's security token
2. `LookupPrivilegeValue` — translates the privilege's name into its LUID
3. `AdjustTokenPrivileges` — flips it on

The check for error `1300` (`ERROR_NOT_ALL_ASSIGNED`) is there because `AdjustTokenPrivileges` has an infamous quirk: it returns success even when it enabled nothing, and only the last-error code tells the truth.

With the privilege enabled, the script calls `NtSetSystemInformation` with the `MemoryPurgeStandbyList` command, and the kernel moves every standby page to the free list.

## What the standby list actually is

The standby list is file data Windows has already read and is keeping around in otherwise-idle RAM, in case something asks for it again. Those pages are *already* counted as available — any app that needs memory gets a standby page instantly repurposed.

That's why **"Available" barely moves when you purge**: you're not freeing memory apps couldn't get, you're just throwing away cache. Useful for cold-cache benchmarking or the old gaming stutter bug; mostly cosmetic otherwise.
