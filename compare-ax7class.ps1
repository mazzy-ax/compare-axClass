# mazzy@mazzy.ru, 2017-10-08, https://github.com/mazzy-ax/compare-axClass

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

process {
    function findParameterNodeIn ([System.Xml.XmlElement]$node, [string]$paramName) {
        $n = $node.ax7[$paramName]
        if ( -not $n ) {
            $n = $node[$paramName]
        }
        return $n
    }

    function setParameter ($param, [System.Xml.XmlElement]$node, [string]$paramName) {
        $paramNode = findParameterNodeIn $node $paramName 
        if ( $paramNode ) {
            $param[$paramName] = $paramNode.InnerText
        }
    }

    function setParameterBool ($param, [System.Xml.XmlElement]$node, [string]$paramName) {
        $paramNode = findParameterNodeIn $node $paramName
        if ( $paramNode ) {
            $param[$paramName] = $paramNode.InnerText -ne 'false'
        }
    }

    # XML - is case sensive
    function readParameters([System.Xml.XmlElement]$node, $parentParam = @{}) {
        $param = @{}

        $parentParam.Keys | ForEach-Object {
            $param[$_] = $parentParam[$_]
        }
        
        setParameter     $param $node 'outputDirectory'
        setParameterBool $param $node 'showOverriddenMethods'
        setParameterBool $param $node 'removeXmlComments'
        setParameterBool $param $node 'removeIndent'

        return $param
    }

    [XML]$task = Get-Content $TaskPath
    $files = $task.diffAxClassMethod.files
    $parameters = readParameters $files

    $files.file | ForEach-Object {
        $fileName = $_.Name
        if ( -not $fileName ) {
            Write-Warning "#: File name was not found. skipped."
            continue
        }
        $fileParameters = readParameters $_ $parameters
        $fileName = (Join-Path (Join-Path $BaseDir $fileParameters.OutputDirectory) $fileName) + '.txt'

        $replace = @{}
        $_.ax7.sortmethod | ForEach-Object {
            if ( $_.InnerText ) {
                $replace[$_.InnerText] = $_.Attributes['as'].Value
            }
        }

        $classes = $_.ax7.class
        if ( -not $classes ) {
            $classes = $_.Name
        }

        $classes | ForEach-Object {
            $className = $_
            $classFile = (Join-Path $axClassDir $className) + '.xml'
            [XML]$class = Get-Content $classFile -ErrorAction Stop

            $class.AxClass.SourceCode.Methods.Method | ForEach-Object {
                if ( $_.Name -in $Replace.Keys ) {
                    $_.Name = $Replace[$_.Name]
                }
                $_.Name = "`n### method: $($_.Name) ### class: $className"

                if ( $fileParameters.removeXmlComments ) {
                    $_.Source.InnerXML = $_.Source.InnerXML -replace '(?m)^\s*///.*\n' # remove document comment
                }

                if ( $fileParameters.removeIndent) {
                    $_.Source.InnerXML = $_.Source.InnerXML -replace '(?m)^( {4}|\t)' # remove Indent
                }

                $_
            } | Sort-Object Name | ForEach-Object {
                $_.Name
                $_.Source.InnerText
            }
        } | Out-File $fileName -Encoding utf8
    }

    Write-Output "Done."
}
