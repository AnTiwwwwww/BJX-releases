// 在独立的 .NET Framework 辅助程序中检查环境，缺少 pwsh 时也能显示指引。
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32;

internal static class PowerShellRuntime
{
    internal const string InstallUrl = "https://learn.microsoft.com/zh-cn/powershell/scripting/install/install-powershell-on-windows";

    internal static string Require7()
    {
        string executable = Find7(Environment.GetEnvironmentVariable("PATH"),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles));
        if (executable != null) return executable;

        string guidance = InstallationGuide(HasWindows51());
        // 只打开说明页；安装由用户自行执行，默认按钮为「否」。
        int answer = MessageBox(IntPtr.Zero, guidance, "BJX 需要 PowerShell 7",
            0x00000004 | 0x00000030 | 0x00000100 | 0x00010000 | 0x00040000);
        if (answer == 6)
        {
            try { Process.Start(new ProcessStartInfo(InstallUrl) { UseShellExecute = true }); }
            catch { /* 弹窗中已保留完整安装地址和命令。 */ }
        }
        return null;
    }

    internal static string Find7(string searchPath, string programFiles)
    {
        foreach (string entry in (searchPath ?? "").Split(';'))
        {
            string directory = entry.Trim().Trim('"');
            if (directory.Length == 0) continue;
            try
            {
                string candidate = Path.Combine(directory, "pwsh.exe");
                if (IsPowerShell7(candidate)) return Path.GetFullPath(candidate);
            }
            catch (ArgumentException) { }
        }
        // 刚安装但 BJX 的 PATH 尚未刷新时，也能找到标准安装位置。
        if (!string.IsNullOrEmpty(programFiles))
        {
            string candidate = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
            if (IsPowerShell7(candidate)) return Path.GetFullPath(candidate);
        }
        return null;
    }

    private static bool IsPowerShell7(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            FileVersionInfo info = FileVersionInfo.GetVersionInfo(path);
            return string.Equals(info.ProductName, "PowerShell", StringComparison.OrdinalIgnoreCase)
                && info.ProductMajorPart >= 7;
        }
        catch { return false; }
    }

    internal static bool HasWindows51()
    {
        try
        {
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine"))
            {
                string version = key == null ? "" : Convert.ToString(key.GetValue("PowerShellVersion"));
                return version.StartsWith("5.1", StringComparison.Ordinal);
            }
        }
        catch { return false; }
    }

    internal static string InstallationGuide(bool hasWindows51)
    {
        string detected = hasWindows51
            ? "检测到 Windows PowerShell 5.1，但未找到可用的 PowerShell 7。"
            : "未找到可用的 PowerShell 7（pwsh.exe）。";
        return detected + "\n\nBJX 本次任务不会继续。PowerShell 7 可与 5.1 并存，不需要卸载系统自带版本。\n\n"
            + "安装方法：\n1. 打开 Windows PowerShell，运行以下命令：\n"
            + "winget install --id Microsoft.PowerShell --exact --source winget\n"
            + "2. 如果没有 winget，按微软说明下载 Windows x64 安装包。\n"
            + "3. 安装完成后，关闭并重新打开 BJX，再开始任务。\n\n"
            + "若已经安装 7，请将 pwsh.exe 所在目录加入 PATH 后重新打开 BJX。\n\n"
            + InstallUrl + "\n\n点击「是」打开微软安装说明，点击「否」关闭提示。";
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    private static extern int MessageBox(IntPtr owner, string text, string caption, uint type);
}
