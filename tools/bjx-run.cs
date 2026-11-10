// 无窗口启动 pwsh。MXU 直接运行控制台程序会弹出命令行，这个程序本身没有控制台。
using System;
using System.Diagnostics;
using System.Text;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args == null || args.Length == 0)
        {
            return 0;
        }

        string executable = PowerShellRuntime.Require7();
        if (executable == null) return 2;
        var start = new ProcessStartInfo();
        start.FileName = executable;
        start.Arguments = JoinArgs(args);
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.WindowStyle = ProcessWindowStyle.Hidden;

        try
        {
            var process = Process.Start(start);
            if (process == null)
            {
                return 1;
            }
            process.WaitForExit();
            var code = process.ExitCode;
            process.Dispose();
            return code;
        }
        catch
        {
            return 1;
        }
    }

    private static string JoinArgs(string[] args)
    {
        var builder = new StringBuilder();
        for (var i = 0; i < args.Length; i++)
        {
            if (i > 0)
            {
                builder.Append(' ');
            }
            builder.Append(Quote(args[i]));
        }
        return builder.ToString();
    }

    private static string Quote(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "\"\"";
        }
        if (value.IndexOf(' ') < 0 && value.IndexOf('\t') < 0 && value.IndexOf('"') < 0)
        {
            return value;
        }

        var builder = new StringBuilder();
        builder.Append('"');
        var slashes = 0;
        for (var i = 0; i < value.Length; i++)
        {
            var ch = value[i];
            if (ch == '\\')
            {
                slashes++;
                continue;
            }
            if (ch == '"')
            {
                builder.Append('\\', slashes * 2 + 1);
                builder.Append('"');
                slashes = 0;
                continue;
            }
            if (slashes > 0)
            {
                builder.Append('\\', slashes);
                slashes = 0;
            }
            builder.Append(ch);
        }
        if (slashes > 0)
        {
            builder.Append('\\', slashes * 2);
        }
        builder.Append('"');
        return builder.ToString();
    }
}
