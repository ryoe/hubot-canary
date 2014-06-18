# Description:
#   A hubot script to query the canary.io API.
#
# Dependencies:
#   "moment": "^2.6.0"
#
# Commands:
#   hubot canary mon <check-id> - start monitoring <check-id>. every 5 seconds send hubot canary summary <check-id>
#   hubot canary mon stop <check-id> - stop monitoring <check-id>
#   hubot canary mon stop all - stop all monitoring
#   hubot canary incident <check-id> - same as "hubot canary mon <check-id>" but only display 5xx http status and non-zero exit status (failures)
#   hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most http status 5xx, most failed checks (non-zero exit_status), slowest avg, slowest single call, slowest total time
#   hubot canary check - get the list of URLs which have measurements taken by canary.io 
#   hubot canary check <filter> - get filtered list of checked URLs. Coming soon!
#   hubot canary check reset - clear the hubot canary check cache, then get again
#   hubot canary watch <check-id> - get url to open <check-id> for real-time monitoring in http://watch.canary.io
#   hubot canary measure <check-id> - get url to download measurements of <check-id> for last 10 seconds
#   hubot canary measure <check-id> <num-seconds> - get url to download measurements of <check-id> for last <num-seconds> seconds
#   hubot canary help - get list of hubot canary commands
#
# Configuration:
#   HUBOT_CANARY_NOTIFY_ROOM - chat room where GET/POST incident messages will be sent
#
# URLS:
#   GET /hubot/incident?checkId=<check-id>[&room=<room>&type=<start|stop>]
#   POST /hubot/incident
#     checkId = <check-id>
#     [room = <room>]
#     [type = <start|stop>]
#
# Notes:
#   Have fun with it.
#
# Author:
#   ryoe
moment = require 'moment'
querystring = require 'querystring'

MAX_RANGE = 300
INCIDENT_RANGE = 180
DEFAULT_RANGE = 10
monitors = []
monInterval = null
checks = null
help = null
rbt = null

module.exports = (robot) ->
  rbt = robot
  help = new Help
  checks = new Checks
  initChecks()
  envVarWarn()

  robot.respond /\bcanary\b/i, (msg) ->
    text = msg.message.text

    if checks.length() == 0 #sanity check
      getChecks msg, true, (err, data) ->
        processCanaryCmd msg, text if not err
    else
      processCanaryCmd msg, text

  robot.error (err, msg) ->
    console.log err
    robot.logger.error "DOES NOT COMPUTE"

    if msg?
      msg.reply "DOES NOT COMPUTE"

  robot.on 'hubot-canary:msgEvent', (data) ->
    console.log data.message
    if data.user and data.user.reply_to
      room = data.user.reply_to
    else if data.envelope and data.envelope.user and data.envelope.user.reply_to
      room = data.envelope.user.reply_to
    else if data.room
      room = data.room
    else 
      room = process.env.HUBOT_CANARY_NOTIFY_ROOM
    dataMsg = data.message || 'It is important that you know, no was message received!'
    console.log room
    robot.messageRoom room, "#{dataMsg}"
    envVarWarn()

  robot.router.post '/hubot/incident', (req, res) ->
    data = req.body
    cid  = data.checkId
    type = data.type || 'start'
    room = data.room || process.env.HUBOT_CANARY_NOTIFY_ROOM || null
    roomWarn = if (process.env.HUBOT_CANARY_NOTIFY_ROOM || null)? then '' else '\n* HUBOT_CANARY_NOTIFY_ROOM environment variable not set'

    user = {}
    user.room = room

    #call existing xxxMonitor functions...
    if 'stop'.localeCompare(type.toLowerCase()) is 0
      stopMonitor { message: { text: "mon stop #{cid}"}}
    else
      setupMonitor { room: user.room }, cid, false
    res.end "POST incident:\n* checkId: #{cid}\n* type: #{type}\n* room: #{room}#{roomWarn}"
    envVarWarn()

  robot.router.get '/hubot/incident', (req, res) ->
    q    = querystring.parse req._parsedUrl.query
    cid  = q.checkId
    type = q.type || 'start'
    room = q.room || process.env.HUBOT_CANARY_NOTIFY_ROOM || null
    roomWarn = if (process.env.HUBOT_CANARY_NOTIFY_ROOM || null)? then '' else '\n* HUBOT_CANARY_NOTIFY_ROOM environment variable not set'

    user = {}
    user.room = room

    #call existing xxxMonitor functions...
    if 'stop'.localeCompare(type.toLowerCase()) is 0
      stopMonitor { message: { text: "mon stop #{cid}"}}
    else
      setupMonitor { room: user.room }, cid, false
    res.end "GET incident:\n* checkId: #{cid}\n* type: #{type}\n* room: #{room}#{roomWarn}"
    envVarWarn()

envVarWarn = ->
  rm = process.env.HUBOT_CANARY_NOTIFY_ROOM || null
  unless rm?
    rbt.logger.warning 'HUBOT_CANARY_NOTIFY_ROOM environment variable not set'

initChecks = ->
  msg =
    message: 
      text: 'check'
  getChecks msg, true, null

processCanaryCmd = (msg, text) ->
  if text.match(/\bcheck(s)?\b/i)
    getChecks msg, false, null
  else if text.match(/\bhelp\b/i)
    getHelp msg
  else if text.match(/\bmeasure(ment)?(s)?\b/i)
    getMeasurements msg
  else if text.match(/\bsummary?(s)?\b/i)
    getSummary msg
  else if text.match(/\bmon\b/i)
    startMonitor msg
  else if text.match(/\bincident\b/i)
    startIncident msg
  else if text.match(/\bwatch\b/i)
    getWatchUrl msg
  else
    getUnknownCommand msg

apiCall = (msg, url, cb) ->
  console.log url
  rbt.http(url)
    .headers(Accept: 'application/json')
    .get() (err, res, body) ->
      if err
        cb err, ['error']
        return

      if res.statusCode == 200
        cb null, body
      else if res.statusCode == 301
        # get url from body
        # assumes body is <a href="redirUrl">Some text</a>
        matches = body.match(/href="(.*)"/i)
        redirUrl = matches[1]
        apiCall msg, redirUrl, cb
      else
        cb res.statusCode, body

getChecks = (msg, silent, cb) ->
  text = msg.message.text

  if text.match(/\breset\b/i)
    checks.reset()

  if checks.length() > 0
    #use cached checks
    displayChecks msg if not silent
    cb null, null if cb
    return

  apiCall msg, checks.url(), (err, body) ->
    if err
      console.log err
      emitMessage msg, body
      return

    data = JSON.parse body
    checks.load data
    displayChecks msg if not silent
    cb null, null if cb

displayChecks = (msg) ->
  emitMessage msg, checks.toString()

getWatchUrl = (msg) ->
  text = msg.message.text
  matches = text.match(/\bwatch\b(\s*)?(\S*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2] || null
  w = new Watch(checkId)
  url = w.url()
  if not checkId?
    emitMessage msg, "WARN: No <check-id> provided.\n#{url}"
    return

  return if not isValidCheckId msg, checkId
  emitMessage msg, "#{url}"

getMeasurements = (msg) ->
  text = msg.message.text
  matches = text.match(/\bmeasure(ment)?(s)?\b \b(\S*)+\b(\s*)?(\d*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[3]
  return if not isValidCheckId msg, checkId

  range = matches[5]
  m = new Measurements checkId, range, false, false
  url = m.url()
  emitMessage msg, "#{url}"

stopMonitor = (msg) ->
  text = msg.message.text
  matches = text.match(/\bmon\b stop(\s*)+\b(all|\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2]
  if checkId.localeCompare('all') != 0
    return if not isValidCheckId msg, checkId
  else
    monitors = []

  idx = monitors.indexOf checkId
  monitors.splice idx, 1 if idx > -1
  if monitors.length == 0
    clearInterval monInterval
    monInterval = null
    emitMessage msg, 'All monitors cleared.'

startIncident = (msg) ->
  text = msg.message.text
  matches = text.match(/\bincident\b(\s*)+(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2]
  setupMonitor msg, checkId, false

startMonitor = (msg) ->
  text = msg.message.text
  if text.match(/\bmon\b stop/i)
    stopMonitor msg
    return

  matches = text.match(/\bmon\b(\s*)+(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2]
  setupMonitor msg, checkId, true

setupMonitor = (msg, checkId, isMon) ->
  return if not isValidCheckId msg, checkId
  idx = monitors.indexOf checkId
  monitors.push checkId if idx < 0
  delay = 5000
  if not monInterval?
    processMonitors msg #show results now!
    monInterval = setInterval processMonitors, delay, msg, isMon

processMonitors = (msg, isMon) ->
  range = if isMon then MAX_RANGE else INCIDENT_RANGE
  getSummaryData msg, checkId, range, true, isMon for checkId in monitors

getSummary = (msg) ->
  text = msg.message.text
  matches = text.match(/\bsummary\b(\s*)+\b(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2]
  return if not isValidCheckId msg, checkId
  range = MAX_RANGE
  getSummaryData msg, checkId, range, false, true

getSummaryData = (msg, checkId, range, totalOnly, isMon) ->
  m = new Measurements checkId, range, totalOnly, isMon
  url = m.url()

  apiCall msg, url, (err, body) ->
    if err
      console.log err
      emitMessage msg, body
      return

    data = JSON.parse body
    m.load data
    emitMessage msg, m.toString()

getHelp = (msg) ->
  emitMessage msg, help.toString()

getUnknownCommand = (msg) ->
  emitMessage msg, "Unable to comply. Unknown command #{msg.message.text}\nTry 'hubot canary help'."

isValidCheckId = (msg, checkId) ->
  return true if checks.isValid(checkId)
  emitMessage msg, "#{checkId} is not a current check-id.\nTry 'hubot canary check' for the current cached list.\nOr try 'hubot canary reset' to clear the cache and retrieve new list."
  return false

emitMessage = (msg, message) ->
  mess = msg.message || {}
  usr  = mess.user || null
  env  = mess.envelope || null
  rm   = msg.room || mess.room || null

  data = 
    user:     usr || null
    envelope: env || null
    room:     rm  || null
    message:  "#{message}"
  console.log data
  rbt.emit 'hubot-canary:msgEvent', data

class Monitor
  constructor: ->

class Watch
  constructor: (checkId) ->
    @watchCheckId = checkId || null
    @watchUrl = 'http://watch.canary.io/'
    @watchReplaceUrl = 'http://watch.canary.io/#/checks/XXX/measurements'
    @xxxRegEx = new RegExp 'XXX', 'i'

  url: ->
    if not @watchCheckId?
      return @watchUrl
    @watchReplaceUrl.replace @xxxRegEx, @watchCheckId

class Checks
  constructor: ->
    @checks = []
    @map = {}
    @checksUrl = 'http://checks.canary.io'

  isValid: (checkId) ->
    c = @map[checkId] || null
    c?

  length: ->
    @checks.length

  get: (api) ->

  load: (list) ->
    @reset()
    @checks = list
    @map[c.id] = c for c in @checks

  reset: ->
    @checks = []
    @map = {}

  toString: ->
    deets = []
    deets.push "id: #{c.id} => url: #{c.url}" for c in @checks
    deets.join '\n'

  url: ->
    @checksUrl

class Help
  constructor: ->
    @help = [
      'hubot canary mon <check-id> - start monitoring <check-id>. every 5 seconds send hubot canary summary <check-id>'
      'hubot canary mon stop <check-id> - stop monitoring <check-id>'
      'hubot canary mon stop all - stop all monitoring'
      'hubot canary incident <check-id> - same as "hubot canary mon <check-id>" but only display 5xx http status and non-zero exit status (failures)'
      'hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most http status 5xx, most failed checks (non-zero exit_status), slowest avg, slowest single call, slowest total time'
      'hubot canary check - get the list of URLs which have measurements taken by canary.io'
      'hubot canary check <filter> - get filtered list of checked URLs. Coming soon!'
      'hubot canary check reset - clear the hubot canary check cache, then get again'
      'hubot canary watch <check-id> - get url to open <check-id> for real-time monitoring in http://watch.canary.io'
      'hubot canary measure <check-id> - get url to download measurements of <check-id> for last 10 seconds'
      'hubot canary measure <check-id> <num-seconds> - get url to download measurements of <check-id> for last <num-seconds> seconds'
      'hubot canary help - get list of hubot canary commands'
    ]

  toString: ->
    @help.join '\n'

class Measurements
  constructor: (checkId, range, totalOnly, isMon) ->
    range = range || DEFAULT_RANGE
    range = MAX_RANGE if range > MAX_RANGE
    range = DEFAULT_RANGE if range <= 0

    @measurementCheckId = checkId
    @measurementRange = range
    @isTotalOnly = totalOnly || false
    @isMonitor = isMon || false
    @measurements = []
    @measurementsApiUrl = 'https://measurements.canary.io' #the future
    @measurementsReplaceUrl = 'https://api.canary.io/checks/XXX/measurements?range=YYY'
    @xxxRegEx = new RegExp 'XXX', 'i'
    @yyyRegEx = new RegExp 'YYY', 'i'
    @measurementsUrl = @measurementsReplaceUrl.replace @xxxRegEx, @measurementCheckId
    @measurementsUrl = @measurementsUrl.replace @yyyRegEx, @measurementRange

  length: ->
    @measurements.length

  load: (list) ->
    @measurements = list

  toString: ->
    if @measurements.length is 0
      return "Zero measurements found for #{@measurementCheckId} in last #{@measurementRange} seconds."

    if not @isMonitor and @isTotalOnly
      @displayChart()
    else
      @displaySummary()

  displayChart: ->
    @measurements.reverse(); #oldest first
    len = @measurements.length
    unixStart = @measurements[0].t
    unixEnd = @measurements[len-1].t
    startDate = moment.unix(unixStart)
    endDate = moment.unix(unixEnd)
    resSec = 5 #resolution seconds (aka bucket size)
    threshold = unixStart + resSec
    failed = []
    locs5xx = []
    timeBuckets = []
    bucketLocs = []
    i = 0
    while i < len
      loc = @measurements[i]
      if loc.exit_status isnt 0
        failed.push loc
      else
        bucketLocs.push loc
        locs5xx.push loc  unless loc.http_status < 500

      if loc.t is threshold
        timeBuckets.push { locs: bucketLocs, failed: failed, locs5xx: locs5xx }
        bucketLocs = []
        failed = []
        locs5xx = [];
        threshold += resSec
      i++

    timeBuckets.push { locs: bucketLocs, failed: failed, locs5xx: locs5xx } #add the final bucket...
    success = []
    failed = []
    locs5xx = []
    bucketLocs = []
    len = timeBuckets.length
    i = 0
    while i < len
      bucket = timeBuckets[i]
      console.log bucket
      success.push bucket.locs.length
      failed.push bucket.failed.length
      locs5xx.push bucket.locs5xx.length
      i++

    chdata = []
    #chdata.push success.join(',')
    chdata.push failed.join(',')
    #chdata.push locs5xx.join(',')
    chdata.push success.join(',') #use "success" to fake up a bunch of 5xx status codes

    tempDate = startDate.clone()
    date30sIntervals = []
    date30sIntervals.push tempDate.format('HH:mm:ss')
    i = 0
    while i < 6
      date30sIntervals.push tempDate.add('s', 30).format('HH:mm:ss')
      i++

    chartArgs = []
    datePart = []
    datePart.push startDate.format('MMM+D,+YYYY')
    datePart.push startDate.format('HH:mm:ss')
    datePart.push 'to'
    datePart.push endDate.format('HH:mm:ss+(ZZ)')
    chartArgs.push 'chtt=' + @measurementCheckId+ '|' + datePart.join('+')
    chartArgs.push 'chts=000000,14'
    chartArgs.push 'chs=750x400'
    chartArgs.push 'cht=bvg'
    chartArgs.push 'chdl=Failed|Status+5xx'
    chartArgs.push 'chdlp=t'
    chartArgs.push 'chco=000000,FF6666'
    chartArgs.push 'chds=a'
    chartArgs.push 'chbh=6,1,6'
    chartArgs.push 'chxt=x,y'
    chartArgs.push 'chxl=0:|' + date30sIntervals.join('|')
    chartArgs.push 'chxp=0,0'
    chartArgs.push 'chd=t:' + chdata.join('|')

    url = 'http://chart.googleapis.com/chart?' + chartArgs.join('&') + '#.png'

  displaySummary: ->
    locMap = {}
    i = 0
    len = @measurements.length

    while i < len
      loc = @measurements[i]
      unless locMap[loc.location]
        locMap[loc.location] =
          loc: loc.location
          max: loc.total_time
          min: loc.total_time
          total: loc.total_time
          avg: 0
          fail: 0
          success: 0
          http1xx: 0
          http2xx: 0
          http3xx: 0
          http4xx: 0
          http5xx: 0
      if loc.exit_status is 0
        locMap[loc.location].success++
        locMap[loc.location].total += loc.total_time
        locMap[loc.location].avg = locMap[loc.location].total/locMap[loc.location].success
      else
        locMap[loc.location].fail++
      if loc.total_time > locMap[loc.location].max
        locMap[loc.location].max = loc.total_time
      else locMap[loc.location].min = loc.total_time  if loc.total_time < locMap[loc.location].min
      httpStatus = loc.http_status
      if httpStatus >= 200 and httpStatus < 300
        locMap[loc.location].http2xx++
      else if httpStatus >= 300 and httpStatus < 400
        locMap[loc.location].http3xx++
      else if httpStatus >= 400 and httpStatus < 500
        locMap[loc.location].http4xx++
      else if httpStatus >= 500
        locMap[loc.location].http5xx++
      else
        locMap[loc.location].http1xx++
      i++

    locs = []
    for prop of locMap
      locs.push locMap[prop]
    tot =
      loc: 'Total'
      max: 0
      min: 100
      total: 0
      avg: 0
      fail: 0
      success: 0
      http1xx: 0
      http2xx: 0
      http3xx: 0
      http4xx: 0
      http5xx: 0
    for loc in locs
      tot.max = loc.max if loc.max > tot.max
      tot.min = loc.min if loc.min < tot.min
      tot.total += loc.total
      tot.fail += loc.fail
      tot.success += loc.success
      tot.http1xx += loc.http1xx
      tot.http2xx += loc.http2xx
      tot.http3xx += loc.http3xx
      tot.http4xx += loc.http4xx
      tot.http5xx += loc.http5xx

    tot.avg = tot.total/tot.success
    locs.sort (a, b) ->
      #most http status 5xx
      return b.http5xx- a.http5xx  if a.http5xx isnt b.http5xx
      #then most failed checks
      return b.fail - a.fail  if a.fail isnt b.fail
      #then slowest avg
      return b.avg - a.avg  if a.avg isnt b.avg
      #then slowest call
      return b.max - a.max  if a.max isnt b.max
      #then slowest total
      b.total - a.total

    if @isTotalOnly
      locs = [tot]
    else locs.unshift tot
    startDate = moment.unix(@measurements[len-1].t)
    endDate = moment.unix(@measurements[0].t)
    dateRange = startDate.format("MMM D, YYYY") + " " + startDate.format("HH:mm:ss") + " to " + endDate.format("HH:mm:ss (UTC ZZ)")
    chk = @measurements[0].check

    deets = []
    deets.push 'Summary for '+ chk.url
    deets.push dateRange
    deets.push 'Total measurements: ' + len
    deets.push '--------------------'
    deets.push @summaryDetails s for s in locs

    deets.join '\n'

  summaryDetails: (locSummary) ->
    deets = []
    deets.push locSummary.loc.toUpperCase()
    deets.push "  failed: #{locSummary.fail}" if locSummary.fail isnt 0
    deets.push "  5xx: #{locSummary.http5xx}" if locSummary.http5xx isnt 0
    deets.push "  4xx: #{locSummary.http4xx}" if @isMonitor and locSummary.http4xx isnt 0
    deets.push "  3xx: #{locSummary.http3xx}" if @isMonitor and locSummary.http3xx isnt 0
    deets.push "  2xx: #{locSummary.http2xx}" if @isMonitor and locSummary.http2xx isnt 0
    deets.push "  1xx: #{locSummary.http1xx}" if @isMonitor and locSummary.http1xx isnt 0
    deets.push "  Zero negative events." if deets.length < 2
    deets.join '\n'

  url: ->
    @measurementsUrl