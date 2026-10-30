# The exact external scripts apply.ps1 downloads and runs. apply.ps1 refuses to run either one
# unless its SHA256 matches. Re-pin with windows/privacy/update-upstream.ts (just
# win-privacy-update-upstream), which rewrites this file and then runs check-upstream.ts; read
# the upstream changes, especially renamed WinUtil tweak IDs, before committing.
@{
    Win11Debloat = @{
        Version = '2026.08.24'
        Commit  = 'f431c56159bfd0b68822c583509126bab8cb94cc'
        Url     = 'https://github.com/Raphire/Win11Debloat/archive/f431c56159bfd0b68822c583509126bab8cb94cc.zip'
        Sha256  = '46738965032e3a9e62e8e447fc8d9f7124e39b30d24ebff19e6232dcf31cd82c'
    }
    WinUtil = @{
        Version = '26.10.07'
        Url     = 'https://github.com/ChrisTitusTech/winutil/releases/download/26.10.07/winutil.ps1'
        Sha256  = 'eeae69922fbe6354ea4e2a37f705eaa17bdaf45cc7889618a313178a513b13ee'
    }
}
