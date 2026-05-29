# הגדרת נתיב לקובץ התוצאות
$reportPath = "C:\Users\Public\C_Share_Report.csv"

# 1. שליפת כל המחשבים הפעילים מהדומיין (מסונן לפי מחשבים ששינו סיסמה ב-90 הימים האחרונים כדי למנוע בדיקת מחשבים ישנים)
# אם מודול ActiveDirectory לא מותקן, ניתן להחליף שורה זו בחיפוש ADSI קלאסי
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $computers = Get-ADComputer -Filter 'Enabled -eq $true' | Select-Object -ExpandProperty Name
} catch {
    Write-Warning "ActiveDirectory module not found. Falling back to ADSI search..."
    $searcher = [adsisearcher]"(objectCategory=computer)"
    $searcher.PageSize = 1000
    $computers = $searcher.FindAll() | ForEach-Object { $_.Properties.name }
}

$results = @()
Write-Host "Found $($computers.Count) computers. Starting accessibility check..." -ForegroundColor Cyan

# 2. מעבר על כל מחשב ובדיקת נגישות לשילוב C$
foreach ($computer in $computers) {
    $targetPath = "\\$computer\c$"
    Write-Host "Checking $computer..." -ForegroundColor Yellow
    
    # בדיקה האם הנתיב קיים ונגיש תחת הרשאות המשתמש הנוכחי
    if (Test-Path -Path $targetPath -ErrorAction SilentlyContinue) {
        $status = "Accessible"
        $color = "Green"
    } else {
        $status = "Not Accessible / Offline"
        $color = "Red"
    }
    
    Write-Host "Result for $computer: $status" -ForegroundColor $color
    
    # שמירת התוצאה באובייקט
    $results += [PSCustomObject]@{
        ComputerName = $computer
        NetworkPath  = $targetPath
        Status       = $status
        CheckTime    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

# 3. ייצוא כל הממצאים לקובץ CSV נקי
$results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
Write-Host "Scan complete! Results saved to: $reportPath" -ForegroundColor Green
