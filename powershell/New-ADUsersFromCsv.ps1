<#
.SYNOPSIS
    Crea usuarios de Active Directory de forma masiva a partir de un fichero CSV.

.DESCRIPTION
    Lee un CSV con las columnas Nombre, Apellido, Departamento y Puesto. Para cada fila:
      1. Genera el nombre de usuario (inicial del nombre + apellido, en minúsculas y sin acentos).
      2. Comprueba si el usuario ya existe y, si es así, lo salta.
      3. Crea el usuario en la OU de su departamento, con una contraseña temporal aleatoria
         y la obligación de cambiarla en el primer inicio de sesión.
      4. Lo añade al grupo de seguridad del departamento (GRP_<Departamento>).
    Al terminar exporta un CSV con los usuarios creados y sus contraseñas temporales
    (para entregarlas por un canal seguro y borrar el fichero después).

.PARAMETER CsvPath
    Ruta del CSV de entrada.

.PARAMETER BaseOU
    OU base donde están las OUs de cada departamento. Ejemplo: "OU=Empresa,DC=empresa,DC=local".

.PARAMETER WhatIf
    Simula la ejecución sin crear nada (muy recomendable la primera vez).

.EXAMPLE
    .\New-ADUsersFromCsv.ps1 -CsvPath .\usuarios_ejemplo.csv -BaseOU "OU=Empresa,DC=empresa,DC=local" -WhatIf

.NOTES
    Requiere el módulo ActiveDirectory (RSAT) y permisos para crear usuarios.
    Autor: Toni Susany
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$BaseOU
)

Import-Module ActiveDirectory -ErrorAction Stop

# Dominio actual, para construir el UPN (usuario@dominio)
$dominio = (Get-ADDomain).DNSRoot

# --- Funciones auxiliares ----------------------------------------------------

function ConvertTo-SinAcentos([string]$texto) {
    # Descompone los caracteres acentuados (á -> a + ´) y elimina las marcas
    $normalizado = $texto.Normalize([Text.NormalizationForm]::FormD)
    $sinMarcas = $normalizado -replace '\p{Mn}', ''
    return ($sinMarcas -replace '[^a-zA-Z]', '').ToLower()
}

function New-PasswordTemporal {
    # 16 caracteres: al menos uno de cada tipo (para cumplir la directiva de
    # complejidad del dominio) y el resto aleatorios. Se evitan caracteres
    # que se confunden al dictarlos (O/0, l/1/I).
    $mayus   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $minus   = 'abcdefghijkmnopqrstuvwxyz'
    $numeros = '23456789'
    $simbolos = '!@#$%&*'
    $todos = $mayus + $minus + $numeros + $simbolos

    $caracteres = @(
        $mayus[(Get-Random -Maximum $mayus.Length)]
        $minus[(Get-Random -Maximum $minus.Length)]
        $numeros[(Get-Random -Maximum $numeros.Length)]
        $simbolos[(Get-Random -Maximum $simbolos.Length)]
    )
    $caracteres += 1..12 | ForEach-Object { $todos[(Get-Random -Maximum $todos.Length)] }

    # Se barajan para que los obligatorios no estén siempre al principio
    return -join ($caracteres | Sort-Object { Get-Random })
}

# --- Proceso principal -------------------------------------------------------

if (-not (Test-Path $CsvPath)) {
    throw "No se encuentra el fichero $CsvPath"
}

$usuarios = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8
$resultado = @()

foreach ($u in $usuarios) {
    $sam = (ConvertTo-SinAcentos $u.Nombre).Substring(0, 1) + (ConvertTo-SinAcentos $u.Apellido)
    $ou = "OU=$($u.Departamento),$BaseOU"
    $grupo = "GRP_$($u.Departamento)"

    # 1. ¿Existe ya?
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Warning "El usuario '$sam' ya existe. Se omite."
        continue
    }

    $passwordPlano = New-PasswordTemporal
    $password = ConvertTo-SecureString $passwordPlano -AsPlainText -Force

    if ($PSCmdlet.ShouldProcess($sam, "Crear usuario en $ou")) {
        try {
            New-ADUser `
                -Name "$($u.Nombre) $($u.Apellido)" `
                -GivenName $u.Nombre `
                -Surname $u.Apellido `
                -SamAccountName $sam `
                -UserPrincipalName "$sam@$dominio" `
                -Department $u.Departamento `
                -Title $u.Puesto `
                -Path $ou `
                -AccountPassword $password `
                -ChangePasswordAtLogon $true `
                -Enabled $true `
                -ErrorAction Stop

            Add-ADGroupMember -Identity $grupo -Members $sam -ErrorAction Stop

            Write-Host "[OK] $sam creado en $ou y añadido a $grupo" -ForegroundColor Green
            $resultado += [PSCustomObject]@{
                Usuario            = $sam
                NombreCompleto     = "$($u.Nombre) $($u.Apellido)"
                Departamento       = $u.Departamento
                PasswordTemporal   = $passwordPlano
            }
        }
        catch {
            Write-Error "[ERROR] No se pudo crear '$sam': $($_.Exception.Message)"
        }
    }
}

# Exporta el resultado (solo si se ha creado algún usuario)
if ($resultado.Count -gt 0) {
    $salida = "usuarios_creados_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    $resultado | Export-Csv -Path $salida -NoTypeInformation -Delimiter ';' -Encoding UTF8
    Write-Host "`nResumen exportado a $salida. Entrega las contraseñas por un canal seguro y borra el fichero." -ForegroundColor Yellow
}
