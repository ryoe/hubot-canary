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
# Notes:
#   Have fun with it.
#
# Author:
#   ryoe
moment = require 'moment'
querystring = require 'querystring'

MAX_RANGE = 300
DEFAULT_RANGE = 10
monitors = []
monInterval = null
measuresUrl = 'https://api.canary.io/checks/XXX/measurements?range=YYY'
watchUrl = 'http://watch.canary.io/'
watchReplaceUrl = 'http://watch.canary.io/#/checks/XXX/measurements'
checks = null
help = null
rbt = null

module.exports = (robot) ->
  rbt = robot
  help = new Help
  checks = new Checks
  
  robot.error (err, msg) ->
    console.log 'guh'
    console.log err
    robot.logger.error "DOES NOT COMPUTE"

    if msg?
      msg.reply "DOES NOT COMPUTE"

  robot.on 'hubot-canary:incEvt', (data) ->
    console.log 'hubot-canary:incEvt'
    console.log data
    room = data.room || '109614_demo@conf.hipchat.com'
    dataMsg = data.message || 'It is important that you know, no was message received!'
    robot.messageRoom room, dataMsg

  robot.router.post '/hubot/incident', (req, res) ->
    data = req.body
    msg = data.message

    user = {}
    user.type = 'groupchat'
    user.room = '109614_demo@conf.hipchat.com' #NOTIFY_ROOM #q.room if q.room

    hMsg = "DO NOT BE ALARMED!\nWe just handled a POST! This is a broadcast message from your new robot overlord!\n\n#{msg}"

    robot.send user, hMsg
    res.end "POST incident #{msg}"

  robot.router.get '/hubot/incident', (req, res) ->
    q = querystring.parse req._parsedUrl.query
    msg = q.message

    user = {}
    user.type = 'groupchat'
    user.room = '109614_demo@conf.hipchat.com' #NOTIFY_ROOM #q.room if q.room

    hMsg = "DO NOT BE ALARMED!\nThis is a broadcast message from your new robot overlord!\n\n#{msg}"
    hMsg = 'canary begin'#'bluebot canary mon https-github.com'
    robot.send user, hMsg
    #console.log robot
    #robot.respond 'bluebot canary incident https-github.com'
    #robot.respond 'canary incident https-github.com'
    #m = robot.Response
    #m.message = {}
    #m.message.text = 'canary incident https-github.com'
    #processCanaryCmd m, m.message.text
    res.end "incident #{msg}"

  robot.respond /\bcanary\b/i, (msg) ->
    text = msg.message.text

    if checks.length() == 0 #sanity check
      getChecks msg, true, (err, data) ->
        processCanaryCmd msg, text if not err
    else
      processCanaryCmd msg, text

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
  msg.http(url)
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
      msg.send body
      return

    data = JSON.parse body
    checks.load data
    displayChecks msg if not silent
    cb null, null if cb

displayChecks = (msg) ->
  msg.send checks.toString()

getWatchUrl = (msg) ->
  text = msg.message.text
  matches = text.match(/\bwatch\b(\s*)?(\S*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2] || null
  if not checkId?
    url = watchUrl
    msg.send "WARN: No <check-id> provided.\n#{url}"
    return

  return if not isValidCheckId msg, checkId

  regEx = new RegExp 'XXX', 'i'
  url = watchReplaceUrl.replace regEx, checkId
  msg.send "#{url}"

getMeasurements = (msg) ->
  text = msg.message.text
  matches = text.match(/\bmeasure(ment)?(s)?\b \b(\S*)+\b(\s*)?(\d*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[3]
  range = matches[5] || DEFAULT_RANGE
  range = MAX_RANGE if range > MAX_RANGE
  range = DEFAULT_RANGE if range <= 0

  return if not isValidCheckId msg, checkId

  regEx = new RegExp 'XXX', 'i'
  url = measuresUrl.replace regEx, checkId
  regEx = new RegExp 'YYY', 'i'
  url = url.replace regEx, range
  msg.send "#{url}"

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
    msg.send 'All monitors cleared.'

startIncident = (msg) ->
  text = msg.message.text
  matches = text.match(/\bincident\b(\s*)+(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[2]
  return if not isValidCheckId msg, checkId
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
  return if not isValidCheckId msg, checkId
  setupMonitor msg, checkId, true

setupMonitor = (msg, checkId, isMon) ->
  idx = monitors.indexOf checkId
  monitors.push checkId if idx < 0
  delay = 5000
  if not monInterval?
    processMonitors msg #show results now!
    monInterval = setInterval processMonitors, delay, msg, isMon

processMonitors = (msg, isMon) ->
  range = MAX_RANGE
  getSummaryData msg, checkId, range, true, isMon for checkId in monitors
  console.log 'emit'
  rbt.emit 'hubot-canary:incEvt', { msg: 'boom'}
  console.log 'post-emit'

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
  regEx = new RegExp 'XXX', 'i'
  url = measuresUrl.replace regEx, checkId
  regEx = new RegExp 'YYY', 'i'
  url = url.replace regEx, range

  apiCall msg, url, (err, body) ->
    if err
      console.log err
      msg.send body
      return

    data = JSON.parse body
    displaySummary msg, data, checkId, range, totalOnly, isMon

displaySummary = (msg, measurements, checkId, range, totalOnly, isMon) ->
  if measurements.length == 0
    msg.send "Zero measurements found for #{checkId} in last #{range} seconds."
    return

  locMap = {}
  i = 0
  len = measurements.length

  while i < len
    loc = measurements[i]
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
    #then most http status 5xx
    return b.http5xx- a.http5xx  if a.http5xx isnt b.http5xx
    #most failed checks
    return b.fail - a.fail  if a.fail isnt b.fail
    #then slowest avg
    return b.avg - a.avg  if a.avg isnt b.avg
    #then slowest call
    return b.max - a.max  if a.max isnt b.max
    #then slowest total
    b.total - a.total

  if totalOnly
    locs = [tot]
  else locs.unshift tot
  startDate = moment.unix(measurements[len-1].t)
  endDate = moment.unix(measurements[0].t)
  dateRange = startDate.format("MMM D, YYYY") + " " + startDate.format("HH:mm:ss") + " to " + endDate.format("HH:mm:ss (UTC ZZ)")
  chk = measurements[0].check

  deets = []
  deets.push 'Summary for '+ chk.url
  deets.push dateRange
  deets.push 'Total measurements: ' + len
  deets.push '--------------------'
  deets.push summaryDetails s, isMon for s in locs

  msg.send deets.join '\n'

summaryDetails = (locSummary, isMon) ->
  deets = []
  deets.push locSummary.loc.toUpperCase()
  deets.push '  failed: ' + locSummary.fail if locSummary.fail isnt 0
  deets.push '  5xx: ' + locSummary.http5xx if locSummary.http5xx isnt 0
  deets.push '  4xx: ' + locSummary.http4xx if isMon and locSummary.http4xx isnt 0
  deets.push '  3xx: ' + locSummary.http3xx if isMon and locSummary.http3xx isnt 0
  deets.push '  2xx: ' + locSummary.http2xx if isMon and locSummary.http2xx isnt 0
  deets.push '  1xx: ' + locSummary.http1xx if isMon and locSummary.http1xx isnt 0
  return deets.join '\n'

getHelp = (msg) ->
  msg.send help.toString()

getUnknownCommand = (msg) ->
  list = []
  list.push 'Unable to comply. Unknown command "' + msg.message.text + '"'
  list.push 'Try "hubot canary help".'

  msg.send list.join '\n'

isValidCheckId = (msg, checkId) ->
  return true if checks.isValid(checkId)
  msg.send '"' + checkId + '" is not a current check-id.\nTry "hubot canary check" for the current cached list.\nOr try "hubot canary reset" to clear the cache and retrive new list.'
  return false

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
    @help = []
    @help.push 'hubot canary mon <check-id> - start monitoring <check-id>. every 5 seconds send hubot canary summary <check-id>'
    @help.push 'hubot canary mon stop <check-id> - stop monitoring <check-id>'
    @help.push 'hubot canary mon stop all - stop all monitoring'
    @help.push 'hubot canary incident <check-id> - same as "hubot canary mon <check-id>" but only display 5xx http status and non-zero exit status (failures)'
    @help.push 'hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most http status 5xx, most failed checks (non-zero exit_status), slowest avg, slowest single call, slowest total time'
    @help.push 'hubot canary check - get the list of URLs which have measurements taken by canary.io' 
    @help.push 'hubot canary check <filter> - get filtered list of checked URLs. Coming soon!'
    @help.push 'hubot canary check reset - clear the hubot canary check cache, then get again'
    @help.push 'hubot canary watch <check-id> - get url to open <check-id> for real-time monitoring in http://watch.canary.io'
    @help.push 'hubot canary measure <check-id> - get url to download measurements of <check-id> for last 10 seconds'
    @help.push 'hubot canary measure <check-id> <num-seconds> - get url to download measurements of <check-id> for last <num-seconds> seconds'
    @help.push 'hubot canary help - get list of hubot canary commands'

  toString: ->
    @help.join '\n'
