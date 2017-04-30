#Requires -Modules 'InvokeBuild'
Param (
    [string]$BuildOutput = "$PSScriptRoot\BuildOutput",

    [string[]]$Dependency = @('Coveralls','Pester','PsScriptAnalyzer'),

    [string]$SourceFolder = "$PSScriptRoot\$($env:APPVEYOR_PROJECT_NAME)",

    [string]$TestUploadUrl = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",

    [string]$CoverallsKey = $env:CA_Key,

    [string]$Branch = $env:APPVEYOR_REPO_BRANCH
)

Function Write-TaskBanner ( [string]$TaskName )
{
    "`n" + ('-' * 79) + "`n" + "`t`t`t $($TaskName.ToUpper()) `n" + ('-' * 79) + "`n"
}

task Clean {
    Write-TaskBanner -TaskName $Task.Name

    If (Test-Path -Path $Script:BuildOutput) {
        "Removing existing files and folders in $($Script:BuildOutput)\"
        Get-ChildItem $Script:BuildOutput | Remove-Item -Force -Recurse
    }
    Else {
        "$Script:BuildOutput is not present, nothing to clean up."
        $Null = New-Item -ItemType Directory -Path $Script:BuildOutput
    }
}

task Install_Dependencies {
    Write-TaskBanner -TaskName $Task.Name

    Foreach ( $Depend in $Script:Dependency ) {
        Install-Module $Depend -Scope CurrentUser -Force
        Import-Module $Depend -Force
    }
}

task Unit_Tests {
    Write-TaskBanner -TaskName $Task.Name

    $UnitTestParams = @{
        Script = '.\Tests\Unit'
        CodeCoverage = '.\PSCodeHealth\P*\*'
        OutputFile = "$($Script:BuildOutput)\UnitTestsResult.xml"
        PassThru = $True
    }
    $Script:UnitTestsResult = Invoke-Pester @UnitTestParams
}

task Fail_If_Failed_Unit_Test -If ( $Script:UnitTestsResult.FailedCount -ne 0 ) {
    Write-TaskBanner -TaskName $Task.Name

    assert ($Script:UnitTestsResult.FailedCount -eq 0) ('{0} Unit test(s) failed. Aborting build' -f $Script:UnitTestsResult.FailedCount)
}

task Publish_Unit_Tests_Coverage -If ( $Script:UnitTestsResult.CodeCoverage ) {
    Write-TaskBanner -TaskName $Task.Name

    $Coverage = Format-Coverage -PesterResults $Script:UnitTestsResult -CoverallsApiToken $Script:CoverallsKey -BranchName $Script:Branch
    Publish-Coverage -Coverage $Coverage
}

task Integration_Tests {
    Write-TaskBanner -TaskName $Task.Name

    $IntegrationTestParams = @{
        Script = '.\Tests\Integration'
        OutputFile = "$($Script:BuildOutput)\IntegrationTestsResult.xml"
        PassThru = $True
    }
    $Script:IntegrationTestsResult = Invoke-Pester @IntegrationTestParams
}

task Fail_If_Failed_Integration_Test -If ( $Script:IntegrationTestsResult.FailedCount -ne 0 ) {
    Write-TaskBanner -TaskName $Task.Name

    assert ($Script:IntegrationTestsResult.FailedCount -eq 0) ('{0} Integration test(s) failed. Aborting build' -f $Script:IntegrationTestsResult.FailedCount)
}

task Upload_Test_Results_To_AppVeyor {
    Write-TaskBanner -TaskName $Task.Name

    $TestResultFiles = (Get-ChildItem -Path $Script:BuildOutput -Filter '*TestsResult.xml').FullName
    Foreach ( $TestResultFile in $TestResultFiles ) {
        "Uploading test result file : $TestResultFile"
        (New-Object 'System.Net.WebClient').UploadFile($Script:TestUploadUrl, $TestResultFile)
    }
}

task Test Unit_Tests,
    Fail_If_Failed_Unit_Test,
    Publish_Unit_Tests_Coverage,
    Integration_Tests,
    # There are no integration tests at the moment
    # Fail_If_Failed_Integration_Test,
    Upload_Test_Results_To_AppVeyor

Task Copy_Source_To_Build_Output {
    Write-TaskBanner -TaskName $Task.Name

    "Copying the source folder [$Script:SourceFolder] into the build output folder : [$Script:BuildOutput]"
    Copy-Item -Path $Script:SourceFolder -Destination $Script:BuildOutput -Recurse
}

# Default task :
task . Clean,
    Install_Dependencies,
    Test,
    Copy_Source_To_Build_Output