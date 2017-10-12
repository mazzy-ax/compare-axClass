# mazzy@mazzy.ru, 2017-10-12, https://github.com/mazzy-ax/compare-axClass

#require modules Write-ProgressEx
#
# https://github.com/mazzy-ax/Write-ProgressEx
# Powershell 5+:
# PS> install-module Write-ProgressEx
# 

[CmdletBinding()]
[OutputType([String])]
param (
    # Specifies a path to a task
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath = 'compare-axClass.xml',

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string]$BaseDir = (Get-Location)
)

# XML - is case sensitive!!!
process {
    function get-Parameter ([string]$xPath, [System.Xml.XmlNode[]]$nodes) {
        $nodes | ForEach-Object {
            $_.SelectSingleNode("ax7/$xPath | $xPath")
        } | Where-Object { $_ } | Select-Object -First 1
    }

    function get-ParameterBool ([string]$xPath, [System.Xml.XmlNode[]]$nodes) {
        $node = get-Parameter $xPath $nodes
        $node -and ($node.InnerText -ne 'false')
    }

    function get-ParameterStr ([string]$xPath, [System.Xml.XmlNode[]]$nodes) {
        $node = get-Parameter $xPath $nodes
        $node.InnerText
    }

    [XML]$task = Get-Content $TaskPath

    $parameters = $task.diffAxClassMethod.parameters
    $files = $task.diffAxClassMethod.files

    if( get-ParameterBool 'removeAllOutputFiles' $parameters ) {
        $OutputDirectory = get-ParameterStr 'outputDirectory' ($file, $parameters)
        $path = (Join-Path (Join-Path $BaseDir $OutputDirectory) '*.txt')
        Remove-Item $path
        Write-Verbose "$path deleted."
    }

    Write-ProgressEx "compare-ax7class" -total $files.ChildNodes.Count -ShowMessages
    $files.file | Write-ProgressEx "compare-ax7class" -increment -ShowMessages | ForEach-Object {
        $file = $_
        $fileName = $file.name
        
        if ( -not $fileName ) {
            Write-Warning "#: File name was not found. skipped."
            continue
        }
        Write-Verbose "File $fileName"
        
        $classDir = get-ParameterStr 'classDir' ($file, $parameters)
        $removeXmlComments = get-ParameterBool 'removeXmlComments' ($file, $parameters)
        $removeIndent = get-ParameterBool 'removeIndent' ($file, $parameters)
        $OutputDirectory = get-ParameterStr 'outputDirectory' ($file, $parameters)
        $fileName = (Join-Path (Join-Path $BaseDir $OutputDirectory) $fileName) + '.txt'

        if( get-ParameterBool 'removeOutputFile' ($file, $parameters) ) {
            Remove-Item $fileName
        }    

        $sortmethods = @{}
        $file.SelectNodes('ax7/sortmethod | sortmethod')  | Where-Object { $_.InnerText -and $_.as } | ForEach-Object {
            $sortmethods[$_.InnerText] = $_.as
        }

        $classes = $file.SelectNodes('ax7/class | class')
        if ( -not $classes.Count ) {
            $classes = $file.SelectSingleNode('name')
        }
        Write-Verbose "Classes #$($classes.Count)"

        $classNames = @{}
        $text = $classes | Where-Object { $_.InnerText } | ForEach-Object {
            $className = $_.InnerText
            Write-Verbose "== Class $className"

            if ($classNames[$className]) {
                Write-Verbose "---- Already processed. Skip."
                continue
            }
            $classNames[$className] = $true

            $classFile = (Join-Path $classDir $className) + '.xml'
            [XML]$classContent = Get-Content $classFile -ErrorAction SilentlyContinue

            if ( -not $classContent ) {
                Write-Warning "Class was not readed. $classFile"
            }
            else {
                Write-Verbose "== Readed."
                $classContent.AxClass.SourceCode.Methods.Method | Where-Object { $_ } | ForEach-Object {
                    $method = $_
                    $methodName = if ($sortmethods[$method.name]) {$sortmethods[$method.name]} else {$method.name}
                    $method.Name = "`n### method: $methodName ### class: $className"
                    Write-Verbose "---- $methodName"

                    if ( $removeXmlComments ) {
                        $method.Source.InnerXML = $method.Source.InnerXML -replace '(?m)^\s*///.*\n' # remove document comment
                    }

                    if ( $removeIndent ) {
                        $method.Source.InnerXML = $method.Source.InnerXML -replace '(?m)^( {4}|\t)' # remove Indent
                    }

                    $method
                } | Sort-Object Name | ForEach-Object {
                    $_.Name
                    $_.Source.InnerText
                }
            }
        }
        if ( -not $text ) {
            Write-Warning "File is empty. $fileName"
        }
        else {
            Write-ProgressEx "Save XML" -increment -id 1
            $text | Out-File $fileName -Encoding utf8
            Write-Verbose "File saved $fileName"
        } 
    }
    Write-ProgressEx -id 1 -Completed -ShowMessages
}
