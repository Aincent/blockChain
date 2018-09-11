---------------------Global functon class ---------------------------------------------------
--Parameters:   super               -- The super class
--              autoConstructSuper   -- If it is true, it will call super ctor automatic,when
--                                      new a class obj. Vice versa.
--Return    :   return an new class type
--Note      :   This function make single inheritance possible.
---------------------------------------------------------------------------------------------

---
-- 用于定义一个类.
--
-- @param #table super 父类。如果不指定，则表示不继承任何类，如果指定，则该指定的对象也必须是使用class()函数定义的类。
-- @param #boolean autoConstructSuper 是否自动调用父类构造函数，默认为true。如果指定为false，若不在ctor()中手动调用super()函数则不会执行父类的构造函数。
-- @return #table class 返回定义的类。
-- @usage
function class(super, autoConstructSuper)
    local classType = {};
    classType.autoConstructSuper = autoConstructSuper or (autoConstructSuper == nil);

    if super then
        classType.super = super;
        local mt = getmetatable(super);
        setmetatable(classType, { __index = super; __newindex = mt and mt.__newindex;});
    else
        classType.setDelegate = function(self,delegate)
            self.m_delegate = delegate;
        end
    end
    return classType;
end

---------------------Global functon super ----------------------------------------------
--Parameters:   obj         -- The current class which not contruct completely.
--              ...         -- The super class ctor params.
--Return    :   return an class obj.
--Note      :   This function should be called when newClass = class(super,false).
-----------------------------------------------------------------------------------------

---
-- 手动调用父类的构造函数.
-- 只有当定义类时采用class(super,false)的调用方式时才可以调用此方法，若此时不手动调用则不会执行父类的构造函数。
-- **只能在子类的构造函数中调用。**
-- @param #table obj 类的实例。
-- @param ... 父类构造函数需要传入的参数。
function super(obj, ...)
    do
        local create;
        create =
            function(c, ...)
                if c.super and c.autoConstructSuper then
                create(c.super, ...);
            end
            if rawget(c,"ctor") then
                obj.currentSuper = c.super;
                c.ctor(obj, ...);
            end
        end
        create(obj.currentSuper, ...);
    end
end

---------------------Global functon new -------------------------------------------------
--Parameters: 	classType -- Table(As Class in C++)
-- 				...		   -- All other parameters requisted in constructor
--Return 	:   return an object
--Note		:	This function is defined to simulate C++ new function.
--				First it called the constructor of base class then to be derived class's.
-----------------------------------------------------------------------------------------

---
-- 创建一个类的实例.
-- 调用此方法时会按照类的继承顺序，自上而下调用每个类的构造函数，并返回新创建的实例。
--
-- @param #table classType 类名。  使用class()返回的类。
-- @param ... 构造函数需要传入的参数。
-- @return #table obj 新创建的实例。
function new(classType, ...)
    local obj = {};
    local mt = getmetatable(classType);
    setmetatable(obj, { __index = classType; __newindex = mt and mt.__newindex;});
    do
        local create;
        create =
            function(c, ...)
            if c.super and c.autoConstructSuper then
                create(c.super, ...);
            end
            if rawget(c,"ctor") then
                obj.currentSuper = c.super;
                c.ctor(obj, ...);
            end
        end
        create(classType, ...);
    end
    obj.currentSuper = nil;
    return obj;
end

---------------------Global functon delete ----------------------------------------------
--Parameters: 	obj -- the object to be deleted
--Return 	:   no return
--Note		:	This function is defined to simulate C++ delete function.
--				First it called the destructor of derived class then to be base class's.
-----------------------------------------------------------------------------------------

---
-- 删除某个实例.
-- 类似c++里的delete ，会按照继承顺序，依次自下而上调用每个类的析构方法。
--
-- **需要留意的是，删除此实例后，lua里该对象的引用(obj)依然有效，再次使用可能会发生无法预知的意外。**
--
-- @param #table obj 需要删除的实例。
function delete(obj)
    do
        local destory =
            function(c)
                while c do
                    if rawget(c,"dtor") then
                    c.dtor(obj);
                end

                c = getmetatable(c);
                c = c and c.__index;
            end
        end
        destory(obj);
    end
end

---------------------Global functon delete ----------------------------------------------
--Parameters:   class       -- The class type to add property
--              varName     -- The class member name to be get or set
--              propName    -- The name to be added after get or set to organize a function name.
--              createGetter-- if need getter, true,otherwise false.
--              createSetter-- if need setter, true,otherwise false.
--Return    :   no return
--Note      :   This function is going to add get[PropName] / set[PropName] to [class].
-----------------------------------------------------------------------------------------

---
-- 为类定义一个property (java里的getter/setter).
-- 会自动为类生成getter/setter方法。
--
-- @param #table class 使用class()方法定义的类。
-- @param #string varName 类里的成员变量名。
-- @param #string propName 属性名，也就是生成的方法setXX/getXX里的'XX'。
-- @param #boolean createGetter 是否生成getter。
-- @param #boolean createSetter 是否生成setter。<br>
-- 如果createGetter不为false或nil，则给class生成一个get#propName()方法,可以获取class的varName的值。<br>
-- 如果createSetter不为false或nil，则给class生成一个set#propName(Value)方法，可以设置class的varName为Value。
function property(class, varName, propName, createGetter, createSetter)
    createGetter = createGetter or (createGetter == nil);
    createSetter = createSetter or (createSetter == nil);

    if createGetter then
        class[string.format("get%s",propName)] = function(self)
            return self[varName];
        end
    end

    if createSetter then
        class[string.format("set%s",propName)] = function(self,var)
            self[varName] = var;
        end
    end
end

---------------------Global functon delete ----------------------------------------------
--Parameters:   obj         -- A class object
--              classType   -- A class
--Return    :   return true, if the obj is a object of the classType or a object of the
--              classType's derive class. otherwise ,return false;
-----------------------------------------------------------------------------------------

---
-- 判断一个对象是否是某个类(包括其父类)的实例.
-- 类似java里的instanceof。
--
-- @param obj 需要判断的对象。
-- @param classType 使用class()方法定义的类。
-- @return #boolean 若obj是classType的实例，则返回true；否则，返回false。
function typeof(obj, classType)
    if type(obj) ~= type(table) or type(classType) ~= type(table) then
        return type(obj) == type(classType);
    end

    while obj do
        if obj == classType then
            return true;
        end
        obj = getmetatable(obj) and getmetatable(obj).__index;
    end
    return false;
end

---------------------Global functon delete ----------------------------------------------
--Parameters:   obj         -- A class object
--Return    :   return the object's type class.
-----------------------------------------------------------------------------------------

---
-- 通过一个对象反向得到此对象的类.
--
-- @param obj 对象。
-- @return class 此对象的类。
-- @return #nil 如果obj不是某个类的对象，则返回nil。
function decltype(obj)
    if type(obj) ~= type(table) or obj.autoConstructSuper == nil then
        --error("Not a class obj");
        return nil;
    end
    if rawget(obj,"autoConstructSuper") ~= nil then
        --error("It is a class but not a class obj");
        return nil;
    end
    local class = getmetatable(obj) and getmetatable(obj).__index;
    if not class then
        --error("No class reference");
        return nil;
    end
    return class;
end

function clone(object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for key, value in pairs(object) do
            new_table[_copy(key)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

function table.merge(tab1, tab2)
    assert(tab1 and tab2)
    for k, v in pairs(tab2) do
        if nil ~= tab2[k] then
            tab1[k] = tab2[k]
        end
    end
end

-- 分隔字符串
function string.split(str, sep)  
    local sep, fields = sep or "\t", {}  
    local pattern = string.format("([^%s]+)", sep)  
    string.gsub(str, pattern, function(c) fields[#fields + 1] = c end)  
    return fields
end

function isTable(object)
    if object and type(object) == "table" then
        return true
    end
    return false
end

function isString(object)
    if object and type(object) == "string" then
        return true
    end
    return false
end

-- local char = string.char

-- local function tail(n, k)
--     local u, r = ''
--     for i = 1, k do
--         n, r = math.floor(n / 0x40), n % 0x40
--         u = char(r + 0x80) .. u
--     end
--     return u, n
-- end

-- function to_utf8(a)
--     local n, r, u = string.byte(string.sub(a, 1, 1))
--     if n < 0x80 then                        -- 1 byte  
--         return char(n)
--     elseif n < 0x800 then                   -- 2 byte  
--         u, n = tail(n, 1)
--         return char(n + 0xc0) .. u
--     elseif n < 0x10000 then                 -- 3 byte  
--         u, n = tail(n, 2)
--         return char(n + 0xe0) .. u
--     elseif n < 0x200000 then                -- 4 byte  
--         u, n = tail(n, 3)
--         return char(n + 0xf0) .. u
--     elseif n < 0x4000000 then               -- 5 byte  
--         u, n = tail(n, 4)
--         return char(n + 0xf8) .. u
--     else                                  -- 6 byte  
--         u, n = tail(n, 5)
--         return char(n + 0xfc) .. u
--     end  
-- end


function onGetNowDataLastTime(data)
    return os.time({year = data.year, month = data.month, day = data.day, hour = 23, min = 59})
end

function string.utf8len(input)
    local len  = string.len(input)
    local left = len
    local cnt  = 0
    local arr  = {0, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc}
    while left ~= 0 do
        local tmp = string.byte(input, -left)
        local i   = #arr
        while arr[i] do
            if tmp >= arr[i] then
                left = left - i
                break
            end
            i = i - 1
        end
        cnt = cnt + 1
    end
    return cnt
end

local function chsize(char)
    if not char then
        print("not char")
        return 0
    elseif char > 239 then
        return 4
    elseif char > 223 then
        return 3
    elseif char > 127 then
        return 2
    else
        return 1
    end
end

function string.utf8sub(str, startChar, numChars)
    local startIndex = 1
    while startChar > 1 do
        local char = string.byte(str, startIndex)
        startIndex = startIndex + chsize(char)
        startChar = startChar - 1
    end

    local currentIndex = startIndex

    while numChars > 0 and currentIndex <= #str do
        local char = string.byte(str, currentIndex)
        currentIndex = currentIndex + chsize(char)
        numChars = numChars -1
    end
    return str:sub(startIndex, currentIndex - 1)
end

function onGetNotEmojiName(newName)
    local pName = ""
    local len = string.utf8len(newName)--utf8解码长度
    -- Log.d("1111111", "len[%s]", len)
    for i = 1, len do
        local isEmoji = false
        local str = string.utf8sub(newName, i, 1)
        -- Log.d("1111111", "str[%s]", str)
        local byteLen = string.len(str)--编码占多少字节
        local value, value1, value2, value3 = string.byte(str, 1, byteLen)
        -- if value1 then value = value * 0x100 + value1 end
        -- if value2 then value = value * 0x100 + value2 end
        -- if value3 then value = value * 0x100 + value3 end
        -- Log.d("1111111", "byteLen[%s] value[%x] value1[%s] value2[%s] value3[%s]", byteLen, value, value1, value2, value3)

        -- if value >= 0x10000 or (value >= 0xE000 and value <= 0xFFFD) or (value >= 0x20 and value <= 0xD7FF) 
        --     or (value == 0xD) or (value == 0xA) or (value == 0x9) or (value == 0x0) then
        -- -- if byteLen > 3 then--超过三个字节的必须是emoji字符啊
        --     isEmoji = true
        -- end
        
        if byteLen > 3 then
            isEmoji = true
        end

        -- if value >= 240 then
        --     isEmoji = true
        -- end

        -- if string.find(str, "[\\ud800\\udc00-\\udbff\\udfff\\ud800-\\udfff]") then
        --     isEmoji = true
        -- end

        -- if byteLen == 3 then
        --     if string.find(str, "[\226][\132-\173]") or string.find(str, "[\227][\128\138]") then
        --         isEmoji = true--过滤部分三个字节表示的emoji字符，可能是早期的符号，用的还是三字节，坑。。。这里不保证完全正确，可能会过滤部分中文字。。。
        --     end
        -- end

        -- if byteLen == 1 then
        --     local ox = string.byte(str)
        --     if (33 <= ox and 47 >= ox) or (58 <= ox and 64 >= ox) or (91 <= ox and 96 >= ox) or (123 <= ox and 126 >= ox) or (str == "　") then
        --         isEmoji = true--过滤ASCII字符中的部分标点，这里排除了空格，用编码来过滤有很好的扩展性，如果是标点可以直接用%p匹配。
        --     end
        -- end

        if not isEmoji then
            pName = pName..str
        end
    end
    return pName
end

function onGetServerConfigFile(pGameCode)
    return string.format("config/%s/serverConfig", pGameCode)
end

function onGetTableByJson(pJsonStr)
    if not pJsonStr or type(pJsonStr) ~= "string" then return end
    local json = require("cjson")
    local pStatus, pTable = pcall(json.decode, pJsonStr)
    if not pStatus or type(pTable) ~= "table" then return end
    return pTable
end

function onPerformSelector(pObject, pSelector, ...)
    if pObject and pSelector then
        return true, pSelector(pObject, ...)
    end
    return false, nil
end