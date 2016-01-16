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
			<form action="/" method="get">
				<p>
					<label>Belichtungszeit in Sekunden</label><br />
					<input type="number" name="time" />
				</p>
				<p><input type="submit" value="Los"></p>
			</form>
			]]
	elseif mode == PCMODE.debug then
	    buf = buf.."<p>GPIO0 <a href=\"?pin=ON1\"><button>ON</button></a>&nbsp;<a href=\"?pin=OFF1\"><button>OFF</button></a></p>";
	    buf = buf.."<p>GPIO2 <a href=\"?pin=ON2\"><button>ON</button></a>&nbsp;<a href=\"?pin=OFF2\"><button>OFF</button></a></p>";
    	buf = buf .. ""
    end

    return buf
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


-- function getIDofValue( t, value )
-- 	for id, v in ipairs(t) do 
-- 		if value == v then 
-- 			return id 
-- 		end 
-- 	end
-- end


pc = {}

TRIGGER_MIN_TIME = 200
MAXBULBTIME = 600
TRIGGER_TIMER = 2

function pc.trigger( hold )
	gpio.write(led2, gpio.LOW);
	if( hold == false ) then
		pc.releasein( TRIGGER_MIN_TIME )
	end
end


function pc.release()
	gpio.write(led2, gpio.HIGH);
end


function pc.releasein( time )
	tmr.alarm(TRIGGER_TIMER, time, 0, pc.release)
end



function pc.modeaction( vars )
	buf = ""
	if mode == PCMODE["bulb"] then
		if vars["time"] ~= nil then
			time = tonumber( vars["time"] )
			if time ~= nil then
				if time > 0 and time < MAXBULBTIME then
					pc.trigger( true )	
					pc.releasein( time * 1000 )
				else
					buf = buf .. "Zeit für die Langzeitbelichtung ausßerhalb des gültigen Bereichs ( 0 bis " .. MAXBULBTIME .. " Sekunden )"
				end
			else
				buf = buf .. "Ungültige Zeit für die Langzeitbelichtung angegeben"
			end
		end 
	end

	return buf
end


-- http web server ...........................................................
-- 
-- The follwing section implements a small web server that allows to initiate
-- building the gui html page as well as providing a file from the ESP file
-- system. Especially for the latter the event driven aproach of the ESP LUA
-- needs to be considered. Therefore the webserver needs to know it's current
-- state in order to provide the correct data in chunks.
-- Since just one file can be open at a time, the webserver as well will not
-- support parallel requests from different clients. Parallel requests will
-- be rejected with 503.
--
-- TODO: lager gui buffers might as well be supported
-- TODO: remove wlan send
--
-- http web server states
http.STATE_IDLE =          0
http.STATE_PROCESSING_RQ = 1
http.STATE_BUILD_PAGE =    10
http.STATE_SEND_FILE =     11

http.state = http.STATE_IDLE

-- sends file contents or returns 404 if file was not found
--
-- client .. net.socket object
-- path .. path to file (first slash must be removed before calling)
function http.sendfile( client, path )
	if file.open( path, "r" ) ~= nil then

		http.state = http.STATE_SEND_FILE
		
		local buf
		--print ("http.sendfile " , path )
		buf = file.read()
		--print( #buf, "bytes read" )
		wlan.send( client, buf )
		return ""
	else
		-- print("404 Not Found " .. string.sub( path, 2, -1 ))
		return "404 Not found " 
	end
end

function http.sendnextblock( client )
	if http.state == http.STATE_SEND_FILE then
		--print ("http.sendfile (next block)" )

		buf = file.read()
		if buf ~= nil then
			--print( #buf, "bytes read" )
			wlan.send( client, buf )
		else
			--print( "end of file. closing connection" )
			file.close()
			http.state = http.STATE_IDLE
			client:close()
		end
	end
end




function http.request(client,request)
    local buf = "";
    local filewassent = false

    -- if another request is beeing currently processed, reject this request
    if http.state ~= http.STATE_IDLE then
		client:send( "503 Service Unavailable" )
    	client:close();
	    buf = nil
    	collectgarbage();
    	return
    end

    -- switch to http server state processing to block parallel requests
    http.state = http.STATE_PROCESSING_RQ

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
		end
    end

    -- if no file was requested build user interface
    if http.state == http.STATE_PROCESSING_RQ then
    	http.state = http.STATE_BUILD_PAGE

    	local modeactionresult = ""
	    -- parse parameters
	    local reqparameters = {}
	    if vars ~= nil then
	        for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do
	            reqparameters[k] = v
	        end

	        modeactionresult = modeactionresult .. pc.modeaction( reqparameters )
	    end

	    buf = buf .. html.header( "photoctrl" )
	    buf = buf .. html.title()

	    buf = buf .. html.gui()

	    if #modeactionresult > 0 then
	    	buf = buf .. '<div class="block"><p>' .. modeactionresult .. '</p></div>'
	    end

	    if(reqparameters.pin == "ON1")then
	        gpio.write(led1, gpio.HIGH);

	    elseif(reqparameters.pin == "OFF1")then
	        gpio.write(led1, gpio.LOW);
	    
	    elseif(reqparameters.pin == "ON2")then
	        gpio.write(led2, gpio.HIGH);
	    
	    elseif(reqparameters.pin == "OFF2")then
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

	    --client:send(buf);
	    wlan.send( client, buf )
	    client:close();
	    buf = nil
	    collectgarbage();

	    -- set http server state to idle
	    http.state = http.STATE_IDLE

	end

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
    conn:on("sent", http.sendnextblock)
end)
