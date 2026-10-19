-- Run with Kindle's LuaJIT: kernel waits must wake immediately on input.
require('setupkoenv');require('ffi/posix_h')
local ffi=require('ffi')
ffi.cdef[[int pipe(int[2]); int fork(void); void _exit(int); int waitpid(int,int*,int);]]
local function now()
 local t=ffi.new('struct timespec[1]');ffi.C.clock_gettime(1,t)
 return tonumber(t[0].tv_sec)+tonumber(t[0].tv_nsec)/1e9
end
local fds=ffi.new('int[2]');assert(ffi.C.pipe(fds)==0)
local input=ffi.new('struct pollfd[1]');input[0].fd=fds[0];input[0].events=ffi.C.POLLIN
local start=now();assert(ffi.C.poll(input,1,100)==0)
assert(now()-start>=0.09,'Idle wait must block instead of spinning')
local pid=ffi.C.fork();assert(pid>=0)
if pid==0 then
 ffi.C.usleep(50000);ffi.C.write(fds[1],'x',1);ffi.C._exit(0)
end
start=now();assert(ffi.C.poll(input,1,1000)==1)
local elapsed=now()-start
assert(elapsed<0.4,'Input must interrupt the one-second idle wait')
local byte=ffi.new('char[1]');assert(ffi.C.read(fds[0],byte,1)==1 and byte[0]==120)
ffi.C.close(fds[0]);ffi.C.close(fds[1]);assert(ffi.C.waitpid(pid,nil,0)==pid)
print(string.format('PASS: idle blocks; input interrupts one-second wait in %.3fs',elapsed))
