using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace NorthernLab.Launcher {
    public sealed class OutputChunk {
        public readonly string Text;
        public readonly bool IsError;
        public OutputChunk(string text, bool isError) { Text = text; IsError = isError; }
    }

    // All pipe reads and file writes run in managed code. No PowerShell
    // callbacks, runspaces or UI events are invoked on background threads.
    public sealed class ProcessCapture : IDisposable {
        private readonly Process process = new Process();
        private readonly ConcurrentQueue<OutputChunk> pending = new ConcurrentQueue<OutputChunk>();
        private Task stdoutTask, stderrTask;
        private bool started;

        public ProcessCapture(string executable, string arguments, string directory, IDictionary environment) {
            var info = new ProcessStartInfo(executable, arguments);
            info.WorkingDirectory = directory;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.StandardOutputEncoding = new UTF8Encoding(false);
            info.StandardErrorEncoding = new UTF8Encoding(false);
            if (environment != null)
                foreach (DictionaryEntry entry in environment)
                    info.EnvironmentVariables[(string)entry.Key] = Convert.ToString(entry.Value);
            process.StartInfo = info;
        }

        public void Start(string stdoutPath, string stderrPath) {
            process.Start();
            started = true;
            stdoutTask = Task.Factory.StartNew(() => Pump(process.StandardOutput, stdoutPath, false),
                TaskCreationOptions.LongRunning);
            stderrTask = Task.Factory.StartNew(() => Pump(process.StandardError, stderrPath, true),
                TaskCreationOptions.LongRunning);
        }

        private void Pump(StreamReader reader, string path, bool isError) {
            using (var file = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite))
            using (var writer = new StreamWriter(file, new UTF8Encoding(false))) {
                writer.AutoFlush = true;
                var buffer = new char[4096];
                int count;
                while ((count = reader.Read(buffer, 0, buffer.Length)) != 0) {
                    string text = new string(buffer, 0, count);
                    writer.Write(text);
                    pending.Enqueue(new OutputChunk(text, isError));
                }
            }
        }

        public OutputChunk[] Drain() {
            var result = new List<OutputChunk>();
            OutputChunk item;
            while (result.Count < 64 && pending.TryDequeue(out item)) result.Add(item);
            return result.ToArray();
        }

        public bool HasExited { get { return started && process.HasExited; } }
        public bool OutputFinished { get { return stdoutTask != null && stderrTask != null && stdoutTask.IsCompleted && stderrTask.IsCompleted && pending.IsEmpty; } }
        public int ExitCode { get { return process.ExitCode; } }
        public int Id { get { return process.Id; } }
        public void Kill() { if (started && !process.HasExited) process.Kill(); }
        public void CheckOutput() {
            if (stdoutTask != null && stdoutTask.IsFaulted) throw stdoutTask.Exception;
            if (stderrTask != null && stderrTask.IsFaulted) throw stderrTask.Exception;
        }

        public void Dispose() {
            Kill();
            if (started) {
                process.WaitForExit(5000);
                if (stdoutTask != null && stderrTask != null && !Task.WaitAll(new[] { stdoutTask, stderrTask }, 5000)) {
                    process.StandardOutput.BaseStream.Close();
                    process.StandardError.BaseStream.Close();
                }
            }
            process.Dispose();
        }
    }
}
