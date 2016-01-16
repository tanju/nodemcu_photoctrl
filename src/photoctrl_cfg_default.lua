-- photoctrl_cfg
--
-- photoCtrl configuration template
--
-- jan.arnhold.com, 2016

-- wifi APs to which photoCtrl should connect, if available
CONF_WIFI = { ["apssid"] = "passwd" }

-- if no AP is found, a hotspot with the following configuration will be
-- created
CONF_HOTSPOT = { ["ssid"] = "photoctrl",
				 ["pwd"] = "mypasswd" }

