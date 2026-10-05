try {
  Add-Type -TypeDefinition @'
using System.Collections.Generic;
using System.Reflection.Metadata;
public class Q { public static List<string> S() { var l = new List<string>(); l.Add(typeof(MetadataReader).Name); return l; } }
'@ -ErrorAction Stop
  Write-Host ('OK ' + ([Q]::S() -join ','))
} catch { Write-Host ('FAIL: ' + $_.Exception.Message) }
