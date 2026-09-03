# Windows locale and language

Running an English UI while getting rid of the Shift-JIS mojibake, such as `\` displaying as
`¥`.

## Layout

```
windows/locale/
├── README.md
└── apply.ps1   # applies three things declaratively
```

## What it applies

### A. One language, `ja-JP`; CorvusSKK as the only IME; the UI overridden to en-US

- Removing the `en-US` language removes the English keyboard layout, `0409:00000409`.
- Setting `ja-JP`'s `InputMethodTips` to CorvusSKK alone removes MS-IME.
- The result is a single SKK entry in the taskbar's language indicator, with no `Win+Space`
  switching.
- English is typed through CorvusSKK's direct input mode, toggled with `l`.
- `Set-WinUILanguageOverride en-US` fixes the display language to English.
- Log out and back in for all of it to take effect.

CorvusSKK's TIP is registered at install time under fixed CLSIDs, the same for every user:

- ProfileGUID `{956F14B3-5310-4CEF-9651-26710EB72F3A}`
- CLSID `{EAEA0E29-AA1E-48EF-B2DF-46F4E24C6265}`

### B. System locale `en-US` with code page 65001, UTF-8

- Switches non-Unicode programs from Shift-JIS (CP932) to UTF-8 (CP65001).
- This is what actually fixes `\` showing as `¥`.
- The console code page for cmd and PowerShell becomes 65001 as well.
- Equivalent to Windows 10's beta "Use Unicode UTF-8 for worldwide language support".
- Requires a reboot; the code page only takes effect at boot.

### C. Home location, United States, GeoId 244

- Sets the region to the US.
- The clock, currency and the weather app all read in English.
- If you live in Japan and want the time and currency to stay Japanese, use
  `-SkipHomeLocation`.

## Running it

```powershell
# no side effects
just win-locale -DryRun

# for real. Elevates itself; a reboot is needed after B
just win-locale

# partially
just win-locale -SkipSystemLocale   # only the language order and home location; no reboot
just win-locale -SkipHomeLocation   # language order and system locale, keeping the Japanese region
```

bootstrap.ps1 runs it as step 9. To skip it:

```powershell
just win-bootstrap -SkipLocale
```

## Undoing it

Either change things individually under Settings, Time and Language, Language, or:

```powershell
Set-WinUserLanguageList -LanguageList 'ja', 'en-US' -Force
Set-WinSystemLocale -SystemLocale ja-JP
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'ACP' '932'
Set-WinHomeLocation -GeoId 122
```
