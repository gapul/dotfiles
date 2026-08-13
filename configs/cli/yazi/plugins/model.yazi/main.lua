--- 3D モデルを f3d でオフスクリーンレンダリングしてプレビューする previewer。
--- 内蔵の pdf previewer と同じ形 (preload で画像を作り、peek で image_show)。
--- f3d は EGL/GLX/cocoa を自動で選ぶので、ssh 越しの headless Linux でもそのまま動く。

local M = {}

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err = self:preload(job)
	if not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	local _, err = ya.image_show(cache, job.area)
	ya.preview_widget(job, err)
end

function M:seek() end

function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	-- f3d は拡張子でリーダーを選ぶ。VRM/VRMA は中身が glTF バイナリなのに名前を知らないので、
	-- 拡張子を教える口が無い以上 .glb の symlink を掴ませるのが最短。
	local src = tostring(job.file.path)
	local ext = src:lower():match("%.([^.]+)$")
	if ext == "vrm" or ext == "vrma" then
		local link = tostring(cache) .. ".glb"
		local _, err = Command("ln"):arg({ "-sf", src, link }):output()
		if err then
			return true, Err("Failed to start `ln`, error: %s", err)
		end
		src = link
	end

	local png = tostring(cache) .. ".png"
	-- stylua: ignore
	local output, err = Command("f3d")
		:arg({
			src,
			"--output=" .. png,
			"--resolution=" .. rt.preview.max_width .. "," .. rt.preview.max_height,
			-- プレビューに要らない装飾を全部落とす (グリッド・軸ウィジェット・ファイル名)
			"--grid=0", "--axis=0", "--filename=0",
			"--no-background",
			-- 真正面だと厚みが分からないので少し振る
			"--camera-direction=-1,0.2,-1",
			"--verbose=quiet",
		})
		:output()

	if not output then
		return true, Err("Failed to start `f3d`, error: %s", err)
	elseif not output.status.success then
		return true, Err("Failed to render 3D model, stderr: %s", output.stderr)
	end

	return ya.image_precache(Url(png), cache)
end

return M
