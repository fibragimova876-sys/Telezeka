using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
internal static class SetupBootstrap {
    [STAThread]
    private static int Main() {
        string temp = Path.Combine(Path.GetTempPath(), "Telezeka-" + Guid.NewGuid().ToString("N"));
        try {
            Directory.CreateDirectory(temp);
            string msi = Path.Combine(temp, "Telezeka-x64.msi");
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Telezeka.Payload")) {
                if (resource == null) throw new InvalidOperationException("Installer payload missing.");
                using (FileStream output = new FileStream(msi, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                    resource.CopyTo(output);
                }
            }
            string engine = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "msiexec.exe");
            using (Process process = Process.Start(new ProcessStartInfo(engine, "/i \"" + msi + "\"") { UseShellExecute = false })) {
                if (process == null) throw new InvalidOperationException("Windows Installer unavailable.");
                process.WaitForExit();
                return process.ExitCode;
            }
        } catch (Exception ex) {
            MessageBox.Show(ex.Message, "Telezeka Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        } finally {
            try { Directory.Delete(temp, true); } catch (IOException) {} catch (UnauthorizedAccessException) {}
        }
    }
}
