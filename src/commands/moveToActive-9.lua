--[[
  Move next job to be processed to active, lock it and fetch its data. The job
  may be delayed, in that case we need to move it to the delayed set instead.

  This operation guarantees that the worker owns the job during the lock
  expiration time. The worker is responsible of keeping the lock fresh
  so that no other worker picks this job again.

  Input:
      KEYS[1] wait key
      KEYS[2] active key
      KEYS[3] priority key
      KEYS[4] stream events key
      KEYS[5] stalled key

      -- Rate limiting
      KEYS[6] rate limiter key
      KEYS[7] delayed key

      -- Promote delayed jobs
      KEYS[8] paused key
      KEYS[9] meta key

      -- Arguments
      ARGV[1] key prefix
      ARGV[2] timestamp
      ARGV[3] optional job ID
      ARGV[4] opts

      opts - token - lock token
      opts - lockDuration
      opts - limiter
]]
local jobId
local rcall = redis.call

-- Includes
--- @include "includes/moveJobFromWaitToActive"
--- @include "includes/getNextDelayedTimestamp"
--- @include "includes/promoteDelayedJobs"

-- Check if there are delayed jobs that we can move to wait.
promoteDelayedJobs(KEYS[7], KEYS[1], KEYS[3], KEYS[8], KEYS[9], KEYS[4], ARGV[1], ARGV[2])

if (ARGV[3] ~= "") then
    jobId = ARGV[3]
    -- clean stalled key
    rcall("SREM", KEYS[5], jobId)
else
    -- no job ID, try non-blocking move from wait to active
    jobId = rcall("RPOPLPUSH", KEYS[1], KEYS[2])
end

-- If jobId is special ID 0, then there is no job to process
if jobId == "0" then
    rcall("LREM", KEYS[2], 1, 0)
elseif jobId then
    local opts = cmsgpack.unpack(ARGV[4])
    -- this script is not really moving, it is preparing the job for processing
    return moveJobFromWaitToActive(KEYS, ARGV[1], jobId, ARGV[2], opts)
end

-- Return the timestamp for the next delayed job if any.
local nextTimestamp = getNextDelayedTimestamp(KEYS[7])
if (nextTimestamp ~= nil) then
    return nextTimestamp - tonumber(ARGV[2])
end
