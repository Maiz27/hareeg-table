param(
  [Parameter(Mandatory = $true)]
  [string]$InputDir,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir,

  [int]$BaseWidth = 128,
  [int]$BaseHeight = 184
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$resizerSource = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class CardResolutionExporter
{
    public static void ResizePng(string inputPath, string outputPath, int width, int height)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath));

        using (var original = Image.FromFile(inputPath))
        using (var output = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        using (var graphics = Graphics.FromImage(output))
        {
            graphics.Clear(Color.Transparent);
            graphics.CompositingMode = CompositingMode.SourceOver;
            graphics.CompositingQuality = CompositingQuality.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.DrawImage(original, 0, 0, width, height);
            output.Save(outputPath, ImageFormat.Png);
        }
    }
}
"@

Add-Type -TypeDefinition $resizerSource -ReferencedAssemblies System.Drawing

$resolvedInput = (Resolve-Path -LiteralPath $InputDir).Path
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path

$sizes = @(
  [PSCustomObject]@{ Scale = '1.0x'; Folder = ''; Width = $BaseWidth; Height = $BaseHeight },
  [PSCustomObject]@{ Scale = '2.0x'; Folder = '2.0x'; Width = $BaseWidth * 2; Height = $BaseHeight * 2 },
  [PSCustomObject]@{ Scale = '4.0x'; Folder = '4.0x'; Width = $BaseWidth * 4; Height = $BaseHeight * 4 }
)

$files = Get-ChildItem -LiteralPath $resolvedInput -File -Filter *.png | Sort-Object Name
$rows = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
  foreach ($size in $sizes) {
    $targetDir = if ($size.Folder -eq '') {
      $resolvedOutput
    } else {
      Join-Path $resolvedOutput $size.Folder
    }
    $targetPath = Join-Path $targetDir $file.Name
    [CardResolutionExporter]::ResizePng($file.FullName, $targetPath, $size.Width, $size.Height)
    $rows.Add([PSCustomObject]@{
      Source = $file.Name
      Scale = $size.Scale
      Output = $targetPath
      Width = $size.Width
      Height = $size.Height
    })
  }
}

$mapSource = Join-Path $resolvedInput 'asset-map.csv'
if (Test-Path -LiteralPath $mapSource) {
  Copy-Item -LiteralPath $mapSource -Destination (Join-Path $resolvedOutput 'asset-map.csv') -Force
}

$variantMapPath = Join-Path $resolvedOutput 'resolution-variants.csv'
$rows | Export-Csv -LiteralPath $variantMapPath -NoTypeInformation

Write-Output "Exported $($files.Count) card assets at $($sizes.Count) resolutions."
Write-Output "Source untouched: $resolvedInput"
Write-Output "Output: $resolvedOutput"
Write-Output "Variant map: $variantMapPath"
