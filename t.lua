a = {
	{ v = 3, t = "a"},
	{ v = 7, t = "b"},
	{ v = 1, t = "c"},
	{ v = 5, t = "d"}
}

b = {}

for i, v in pairs(a) do
	b[i] = {s=nil, p=v}
end

function compVal(v1, v2)
	if v1.p.v < v2.p.v then return true
	else return false
	end
end

function printall()
	print("=======")
	for _,v in pairs(a) do
		print(v.t, " - ", v.v)
	end

	print("-------")

	for _,v in pairs(b) do
		print(v.p.t, " - ", v.p.v)
	end
end

table.sort(b, compVal)

printall()

for _,v in pairs(b) do
	v.p.v = v.p.v + 1
end

printall()

function test1(...)
	for i=1,select("#", ...) do
		print(tostring(select(i,...)))
	end
end

function test(...)
	test1(...)
end

test(1, 2, "asd", 3)

DEFAULT_CHAT_FRAME = {}
function DEFAULT_CHAT_FRAME:AddMessage(...)
	print("Chat: ", ...)
end

DEFAULT_CHAT_FRAME:AddMessage("test")

