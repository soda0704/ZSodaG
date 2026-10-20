using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

internal static class NorthernLabLauncherHost {
    [STAThread]
    private static int Main(string[] args) {
        string tools = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        bool worker = args.Length > 0 && args[0] == "--build";
        try {
            // Same process-only policy as the previous shortcut's -ExecutionPolicy Bypass.
            Environment.SetEnvironmentVariable("PSExecutionPolicyPreference", "Bypass", EnvironmentVariableTarget.Process);
            using (Runspace runspace = RunspaceFactory.CreateRunspace()) {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                Runspace.DefaultRunspace = runspace;
                using (PowerShell shell = PowerShell.Create()) {
                    shell.Runspace = runspace;
                    shell.Streams.Information.DataAdded += (sender, e) => {
                        var record = shell.Streams.Information[e.Index];
                        Console.Out.Write(record.MessageData.ToString());
                        Console.Out.Flush();
                    };
                    shell.Streams.Error.DataAdded += (sender, e) => {
                        Console.Error.WriteLine(shell.Streams.Error[e.Index].ToString());
                        Console.Error.Flush();
                    };
                    if (args.Length > 0 && args[0] == "--test-full-gui") {
                        shell.AddCommand(Path.Combine(tools, "tests", "launcher_full_gui_regression.ps1"));
                    } else if (args.Length > 0 && args[0] == "--test-gui") {
                        shell.AddCommand(Path.Combine(tools, "tests", "launcher_gui_regression.ps1"));
                    } else if (args.Length > 0 && args[0] == "--test-core") {
                        shell.AddCommand(Path.Combine(tools, "tests", "launcher_build_regression.ps1"));
                    } else {
                        shell.AddCommand(Path.Combine(tools, "northernlab_launcher.ps1"));
                        shell.AddParameter("Hosted", true);
                        if (worker) {
                            shell.AddParameter("BuildOnly", true);
                            shell.AddParameter("BuildSessionDirectory", args[1]);
                        }
                    }
                    foreach (PSObject item in shell.Invoke()) Console.Out.WriteLine(item.ToString());
                    // Caught/recovered errors also set HadErrors; only an unhandled
                    // invocation failure should make the application fail.
                    return shell.InvocationStateInfo.State == PSInvocationState.Failed ? 1 : 0;
                }
            }
        } catch (Exception error) {
            string log = Path.Combine(tools, ".local", "launcher-logs", "host-error.log");
            Directory.CreateDirectory(Path.GetDirectoryName(log));
            File.AppendAllText(log, DateTime.Now.ToString("o") + " " + error + Environment.NewLine);
            Console.Error.WriteLine(error.ToString());
            if (args.Length == 0) MessageBox.Show(error.Message + "\n\n" + log, "NorthernLab Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
