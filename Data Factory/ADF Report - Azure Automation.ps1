Login-AzAccount

$filePath = "file name"
$reportDate = [datetime]::ParseExact($filePath, "yyyyMMdd", $null)
$startAfter = $reportDate.AddDays(-1)
$startBefore = $reportDate

#Debug.Assert
Write-Output "Pipeline Logging Started."
Write-Output (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Write-Output ("Filter condition - Start After: {0}, Start Before : {1}" -f $startAfter, $startBefore)

#report file name
$pipelineRunFile = $filePath+"_ADFPipelineRuns.csv"
$activityRunFile = $filePath+"_ADFActivityRuns.csv"

#creating files
New-Item -ItemType "File" -Path $pipelineRunFile -Force
New-Item -ItemType "File" -Path $ActivityRunFile -Force

#header
"Subscription Name`tResource Group Name`tData Factory Name`tPipeline Name`tPipeline Run Start`tPipeline Run End`tPipeline Duration in MS`tParameter[Source folder]`tParameter[Source file]`tPipeline Status" | Out-File -FilePath $pipelineRunFile
"Subscription Name`tResource Group Name`tData Factory Name`tPipeline Name`tPipeline Run Start`tPipeline Run End`tPipeline Duration in MS`tParameter[Source folder]`tParameter[Source file]`tPipeline Status`tActivity Name`tActivity Run Start`tActivity Run End`tActivity Duration in Ms`tActivity Status`tData Read`tData Written`tFiles Read`tFiles Written`tCopy Duration(s)`tSource Type`tSink Type`tStatus`tDuration`tError Code`tMessage`tFailure Type`tTarget" `
| Out-File -FilePath $activityRunFile

#getting pipeline runs
$subscriptions = "list of subscription" #"subscription name 1", "subscription name 2"

foreach ($subscription in $subscriptions)
{
    Select-AzSubscription -Subscription $subscription
    Write-Output $subscription 
    
    $pipelines = Get-AzResourceGroup | ForEach-Object {Get-AzDataFactoryV2 -ResourceGroupName $_.ResourceGroupName} | ForEach-Object {Get-AzDataFactoryV2Pipeline -ResourceGroupName $_.ResourceGroupName -DataFactoryName $_.DataFactoryName} | Select-Object ResourceGroupName, DataFactoryName, Name

    foreach($pipeline in $pipelines)
    {
        $rg = $pipeline.ResourceGroupName.ToString()
        $dataFactoryName = $pipeline.DataFactoryName.ToString()
        $pipelineName = $pipeline.Name.ToString()    

        Write-Output ("Resource Group : {0}, Data Factory : {1} , Pipeline : {2}" -f $rg, $dataFactoryName, $pipelineName)

        $pipelineRuns = Get-AzureRmDataFactoryV2PipelineRun -ResourceGroupName $rg -DataFactoryName $DataFactoryName -PipelineName $pipelineName -LastUpdatedAfter $startAfter -LastUpdatedBefore $startBefore

        foreach ($runs in $pipelineRuns)
        {
            #write pipeline run report
            "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}`t{9}" -f $subscription, $rg, $dataFactoryName, $runs.PipelineName, $runs.RunStart, $runs.RunEnd, $runs.DurationInMs, $runs.Parameters["sourceFolder"], $runs.Parameters["sourceFile"], $runs.Status| Out-File -FilePath $pipelineRunFile -Append
    
            #Debug.Assert
            #Write-Output $runs.RunId.ToString()

            #getting activity runs
            $activitieRuns = Get-AzureRmDataFactoryV2ActivityRun -ResourceGroupName $rg -DataFactoryName $DataFactoryName -PipelineRunId $runs.RunId -RunStartedAfter $startAfter -RunStartedBefore $startBefore

            foreach ($activityRun in $activitieRuns)
            {
                #activity run output
                if (![String]::IsNullOrEmpty($activityRun.Output))
                {
                    $activityRunOutput = $activityRun.Output.ToString() | ConvertFrom-Json

                    $dataRead = $activityRunOutput.dataRead
                    $dataWritten = $activityRunOutput.dataWritten 
                    $filesRead = $activityRunOutput.filesRead
                    $filesWritten = $activityRunOutput.filesWritten
                    $copyDuration = $activityRunOutput.copyDuration
                }
                else
                {
                    $dataRead = ""
                    $dataWritten = ""
                    $filesRead = ""
                    $filesWritten = ""
                    $copyDuration = ""
                }

                #execution Details
                if (![String]::IsNullOrEmpty($activityRun.Output.executionDuration))
                {
                    $executionDetails = $activityRun.Output.executionDetails.ToString() | ConvertFrom-Json

                    $sourceType = $executionDetails[0].source.type
                    $sinkType = $executionDetails[0].sink.type
                    $status = $executionDetails[0].status
                    $duration = $executionDetails[0].duration
                }
                else
                {
                    $sourceType = ""
                    $sinkType = ""
                    $status = ""
                    $duration = ""
                }

                #activity run error
                $activityRunError = $activityRun.Error.ToString() | ConvertFrom-Json

                $errorCode = $activityRunError.errorCode
                $message = $activityRunError.message -replace "\n", " "
                $failureType = $activityRunError.failureType
                $target = $activityRunError.target

                #write activity run report
                "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}`t{9}`t{10}`t{11}`t{12}`t{13}`t{14}`t{15}`t{16}`t{17}`t{18}`t{19}`t{20}`t{21}`t{22}`t{23}`t{24}`t{25}`t{26}`t{27}" `
                -f $subscription, $rg, $dataFactoryName, `
                $runs.PipelineName, $runs.RunStart, $runs.RunEnd, $runs.DurationInMs, $runs.Parameters["sourceFolder"], $runs.Parameters["sourceFile"], $runs.Status, `
                $activityRun.ActivityName, $activityRun.ActivityRunStart, $activityRun.ActivityRunEnd, $activityRun.DurationInMs, $activityRun.Status, `
                $dataRead, $dataWritten, $filesRead, $filesWritten, $copyDuration, `
                $sourceType, $sinkType,$status, $duration, `
                $errorCode, $message, $failureType, $target `
                | Out-File -FilePath $activityRunFile -Append
            }
        }    
    }   
}

#check
if ((Import-Csv -Path $pipelineRunFile).Count -gt 0)
{

    Write-Output "Pipeline Logging Completed and upload reports to blob storage."

    #Upload file to storage account
    if ((Get-Item $pipelineRunFile).length -gt 0 -or (Get-Item $activityRunFile).Length -gt 0)
    {
        $storageAccountName = "storage account name for reports"

        $acctKey = (Get-AzureRmStorageAccountKey -Name $storageAccountName -ResourceGroupName $rg).Value[0]
        $storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $acctKey
        Set-AzureStorageBlobContent -File $pipelineRunFile -Container "adfruns" -BlobType "Block" -Context $storageContext -Verbose -Force
        Set-AzureStorageBlobContent -File $activityRunFile -Container "adfruns" -BlobType "Block" -Context $storageContext -Verbose -Force
    }

}

Write-Output "Completed."
Write-Output (Get-Date -Format "yyyy-MM-dd HH:mm:ss")