using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class RoyaleClock
{
    private const string Server = "MaaAgentServer.dll";
    private const uint LibrarySearchDllLoadDir = 0x100;
    private const uint LibrarySearchDefaultDirs = 0x1000;
    private static readonly byte[] EndNode = Utf8("吃鸡到点结束");
    private static readonly ActionCallback SetDeadlineCallback = SetDeadline;
    private static readonly ActionCallback CheckDeadlineCallback = CheckDeadline;
    private static long activeTask;
    private static DateTime deadlineUtc;

    private static int Main(string[] args)
    {
        try
        {
            var utf8 = new UTF8Encoding(false);
            Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), utf8) { AutoFlush = true });
            Console.SetError(new StreamWriter(Console.OpenStandardError(), utf8) { AutoFlush = true });
            if (args.Length != 1) throw new ArgumentException("缺少 Maa Agent 连接标识");
            if (PowerShellRuntime.Require7() == null) return 2;
            string project = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
            string library = Path.Combine(project, "maafw", Server);
            // 从 MaaFramework 自己的目录解析 DLL 及其依赖。
            if (LoadLibraryEx(library, IntPtr.Zero, LibrarySearchDllLoadDir | LibrarySearchDefaultDirs) == IntPtr.Zero)
                throw new InvalidOperationException("无法加载 " + library);

            if (MaaAgentServerRegisterCustomAction("BJX_ROYALE_SET_DEADLINE", SetDeadlineCallback, IntPtr.Zero) == 0 ||
                MaaAgentServerRegisterCustomAction("BJX_ROYALE_CHECK_DEADLINE", CheckDeadlineCallback, IntPtr.Zero) == 0 ||
                MaaAgentServerStartUp(Utf8(args[0])) == 0)
                throw new InvalidOperationException("无法启动吃鸡计时 Agent");

            MaaAgentServerJoin();
            MaaAgentServerShutDown();
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("BJX 吃鸡计时 " + error.Message);
            return 1;
        }
    }

    internal static DateTime NextDeadline(DateTime localNow, TimeSpan time)
    {
        DateTime tomorrow = localNow.Date.AddDays(1);
        return tomorrow + time;
    }

    private static byte SetDeadline(IntPtr context, long taskId, IntPtr node, IntPtr action, IntPtr param,
        long recognitionId, IntPtr box, IntPtr userData)
    {
        string value = Marshal.PtrToStringAnsi(param) ?? "";
        TimeSpan time;
        if (!TimeSpan.TryParseExact(value.Trim('"'), @"hh\:mm", CultureInfo.InvariantCulture, out time))
        {
            Console.Error.WriteLine("BJX 吃鸡截止时间格式应为 HH:mm");
            return 0;
        }

        // MXU 为每个资源实例启动一个 Agent。同一任务的多局共用这个截止点。
        DateTime deadline = NextDeadline(DateTime.Now, time);
        deadlineUtc = deadline.ToUniversalTime();
        activeTask = taskId;
        Console.WriteLine("BJX 吃鸡截止时间 " + deadline.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture));
        return 1;
    }

    private static byte CheckDeadline(IntPtr context, long taskId, IntPtr node, IntPtr action, IntPtr param,
        long recognitionId, IntPtr box, IntPtr userData)
    {
        if (taskId != activeTask) return 0;

        string value = Marshal.PtrToStringAnsi(param);
        int waitMs = 0;
        if (value != null && value != "null" &&
            (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out waitMs) || waitMs < 0))
            return 0;

        if (waitMs > 0)
        {
            IntPtr tasker = MaaContextGetTasker(context);
            if (tasker == IntPtr.Zero) return 0;
            var elapsed = Stopwatch.StartNew();
            while (elapsed.ElapsedMilliseconds < waitMs && DateTime.UtcNow < deadlineUtc)
            {
                if (MaaTaskerStopping(tasker) != 0) return 0;
                long remaining = waitMs - elapsed.ElapsedMilliseconds;
                Thread.Sleep((int)Math.Max(1, Math.Min(250, remaining)));
            }
        }

        return DateTime.UtcNow >= deadlineUtc ? FinishTask(context, node) : (byte)1;
    }

    private static byte FinishTask(IntPtr context, IntPtr node)
    {
        IntPtr next = MaaStringListBufferCreate();
        IntPtr end = MaaStringBufferCreate();
        try
        {
            // 只走结束节点，跳过后续画面识别，MXU 仍可继续运行列表里的任务。
            if (MaaStringBufferSet(end, EndNode) == 0 || MaaStringListBufferAppend(next, end) == 0)
                return 0;
            return MaaContextOverrideNext(context, node, next);
        }
        finally
        {
            MaaStringBufferDestroy(end);
            MaaStringListBufferDestroy(next);
        }
    }

    private static byte[] Utf8(string value)
    {
        return Encoding.UTF8.GetBytes(value + "\0");
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate byte ActionCallback(IntPtr context, long taskId, IntPtr node, IntPtr action, IntPtr param,
        long recognitionId, IntPtr box, IntPtr userData);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern byte MaaAgentServerRegisterCustomAction(string name, ActionCallback action, IntPtr userData);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern byte MaaAgentServerStartUp(byte[] identifier);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern void MaaAgentServerJoin();

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern void MaaAgentServerShutDown();

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr MaaContextGetTasker(IntPtr context);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern byte MaaTaskerStopping(IntPtr tasker);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern byte MaaContextOverrideNext(IntPtr context, IntPtr node, IntPtr next);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr MaaStringBufferCreate();

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern void MaaStringBufferDestroy(IntPtr buffer);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern byte MaaStringBufferSet(IntPtr buffer, byte[] value);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr MaaStringListBufferCreate();

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern void MaaStringListBufferDestroy(IntPtr list);

    [DllImport(Server, CallingConvention = CallingConvention.Cdecl)]
    private static extern byte MaaStringListBufferAppend(IntPtr list, IntPtr buffer);
}
