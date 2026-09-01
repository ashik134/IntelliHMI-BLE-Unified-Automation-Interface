[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SdkRoot
)

$ErrorActionPreference = 'Stop'

$resolvedSdkRoot = (Resolve-Path -LiteralPath $SdkRoot).Path
$workspaceRoot = Split-Path -Parent $PSScriptRoot

function Assert-RequiredPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required 3DiVi SDK path was not found: $Path"
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    Assert-RequiredPath -Path $Source
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force |
        Copy-Item -Destination $Destination -Recurse -Force
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    Assert-RequiredPath -Path $Source
    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

$pluginSource = Join-Path $resolvedSdkRoot 'flutter\face_sdk_3divi'
$pluginDestination = Join-Path $workspaceRoot '.facesdk\face_sdk_3divi'
Copy-DirectoryContents -Source $pluginSource -Destination $pluginDestination

$runtimeCopies = @(
    @{
        Source = Join-Path $resolvedSdkRoot 'conf\facerec'
        Destination = Join-Path $workspaceRoot 'assets\conf\facerec'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'android_arm_64\lib\arm64-v8a'
        Destination = Join-Path $workspaceRoot 'assets\lib\arm64-v8a'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'share\face_quality'
        Destination = Join-Path $workspaceRoot 'assets\share\face_quality'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'share\quality_iso'
        Destination = Join-Path $workspaceRoot 'assets\share\quality_iso'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'share\processing_block\face_detector\ssyv_light'
        Destination = Join-Path $workspaceRoot 'assets\share\processing_block\face_detector\ssyv_light'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'share\processing_block\face_fitter\fda'
        Destination = Join-Path $workspaceRoot 'assets\share\processing_block\face_fitter\fda'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'share\processing_block\face_template_extractor\100m'
        Destination = Join-Path $workspaceRoot 'assets\share\processing_block\face_template_extractor\100m'
    },
    @{
        Source = Join-Path $resolvedSdkRoot 'share\processing_block\liveness_estimator\2d_ensemble_light\4'
        Destination = Join-Path $workspaceRoot 'assets\share\processing_block\liveness_estimator\2d_ensemble_light\4'
    }
)

foreach ($copy in $runtimeCopies) {
    Copy-DirectoryContents -Source $copy.Source -Destination $copy.Destination
}

Copy-RequiredFile `
    -Source (Join-Path $resolvedSdkRoot 'license\3divi_face_sdk.lic') `
    -Destination (Join-Path $workspaceRoot 'assets\license\3divi_face_sdk.lic')

$requiredOutputs = @(
    (Join-Path $pluginDestination 'pubspec.yaml'),
    (Join-Path $workspaceRoot 'assets\conf\facerec'),
    (Join-Path $workspaceRoot 'assets\license\3divi_face_sdk.lic'),
    (Join-Path $workspaceRoot 'assets\lib\arm64-v8a\libfacerec.so'),
    (Join-Path $workspaceRoot 'assets\lib\arm64-v8a\libonnxruntime.so'),
    (Join-Path $workspaceRoot 'assets\share\processing_block\face_detector\ssyv_light\1.enc'),
    (Join-Path $workspaceRoot 'assets\share\processing_block\face_fitter\fda\1.enc'),
    (Join-Path $workspaceRoot 'assets\share\processing_block\face_template_extractor\100m\1.enc'),
    (Join-Path $workspaceRoot 'assets\share\quality_iso\NoiseEstimateNet2.bin'),
    (Join-Path $workspaceRoot 'assets\share\processing_block\liveness_estimator\2d_ensemble_light\4\part1.enc'),
    (Join-Path $workspaceRoot 'assets\share\processing_block\liveness_estimator\2d_ensemble_light\4\part2.enc')
)

foreach ($output in $requiredOutputs) {
    Assert-RequiredPath -Path $output
}

Write-Output "3DiVi Face SDK runtime staged from: $resolvedSdkRoot"
Write-Output 'Target ABI: arm64-v8a'
Write-Output 'Next step: flutter pub get'
