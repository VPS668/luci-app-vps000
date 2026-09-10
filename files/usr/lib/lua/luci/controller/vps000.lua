module("luci.controller.vps000", package.seeall)

local http = require "luci.http"
local sys = require "luci.sys"
local util = require "luci.util"
local dispatcher = require "luci.dispatcher"

function index()
	entry({"admin", "vps000"}, firstchild(), "VPN", 15).dependent = false
	entry({"admin", "vps000", "config"}, call("action_index"), "连接", 1)
	entry({"admin", "vps000", "status"}, call("action_status")).leaf = true
	entry({"admin", "vps000", "login"}, call("action_login")).leaf = true
	entry({"admin", "vps000", "disconnect"}, call("action_disconnect")).leaf = true
	entry({"admin", "vps000", "save"}, call("action_save")).leaf = true
	entry({"admin", "vps000", "nodes"}, call("action_nodes")).leaf = true
	entry({"admin", "vps000", "account"}, call("action_account")).leaf = true
	entry({"admin", "vps000", "order"}, call("action_order")).leaf = true
	entry({"admin", "vps000", "order_status"}, call("action_order_status")).leaf = true
	entry({"admin", "vps000", "logoff"}, call("action_logoff")).leaf = true
	entry({"admin", "vps000", "update"}, call("action_update_page"), "更新", 2)
	entry({"admin", "vps000", "update_status"}, call("action_update_status")).leaf = true
	entry({"admin", "vps000", "update_check"}, call("action_update_check")).leaf = true
	entry({"admin", "vps000", "update_apply"}, call("action_update_apply")).leaf = true
	entry({"admin", "vps000", "update_cancel"}, call("action_update_cancel")).leaf = true
	entry({"admin", "vps000", "update_progress"}, call("action_update_progress")).leaf = true
end

local function sh_quote(s)
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function scrub(s)
	s = tostring(s or "")
	s = s:gsub("%c", ""):gsub("\127", "")
	s = s:gsub("\239\187\191", "")
	s = s:gsub("\226\128\139", "")
	s = s:gsub("\194\160", " ")
	s = s:gsub("\227\128\128", " ")
	s = util.trim(s)
	s = s:gsub("^[\"'`<]+", ""):gsub("[\"'`>]+$", "")
	return util.trim(s)
end

local function valid_account(a)
	a = scrub(a)
	if a:match("%s") then
		return nil
	end
	if a:match("^[%w%._@%+%-]+$") then
		return a
	end
	return nil
end

local function valid_password(p)
	p = scrub(p)
	if p ~= "" and not p:match("[%c%$`\\]") then
		return p
	end
	return nil
end

local function valid_flag(v)
	v = scrub(v)
	if v == "1" or v == "0" then
		return v
	end
	return nil
end

local function valid_node(r)
	r = scrub(r):gsub("%s+", ""):lower()
	if r:match("^[%l%d_%-]+$") then
		return r
	end
	return nil
end

local function valid_host(h)
	h = scrub(h):gsub("%s+", ""):lower()
	h = h:gsub("^https?://", ""):gsub("/.*$", ""):gsub(":.*$", "")
	if h:match("^[%l%d][%l%d%.%-]*[%l%d]$") or h:match("^[%l%d]+$") then
		return h
	end
	return nil
end

local function apply_url_overrides()
	local server = valid_host(http.formvalue("server"))
	if server then
		sys.call("/usr/sbin/vps000 set server " .. sh_quote(server) .. " >/dev/null")
		return true
	end
	return false
end

local function save_fields()
	local account = valid_account(http.formvalue("account"))
	local password = valid_password(http.formvalue("password"))
	local enable = valid_flag(http.formvalue("enable") or "")
	local split = valid_flag(http.formvalue("split") or "")
	local killswitch = valid_flag(http.formvalue("killswitch") or "")
	local node = valid_node(http.formvalue("node") or "")
	local flags = (http.formvalue("flags") ~= "0")

	if account then
		if password then
			sys.call("/usr/sbin/vps000 set account " .. sh_quote(account) .. " " .. sh_quote(password) .. " >/dev/null")
		else
			sys.call("/usr/sbin/vps000 set account " .. sh_quote(account) .. " >/dev/null")
		end
	end
	if flags then
		if enable then
			sys.call("/usr/sbin/vps000 set enable " .. sh_quote(enable) .. " >/dev/null")
		end
		if split then
			sys.call("/usr/sbin/vps000 set split " .. sh_quote(split) .. " >/dev/null")
		end
		if killswitch then
			sys.call("/usr/sbin/vps000 set killswitch " .. sh_quote(killswitch) .. " >/dev/null")
		end
	end
	if node then
		sys.call("/usr/sbin/vps000 set node " .. sh_quote(node) .. " >/dev/null")
	end
end

function action_index()
	if apply_url_overrides() then
		http.redirect(dispatcher.build_url("admin", "vps000", "config"))
		return
	end
	luci.template.render("vps000/main")
end

function action_status()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000 status 2>/dev/null") or '{"ok":false,"msg":"无状态"}')
end

function action_save()
	save_fields()
	http.prepare_content("application/json")
	http.write_json({ ok = true, msg = "已保存" })
end

function action_login()
	save_fields()
	os.execute("mkdir -p /var/run/vps000; /usr/sbin/vps000 connect replace >/dev/null 2>&1 &")
	http.prepare_content("application/json")
	http.write_json({
		ok = true,
		pending = true,
		msg = "正在连接"
	})
end

function action_disconnect()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000 disconnect 2>/dev/null") or '{"ok":true,"msg":"已断开"}')
end

function action_nodes()
	local cmd = "/usr/sbin/vps000 nodes"
	if http.formvalue("refresh") == "1" then
		cmd = "/usr/sbin/vps000 nodes refresh"
	end
	http.prepare_content("application/json")
	http.write(sys.exec(cmd .. " 2>/dev/null") or '{"ok":false,"nodes":[]}')
end

local function valid_id(s)
	s = scrub(s)
	if s:match("^%d+$") then
		return s
	end
	return nil
end

function action_account()
	save_fields()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000 account 2>/dev/null") or '{"ok":false,"msg":"账户信息暂未获取"}')
end

function action_order()
	local pid = valid_id(http.formvalue("product_id") or "")
	local pay = valid_id(http.formvalue("pay_type") or "")
	local month = valid_id(http.formvalue("month") or "1") or "1"
	http.prepare_content("application/json")
	if not pid or not pay then
		http.write('{"ok":false,"msg":"请选择套餐和支付方式"}')
		return
	end
	http.write(sys.exec("/usr/sbin/vps000 order " .. sh_quote(pid) .. " " .. sh_quote(pay) .. " " .. sh_quote(month) .. " 2>/dev/null")
		or '{"ok":false,"msg":"下单失败"}')
end

function action_order_status()
	local ono = scrub(http.formvalue("order_no") or "")
	ono = ono:gsub("[^%w%-_]", "")
	http.prepare_content("application/json")
	if ono ~= "" then
		http.write(sys.exec("/usr/sbin/vps000 order-status " .. sh_quote(ono) .. " 2>/dev/null")
			or '{"ok":false,"msg":"查询失败"}')
	else
		http.write(sys.exec("/usr/sbin/vps000 order-status 2>/dev/null")
			or '{"ok":false,"msg":"查询失败"}')
	end
end

function action_logoff()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000 logoff 2>/dev/null") or '{"ok":false,"msg":"下线失败"}')
end

function action_update_page()
	luci.template.render("vps000/update")
end

function action_update_status()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000-update status 2>/dev/null") or '{"ok":false}')
end

function action_update_check()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000-update check-bg 2>/dev/null") or '{"ok":false,"msg":"无法检查"}')
end

function action_update_apply()
	local t = scrub(http.formvalue("target") or "")
	if t ~= "ipk" and t ~= "firmware" then
		http.prepare_content("application/json")
		http.write('{"ok":false,"msg":"无效目标"}')
		return
	end
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000-update apply " .. sh_quote(t) .. " 2>/dev/null")
		or '{"ok":false,"msg":"无法开始更新"}')
end

function action_update_cancel()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000-update cancel 2>/dev/null") or '{"ok":true}')
end

function action_update_progress()
	http.prepare_content("application/json")
	http.write(sys.exec("/usr/sbin/vps000-update progress 2>/dev/null") or '{"got":0,"total":0}')
end
