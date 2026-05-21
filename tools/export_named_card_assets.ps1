param(
  [Parameter(Mandatory = $true)]
  [string]$InputDir,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$resolvedInput = (Resolve-Path -LiteralPath $InputDir).Path
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path

$ranks = @(
  'ace',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'jack',
  'queen',
  'king'
)

$suits = @('spades', 'hearts', 'diamonds', 'clubs')
$rows = New-Object System.Collections.Generic.List[object]

$index = 1
foreach ($suit in $suits) {
  foreach ($rank in $ranks) {
    $sourceName = 'card_{0:D3}.png' -f $index
    $targetName = "$rank`_$suit.png"
    $sourcePath = Join-Path $resolvedInput $sourceName
    $targetPath = Join-Path $resolvedOutput $targetName
    if (-not (Test-Path -LiteralPath $sourcePath)) {
      throw "Missing expected source image: $sourcePath"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    $rows.Add([PSCustomObject]@{
      Source = $sourceName
      Target = $targetName
      Kind = 'face'
    })
    $index++
  }
}

$jokerSource = Join-Path $resolvedInput 'card_053.png'
if (-not (Test-Path -LiteralPath $jokerSource)) {
  throw "Missing expected joker source image: $jokerSource"
}

foreach ($jokerName in @('joker_red.png', 'joker_black.png')) {
  Copy-Item -LiteralPath $jokerSource -Destination (Join-Path $resolvedOutput $jokerName) -Force
  $rows.Add([PSCustomObject]@{
    Source = 'card_053.png'
    Target = $jokerName
    Kind = 'joker'
  })
}

$backSource = Join-Path $resolvedInput 'card_054.png'
if (-not (Test-Path -LiteralPath $backSource)) {
  throw "Missing expected back source image: $backSource"
}
Copy-Item -LiteralPath $backSource -Destination (Join-Path $resolvedOutput 'back.png') -Force
$rows.Add([PSCustomObject]@{
  Source = 'card_054.png'
  Target = 'back.png'
  Kind = 'back'
})

$mappingPath = Join-Path $resolvedOutput 'asset-map.csv'
$rows | Export-Csv -LiteralPath $mappingPath -NoTypeInformation

Write-Output "Exported $($rows.Count) named card assets."
Write-Output "Source untouched: $resolvedInput"
Write-Output "Output: $resolvedOutput"
Write-Output "Mapping: $mappingPath"
