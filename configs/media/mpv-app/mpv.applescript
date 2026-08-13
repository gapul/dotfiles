-- mpv launcher. Homebrew's mpv is CLI-only and ships no .app, so Finder needs something to
-- open a video with; this is that something. Compiled into ~/Applications/mpv.app at
-- activation (see darwin-apps.nix) rather than committed as a built bundle.

on open theFiles
	set fileList to ""
	repeat with theFile in theFiles
		set filePath to POSIX path of theFile
		if fileList is "" then
			set fileList to quoted form of filePath
		else
			set fileList to fileList & " " & quoted form of filePath
		end if
	end repeat
	do shell script "/opt/homebrew/bin/mpv " & fileList & " &"
end open

on run
	display dialog "mpv Media Player - Drop a media file to open it."
end run
