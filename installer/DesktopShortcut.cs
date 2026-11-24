using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
class DesktopShortcut {
    [STAThread]
    static int Main(string[] args) {
        try {
            if (args.Length != 1) return 2;
            string target = Path.GetFullPath(args[0]);
            if (!String.Equals(Path.GetFileName(target), "telezeka.exe", StringComparison.OrdinalIgnoreCase) || !File.Exists(target)) return 3;
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            if (String.IsNullOrEmpty(desktop) || !Directory.Exists(desktop)) return 4;
            string path = Path.Combine(desktop,"Telezeka.lnk");
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return 5;
            dynamic shell = Activator.CreateInstance(shellType);
            dynamic shortcut = null;
            try {
                shortcut = shell.CreateShortcut(path);
                shortcut.TargetPath = target;
                shortcut.WorkingDirectory = Path.GetDirectoryName(target);
                shortcut.Description = "Telezeka";
                shortcut.IconLocation = target + ",0";
                shortcut.Save();
                return File.Exists(path) ? 0 : 6;
            } finally {
                if (shortcut != null) Marshal.FinalReleaseComObject(shortcut);
                Marshal.FinalReleaseComObject(shell);
            }
        } catch (Exception) {
            MessageBox.Show("Не удалось создать ярлык Telezeka. Приложение доступно в меню Пуск.", "Telezeka", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 1;
        }
    }
}
