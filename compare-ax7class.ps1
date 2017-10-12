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
    [string]$BaseDir = (Get-Location),

    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string]$axClassDir = 'E:\App71\Source\AppIL\Metadata\ApplicationSuite\Foundation\AxClass\'
)

# XML - is case sensitive!!!
process {
    function nz ($notNullValue, $zeroValue ) {
        if( $notNullValue) {
            $notNullValue
        }
        else {
            $zeroValue
        }
    }

    function convertTo-boolean {
        [CmdletBinding()]
        [OutputType([boolean])]
        param (
            [Parameter(ValueFromPipeline = $true, Position = 0)]
            [System.Xml.XmlNode]$node
        )
        process {
            $node -and ($node.InnerText -ne 'false')
        }
    }

    function get-Nodes {
        [CmdletBinding()]
        [OutputType([System.Xml.XmlNode[]])]
        param (
            [string]$xPath,
            [System.Xml.XmlNode[]]$nodes
        )
        process {
            $nodes | ForEach-Object {
                if ( $_.ax7 ) {
                    $_.ax7.SelectNodes($xPath)
                }
                $_.SelectNodes($xPath)
            } | Where-Object { $_ }
        }
    }
    function get-Parameter {
        [CmdletBinding()]
        [OutputType([System.Xml.XmlNode[]])]
        param (
            [string]$xPath,
            [System.Xml.XmlNode[]]$nodes
        )
        process {
            get-Nodes $xPath $nodes | Select-Object -First 1
        }
    }


    [XML]$task = Get-Content $TaskPath

    $parameters = $task.diffAxClassMethod.parameters
    $files = $task.diffAxClassMethod.files

    Write-ProgressEx "compare-ax7class" -total $files.ChildNodes.Count -ShowMessages
    $files.file | Write-ProgressEx "compare-ax7class" -increment -ShowMessages | ForEach-Object {
        $file = $_
        $fileName = $file.name
        if ( -not $fileName ) {
            Write-Warning "#: File name was not found. skipped."
            continue
        }

        $removeXmlComments = get-Parameter 'removeXmlComments' ($file, $parameters) | convertTo-boolean
        $removeIndent = get-Parameter 'removeIndent' ($file, $parameters) | convertTo-boolean
        $OutputDirectory = get-Parameter 'outputDirectory' ($file, $parameters)
        $fileName = (Join-Path (Join-Path $BaseDir $OutputDirectory.InnerText) $fileName) + '.txt'

        $sortmethods = @{}
        get-Nodes 'sortmethod' $file | Where-Object { $_.InnerText -and $_.as } | ForEach-Object {
            $sortmethods[$_.InnerText] = $_.as
        }

        $classes = nz (get-Nodes 'class' $file) $file.SelectSingleNode('name')
        $text = $classes | Where-Object { $_.InnerText } | ForEach-Object {
            $className = $_.InnerText
            $classFile = (Join-Path $axClassDir $className) + '.xml'

            [XML]$classContent = Get-Content $classFile -ErrorAction SilentlyContinue

            if ( -not $classContent ) {
                Write-Warning "Class was not readed. $classFile"
            }
            else {
                $classContent.AxClass.SourceCode.Methods.Method | Where-Object { $_ } | ForEach-Object {
                    $method = $_
                    $methodName = nz $sortmethods[$method.name] $method.name
                    $method.Name = "`n### method: $methodName ### class: $className"

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
        if ($text) {
            $text | Out-File $fileName -Encoding utf8
        }
    }
}
