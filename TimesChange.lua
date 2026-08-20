local addonName, ns = ...

local REPLACEMENT_MOVIE_ID = 195
local MIDNIGHT_ROOT_MAP_ID = 2537
local MAX_MAP_ANCESTORS = 16

local MIDNIGHT_MOVIE_IDS = {
	[1047] = true,
	[1048] = true,
	[1049] = true,
	[1050] = true,
	[1051] = true,
	[1053] = true,
	[1059] = true,
	[1061] = true,
	[1062] = true,
	[1063] = true,
	[1064] = true,
	[1065] = true,
	[1066] = true,
}

-- Midnight maps that do not inherit from the Quel'Thalas UiMap root.
local MIDNIGHT_STANDALONE_MAP_IDS = {
	[2443] = true, -- Silvermoon City
	[2479] = true, -- Voidstorm
	[2480] = true, -- Harandar
	[2561] = true, -- Quel'Thalas phase
	[2567] = true, -- Eversong Woods phase
	[2568] = true, -- Zul'Aman phase
	[2569] = true, -- Isle of Quel'Danas phase
}

local liveReplacementPending = false

local function IsSafeNumber(value)
	if issecretvalue(value) then
		return false
	end

	return type(value) == "number"
end

local function IsReplacementReady()
	return IsMoviePlayable(REPLACEMENT_MOVIE_ID) and IsMovieReadable(REPLACEMENT_MOVIE_ID)
end

local function PreloadReplacement()
	if not IsMovieLocal(REPLACEMENT_MOVIE_ID) then
		PreloadMovie(REPLACEMENT_MOVIE_ID)
	end
end

local function IsMidnightMap(uiMapID)
	if not IsSafeNumber(uiMapID) then
		return false
	end

	if MIDNIGHT_STANDALONE_MAP_IDS[uiMapID] then
		return true
	end

	local visited = {}
	for _ = 1, MAX_MAP_ANCESTORS do
		if uiMapID == MIDNIGHT_ROOT_MAP_ID then
			return true
		end

		if visited[uiMapID] then
			return false
		end
		visited[uiMapID] = true

		local mapInfo = C_Map.GetMapInfo(uiMapID)
		if not mapInfo then
			return false
		end

		local parentMapID = mapInfo.parentMapID
		if not IsSafeNumber(parentMapID) or parentMapID == 0 then
			return false
		end

		uiMapID = parentMapID
	end

	return false
end

local function ReplaceKnownMidnightMovie(movieFrame, originalMovieID)
	if movieFrame ~= MovieFrame
		or not IsSafeNumber(originalMovieID)
		or originalMovieID == REPLACEMENT_MOVIE_ID
		or not MIDNIGHT_MOVIE_IDS[originalMovieID]
		or not IsReplacementReady()
	then
		return
	end

	local originalOwnsLifecycle = movieFrame:IsShown()
		and IsSafeNumber(movieFrame.movieID)
		and movieFrame.movieID == originalMovieID

	if originalOwnsLifecycle then
		local started = movieFrame:StartMovie(REPLACEMENT_MOVIE_ID)
		if not started then
			-- StartMovie can stop the stream it is replacing even when the new
			-- stream fails, so explicitly restore the original movie.
			movieFrame:StartMovie(originalMovieID)
		end
	else
		-- Some Midnight assets cannot be started directly outside their quest.
		-- Blizzard already completed the failed lifecycle, so start a fresh one.
		movieFrame:PlayMovie(REPLACEMENT_MOVIE_ID)
	end
end

local function PlayReplacementAfterLiveCinematic(canBeCancelled)
	if liveReplacementPending or not IsReplacementReady() then
		return
	end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not IsMidnightMap(uiMapID) then
		return
	end

	liveReplacementPending = true
	C_Timer.After(0, function()
		liveReplacementPending = false

		if not IsReplacementReady() then
			return
		end

		local interrupted = false
		if canBeCancelled and InCinematic() then
			StopCinematic()
			interrupted = true
		elseif IsInCinematicScene() and CanCancelScene() then
			CancelScene()
			interrupted = true
		end

		if interrupted then
			MovieFrame:PlayMovie(REPLACEMENT_MOVIE_ID)
		end
	end)
end

-- XML copies mixin methods onto MovieFrame before third-party addons load, so
-- the live frame is the secure-hook target rather than the source mixin table.
hooksecurefunc(MovieFrame, "PlayMovie", ReplaceKnownMidnightMovie)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CINEMATIC_START")
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		PreloadReplacement()
	elseif event == "CINEMATIC_START" then
		local canBeCancelled = ...
		if not issecretvalue(canBeCancelled) then
			PlayReplacementAfterLiveCinematic(canBeCancelled)
		end
	end
end)

ns.addonName = addonName
