-- photoctrl
-- jan.arnhold.com, 2016

-- load cfg
dofile('photoctrl_cfg.lua')

-- constants

-- if no connection could be established after this time, an own hotspot will
-- be created
WIFI_CONNECT_TIMER_TIME = 5000; -- ms
WIFI_CONNECT_TIMER =      1; -- timer id
WIFI_SEND_BLOCK_SIZE =    1460;

-- namespaces
wlan = {}
http = {}

-- checks if for a given wifi name (SSID) a configuration is found in CONF_WIFI
-- if cfg exists, connect to it
-- t .. table of wifi stations
-- returns true if a matching wifi was found
function wlan.tryConnect(t)
	for k,v in pairs(t) do
		if CONF_WIFI[k] ~= nil then
			print( "Station found " .. k ..", trying to connect" )
			wifi.sta.config(k,CONF_WIFI[k])
			wifi.sta.autoconnect(1)
			wifi.sta.connect() -- did also work without
		end
	end
end

-- scan all wifi networks and check if configuration is found for one of them
function wlan.connectOrCreate()
	wifi.setmode(wifi.STATION)
	wifi.sta.getap(wlan.tryConnect)

	-- create a timer to check if connection was established
	-- if not, a hotspot will be setup

	tmr.alarm(WIFI_CONNECT_TIMER, WIFI_CONNECT_TIMER_TIME, 1, function()
		local status = wifi.sta.status()
		if status == 5 then -- 5: STATION_GOT_IP
			tmr.stop( WIFI_CONNECT_TIMER )
			print( "Connected to wifi ", wifi.sta.getip() )
		elseif status ~= 1 then
			-- 0: STATION_IDLE, 2: STATION_WRONG_PASSWORD,
			-- 3: STATION_NO_AP_FOUND, 4: STATION_CONNECT_FAIL
			tmr.stop( WIFI_CONNECT_TIMER )
			print( "Idle, Wrong password, no AP found or connect failed. Creating hotspot" )
			wifi.setmode(wifi.SOFTAP)
			wifi.ap.config( CONF_HOTSPOT )
			print( wifi.sta.getip() )
		else -- 1: STATION_CONNECTING
			print( "." )
		end
	end)

end


-- sends a buffer on a given connection
-- if the buffersize exedes WIFI_SEND_BLOCK_SIZE than several chunks are sent
--
-- will retrigger watchdog in order to allow sending of large buffers
--
-- conn .. connection
-- buf ..  buffer to send
--
-- WIFI_SEND_BLOCK_SIZE
function wlan.send( conn, buf )
	if buf ~= nil then
		local startpos = 1
		while startpos < #buf do
			conn:send( string.sub( buf, startpos, (startpos+WIFI_SEND_BLOCK_SIZE > #buf  and -1 or startpos+WIFI_SEND_BLOCK_SIZE-1) ) )
			--print( "sending chunk ", startpos, (startpos+WIFI_SEND_BLOCK_SIZE > #buf  and -1 or startpos+WIFI_SEND_BLOCK_SIZE-1), "  buffer size", #buf )
			startpos = startpos + WIFI_SEND_BLOCK_SIZE
			tmr.wdclr()
		end	
	end
end

-- html namespace
html = {}

-- returns a file header for a html document
function html.header( title )
	return "<html><head><title>" .. title .. '</title><link rel="stylesheet" type="text/css" href="style.css"><meta name="viewport" content="width=device-width, initial-scale=1.0"><meta name="apple-mobile-web-app-capable" content="yes" /></head><body>'
end

-- returns the footer for a html document
function html.footer()
	return "</body></html>"
end

-- return gui title bar
function html.title()
	return '<div id="logo"><a id="logo" href="/menu">' .. ( PCMODENAMES[mode] and 'pC</a> <span id="mode">' .. PCMODENAMES[mode] .. '</span>' or "photoCtrl</a>" ) .. '</div><div id="topblock"></div>'
end


function html.menuitems( t )
	local buf = ""
	for _, item in pairs(t) do
		if item == MENUSEPARATOR then
			buf = buf .. '<div id="separator"></div>'
		else
			buf = buf .. '<p><div id="menuitem"><a id="menuitem" href="/' .. item .. '">' ..  PCMODENAMES[ PCMODE[item] ] .. '</a></div></p>'
		end
	end
	return buf
end

function html.gui()
	local buf = ""

	-- display menus or the mode depending ui
    if mode == PCMODE.menu then
    	buf = buf .. html.menuitems( PCMAINMENU )
    elseif mode == PCMODE.menuextras then
    	buf = buf .. html.menuitems( PCEXTRASMENU )

    elseif mode == PCMODE.lightning then
	    buf = buf .. [[
	    		<p>Gewitteraufnahme</p>
		    ]]
	elseif mode == PCMODE.bulb then
	    buf = buf .. [[
			<form>
				<p>
					<label>Belichtungszeit in Sekunden</label><br />
					<input type="number" name="time" />
				</p>
				<p></p>
				<p>This is an paragraph</p>
				<p>PIO0 <a href="?pin=ON1"><button>ON</button></a>&nbsp;<a href="?pin=OFF1"><button>Start</button></a></p>
			</form>
			]]
	elseif mode == PCMODE.debug then
	    buf = buf.."<p>GPIO0 <a href=\"?pin=ON1\"><button>ON</button></a>&nbsp;<a href=\"?pin=OFF1\"><button>OFF</button></a></p>";
	    buf = buf.."<p>GPIO2 <a href=\"?pin=ON2\"><button>ON</button></a>&nbsp;<a href=\"?pin=OFF2\"><button>OFF</button></a></p>";
    	buf = buf .. ""
    end

    return buf
end


-- sends file contents or returns 404 if file was not found
--
-- client .. net.socket object
-- path .. path to file (first slash must be removed before calling)
function http.sendfile( client, path )
	if file.open( path, "r" ) ~= nil then
		local buf
		repeat
			buf = file.read()
			wlan.send( client, buf )
		until buf == nil

		file.close()
		return ""
	else
		-- print("404 Not Found " .. string.sub( path, 2, -1 ))
		return "404 Not found " 
	end
end


mode = 0;
PCMODE = {
	["menu"] = 0,
	["lightning"] = 1,
	["bulb"] = 2,
	["menuextras"] = 98,
	["debug"] = 99
}

PCMODENAMES = {
	[1] = "Gewitter",
	[2] = "Langzeit",
	[98] = "Extras",
	[99] = "Debug"
}

MENUSEPARATOR = "_sep_"
PCMAINMENU = {"lightning", "bulb", MENUSEPARATOR, "menuextras"}
PCEXTRASMENU = { "debug" }

function getIDofValue( t, value )
	for id, v in ipairs(t) do 
		if value == v then 
			return id 
		end 
	end
end


function http.request(client,request)
    local buf = "";
    local filewassent = false

    -- parse http request
    local _, _, method, path, vars = string.find(request, "([A-Z]+) (.+)?(.+) HTTP");
    if(method == nil)then
        _, _, method, path = string.find(request, "([A-Z]+) (.+) HTTP");
    end

    -- if a path is given, than either a file is to be returned
    -- or a mode swith is requested
    if #path > 1 then
    	-- remove leading slash
    	path = string.sub( path, 2, -1 )
    	-- check for mode switch
		if PCMODE[path] ~= nil then
			mode = PCMODE[path]
		else
			-- no mode is found, so return file of an 404 error
    		buf = buf .. http.sendfile( client, path )
			filewassent = true -- file was found and set
		end
    end

    -- if no file was requested build user interface
    if filewassent == false then
	    -- parse parameters
	    local _GET = {}
	    if (vars ~= nil)then
	        for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do
	            _GET[k] = v
	        end
	    end

	    buf = buf .. html.header( "photoctrl" )
	    buf = buf .. html.title()

	    buf = buf .. html.gui()

	    if(_GET.pin == "ON1")then
	        gpio.write(led1, gpio.HIGH);

	    elseif(_GET.pin == "OFF1")then
	        gpio.write(led1, gpio.LOW);
	    
	    elseif(_GET.pin == "ON2")then
	        gpio.write(led2, gpio.HIGH);
	    
	    elseif(_GET.pin == "OFF2")then
	        gpio.write(led2, gpio.LOW);
	    end

	    -- extra debug
	    if mode == PCMODE.debug then
    	    buf = buf .. "<h3>Path</h3><p>" .. path .. "</p>"
	    	buf = buf .. "<h2>Request</h3><p> " .. request .. "</p>"
	    	buf = buf .. "<h2>Heap</h3><p> " .. node.heap() .. "</p>"
	    	buf = buf .. "<h2>Files and Storage</h3><p><tt>"
	    	for k,v in pairs(file.list()) do 
	    		buf = buf .. k .. " (" .. v .. " bytes) <br />" 
	    	end
	    	local remaining, used, total=file.fsinfo()
	    	buf = buf .. "</tt></p>"
	    	buf = buf .. "<p>" .. (remaining * 100 / total) .. "% free</p>"

	    end

	    buf = buf .. html.footer()
	end
	
    --client:send(buf);
    wlan.send( client, buf )
    client:close();
    buf = nil
    collectgarbage();
end



--main
-- try to connect to an existing wifi or create one
wlan.connectOrCreate()



led1 = 3
led2 = 4
gpio.mode(led1, gpio.OUTPUT)
gpio.mode(led2, gpio.OUTPUT)
srv=net.createServer(net.TCP)
srv:listen(80,function(conn)
    conn:on("receive", http.request)
end)
