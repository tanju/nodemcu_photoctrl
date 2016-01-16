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



-- checks if for a given wifi name (SSID) a configuration is found in CONF_WIFI
-- if cfg exists, connect to it
-- t .. table of wifi stations
-- returns true if a matching wifi was found
function tryConnectWifi(t)
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
function connectOrCreateWifi()
	wifi.setmode(wifi.STATION)
	wifi.sta.getap(tryConnectWifi)

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
-- conn .. connection
-- buf ..  buffer to send
--
-- WIFI_SEND_BLOCK_SIZE
function wifiSend( conn, buf )
	local startpos = 1
	while startpos < #buf do
		conn:send( string.sub( buf, startpos, (startpos+WIFI_SEND_BLOCK_SIZE > #buf  and -1 or startpos+WIFI_SEND_BLOCK_SIZE-1) ) )
		print( "sending chunk ", startpos, (startpos+WIFI_SEND_BLOCK_SIZE > #buf  and -1 or startpos+WIFI_SEND_BLOCK_SIZE-1) )
		startpos = startpos + WIFI_SEND_BLOCK_SIZE
	end	
end


function htmlheader( title )
	return "<html><head><title>" .. title .. '</title><link rel="stylesheet" type="text/css" href="style.css"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head><body>'
end

function htmlfooter()
	return "</body></html>"
end

-- get file via http
function httpgetfile( path )
	if file.open( string.sub( path, 2, -1 ), "r" ) ~= nil then
		local buf = file.read()
		file.close()
		return buf
	else
		-- print("404 Not Found " .. string.sub( path, 2, -1 ))
		return "404 Not found " 
	end
end


function httprequest(client,request)
    local buf = "";

    -- parse http request
    local _, _, method, path, vars = string.find(request, "([A-Z]+) (.+)?(.+) HTTP");
    if(method == nil)then
        _, _, method, path = string.find(request, "([A-Z]+) (.+) HTTP");
    end

    if #path > 1 then
    	buf = buf .. httpgetfile( path )
    else
	    -- parse parameters
	    local _GET = {}
	    if (vars ~= nil)then
	        for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do
	            _GET[k] = v
	        end
	    end

	    buf = buf .. htmlheader( "photoctrl" )

	    buf = buf.."<h1>photoCtrl</h1>";
	    buf = buf.."<p>GPIO0 <a href=\"?pin=ON1\"><button>ON</button></a>&nbsp;<a href=\"?pin=OFF1\"><button>OFF</button></a></p>";
	    buf = buf.."<p>GPIO2 <a href=\"?pin=ON2\"><button>ON</button></a>&nbsp;<a href=\"?pin=OFF2\"><button>OFF</button></a></p>";
	    local _on,_off = "",""
	    if(_GET.pin == "ON1")then
	        gpio.write(led1, gpio.HIGH);
	        buf = buf .. "<p>ON1</p>"

	    elseif(_GET.pin == "OFF1")then
	        gpio.write(led1, gpio.LOW);
	        buf = buf .. "<p>OFF1</p>"
	    
	    elseif(_GET.pin == "ON2")then
	        gpio.write(led2, gpio.HIGH);
	        buf = buf .. "<p>ON2</p>"
	    
	    elseif(_GET.pin == "OFF2")then
	        gpio.write(led2, gpio.LOW);
	        buf = buf .. "<p>OFF2</p>"
	    end

	    buf = buf .. [[
	    	<div class="block">
			<h2 class="block">Langzeitbelichtung</h2>
			<form>
				<p>
					<label>Zeit</label> <input type="number" name="time" />
					Belichtungszeit in Sekunden.
				</p>
				<p></p>
			</form>
			</div>
			<div class="block">
				<h2 class="block">Gewitteraufnahme</h2>
				<form>
					<p>
						<label>Zeit</label> <input type="number" name="time" />
						Belichtungszeit in Sekunden.
					</p>
					<p></p>
				</form>
			</div>
		    ]]

	    buf = buf .. '<div class="block"><h2 class="block">Debuginfo</h2>'
	    buf = buf .. "<h3>Path</h3><p>" .. path .. "</p>"
	    buf = buf .. "<h2>Request</h3><p> " .. request .. "</p>"
	    buf = buf .. "</div"

	    buf = buf .. htmlfooter()
	end
	
    --client:send(buf);
    wifiSend( client, buf )
    client:close();
    collectgarbage();
end



--main
-- try to connect to an existing wifi or create one
connectOrCreateWifi()



led1 = 3
led2 = 4
gpio.mode(led1, gpio.OUTPUT)
gpio.mode(led2, gpio.OUTPUT)
srv=net.createServer(net.TCP)
srv:listen(80,function(conn)
    conn:on("receive", httprequest)
end)
