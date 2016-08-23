
local headers = ngx.req.get_headers()
local method = ngx.var.request_method
local args = ngx.req.get_uri_args() or {}
local url = ngx.unescape_uri(ngx.var.uri)
local request_url = ngx.unescape_uri(ngx.var.request_uri)
local remoteIp = ngx.var.remote_addr
local lua_version


local config_dict = ngx.shared.config_dict

local cjson_safe = require "cjson.safe"
local config_base = cjson_safe.decode(config_dict:get("base")) or {}

--- 判断config_dict中模块开关是否开启
local function config_is_on(config_arg)
    if config_base[config_arg] == "on" then
        return true
    end
end

--- 取config_dict中的json数据
local function getDict_Config(Config_jsonName)
    local re = cjson_safe.decode(config_dict:get(Config_jsonName)) or {}
    return re
end

--- remath(str,re_str,options)
--- 常用二阶匹配规则
local function remath(str,re_str,options)
    if str == nil or re_str == nil or options == nil then return false end
    if options == "" then
        if str == re_str or re_str == "*" then
            return true
        end
    elseif options == "table" then
        if type(re_str) ~= "table" then return false end
        for i,v in ipairs(re_str) do
            if v == str then
                return true
            end
        end
    elseif options == "in" then --- 用于包含 查找 string.find
        local from , to = string.find(str, re_str)
        --if from ~= nil or (from == 1 and to == 0 ) then
        --当re_str=""时的情况
        if from ~= nil then
            return true
        end
    elseif options == "list" then
        if type(re_str) ~= "table" then return false end
        local re = re_str[str]
        if re == true then
            return true
        end
    else
        local from, to = ngx.re.find(str, re_str, options)
        if from ~= nil then
            return true,string.sub(str, from, to)
        end
    end
end

local function tableToString(obj)
    local lua = ""  
    local t = type(obj)  
    if t == "number" then  
        lua = lua .. obj  
    elseif t == "boolean" then  
        lua = lua .. tostring(obj)  
    elseif t == "string" then  
        lua = lua .. string.format("%q", obj)  
    elseif t == "table" then  
        lua = lua .. "{\n"  
        for k, v in pairs(obj) do  
            lua = lua .. "[" .. tableToString(k) .. "]=" .. tableToString(v) .. ",\n"  
        end  
        local metatable = getmetatable(obj)  
            if metatable ~= nil and type(metatable.__index) == "table" then  
            for k, v in pairs(metatable.__index) do  
                lua = lua .. "[" .. tableToString(k) .. "]=" .. tableToString(v) .. ",\n"  
            end  
        end  
        lua = lua .. "}"  
    elseif t == "nil" then  
        return nil  
    else  
        error("can not tableToString a " .. t .. " type.")  
    end  
    return lua  
end

local function tableTojson(obj)
    local json_text = cjson_safe.encode(obj)  
    return json_text
end

local function guid()
    local random = require "resty-random"
    return string.format('%s-%s',
        random.token(10),
        random.token(10)
    )
end

-- 设置token 并缓存3分钟
local function set_token(token)
    if token == nil then token = guid() end -- 没有值自动生成一个guid
    if token_dict:get(token) == nil then 
        token_dict:set(token,true,3*60)  --- -- 缓存3分钟 非重复插入
        return token
    else
        return set_token(nil)
    end 
end

local function ngx_find(_str)
    -- str = string.sub(str,"@ngx_time@",ngx.time())
    -- ngx.re.gsub 效率要比string.sub要好一点，参考openresty最佳实践
    _str = ngx.re.gsub(str,"@ngx_localtime@",ngx.localtime())
    -- string.find 会走jit,所以就没有用ngx模块
    -- 当前情况下，对token仅是全局替换一次，请注意
    if string.find(_str,"@token@") ~= nil then      
        str = ngx.re.gsub(_str,"@token@",set_token())
    end 
    return str
end

local function sayHtml_ext(html,ty) 
    ngx.header.content_type = "text/html"
    if html == nil then 
        ngx.say("fileorhtml is nil")
        ngx.exit(200)
    elseif type(html) == "table" then
        if ty == nil then               
            ngx.say(tableTojson(html))
            ngx.exit(200)
        else
            ngx.say(tableToString(html))
            ngx.exit(200)
        end
    else
        ngx.say(ngx_find(html))
        ngx.exit(200)
    end 
end

-- 传入 (host  连接IP  http头)
local function loc_getRealIp(_host,_headers)
    if config_is_on("realIpFrom_Mod") then
        local realipfrom = getDict_Config("realIpFrom_Mod")
        local ipfromset = realipfrom[_host]
        if type(ipfromset) ~= "table" then return remoteIp end
        if remath(remoteIp,ipfromset.ips[1],ipfromset.ips[2]) then
            local ip = _headers[ipfromset.realipset]
            if ip then
                if type(ip) == "table" then ip = ip[1] end
            else
                ip = remoteIp
            end
            return ip
        else
            return remoteIp
        end
        -- 统一使用 二阶匹配
    else
        return remoteIp
    end
end

if jit then 
    lua_version = jit.version
else 
    lua_version = _VERSION
end
local debug_tb = {
    _Openstar_version = config_base.openstar_version,
    _pid = ngx.worker.pid(),
    _worker_count =ngx.worker.count(),
    _worker_id = ngx.worker.id(),
    _ngx_configure=ngx.config.nginx_configure(),
    _ngx_prefix=ngx.config.prefix(),
    _lua_version = lua_version,
    _ngx_lua_version = ngx.config.ngx_lua_version,
    _url = url,
    _method = method,
    _request_url = request_url,
    _args = args,
    _headers = headers,
    _schema = ngx.var.schema,
    _var_host = ngx.var.host,
    _hostname = ngx.var.hostname,
    _servername = ngx.var.server_name or "unknownserver",
    _remoteIp = remoteIp,
    _ip = loc_getRealIp(host,headers),
    _filename = ngx.var.request_filename,
    _query_string = ngx.unescape_uri(ngx.var.query_string),
    _nowtime=ngx.var.time_local or "time error",
    _remote_addr = ngx.var.remote_addr,
    _remote_port = ngx.var.remote_port,
    _remote_user = ngx.var.remote_user,
    _remote_passwd = ngx.var.remote_passwd,
    _content_type = ngx.var.content_type,
    _content_length = ngx.var.content_length,
    _nowstatus=ngx.var.status or "-",
    _request=ngx.var.request or "-",
    _bodybyte = ngx.var.body_bytes_sent or "-"  
}

if method == "GET" then
    sayHtml_ext(debug_tb)
elseif method == "POST" then
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    if not data then 
        local datafile = ngx.req.get_body_file()
        if datafile then
            local fh, err = io.open(datafile, "r")
            if fh then
                fh:seek("set")
                local body_data = fh:read("*a")
                fh:close()
                data = body_data
            end
        end
    end
    debug_tb["_PostData"] = data
    sayHtml_ext(debug_tb)
else
    ngx.say("method error")
end