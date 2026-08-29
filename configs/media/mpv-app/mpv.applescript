-- mpv launcher. mpv is CLI-only and ships no .app, so Finder needs something to open a
-- video with; this is that something. Compiled into /Applications/mpv.app at activation
-- (see darwin-apps.nix) rather than committed as a built bundle.
--
-- @mpv@ is substituted with the nix mpv at activation. `do shell script` runs with a bare
-- PATH (/usr/bin:/bin:/usr/sbin:/sbin), so a bare `mpv` would not resolve — the absolute
-- path has to be baked in.

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
	do shell script "@mpv@ " & fileList & " &"
end open

on run
	display dialog "mpv Media Player - Drop a media file to open it."
end run
