# Description:
#   A hubot script to query the canary.io API.
#
# Dependencies:
#   "moment": "^2.6.0"
#
# Commands:
#   hubot canary check - get the list of URLs which have measurements taken by canary.io 
#   hubot canary check <filter> - get filtered list of checked URLs. Coming soon!
#   hubot canary check reset - clear the hubot canary check cache, then get again
#   hubot canary measure <check-id> - get measurements of <check-id> for last 10 seconds
#   hubot canary measure <check-id> <num-seconds> - get measurements of <check-id> for last <num-seconds> seconds
#   hubot canary mon <check-id> - start monitoring <check-id>. every 5 seconds send hubot canary summary <check-id>
#   hubot canary mon stop <check-id> - stop monitoring <check-id>
#   hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most http status 5xx, most failed checks (non-zero exit_status), slowest avg, slowest single call, slowest total time
#   hubot canary help - get list of hubot canary commands
#
# Notes:
#   Have fun with it.
#
# Author:
#   ryoe
moment = require 'moment'

checks = []
checksMap = {}
monitors = []
monInterval = null
checksUrl = 'http://checks.canary.io'
measuresUrl = 'https://api.canary.io/checks/XXX/measurements?range=YYY'

module.exports = (robot) ->
  robot.respond /\bcanary\b/i, (msg) ->
    text = msg.message.text

    if checks.length == 0 #sanity check
      getChecks msg, true, (err, data) ->
        processCanaryCmd msg, text if not err
    else
      processCanaryCmd msg, text

apiCall = (msg, url, cb) ->
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
    checks = []

  if checks.length > 0
    #use cached checks
    displayChecks msg if not silent
    cb null, null if cb
    return

  apiCall msg, checksUrl, (err, body) ->
    if err
      console.log err
      msg.send body
      return

    checks = JSON.parse body
    checksMap[c.id] = c for c in checks
    displayChecks msg if not silent
    cb null, null if cb

displayChecks = (msg) ->
  deets = []
  deets.push checkDetails c for c in checks
  msg.send deets.join '\n'

checkDetails = (check) ->
  return 'id: ' + check.id + ' => url: ' + check.url

getMeasurements = (msg) ->
  text = msg.message.text
  matches = text.match(/\bmeasure(ment)?(s)?\b \b(\S*)+\b(\s*)?(\d*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[3]
  range = matches[5] || 10

  return if not isValidCheckId msg, checkId

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
    displayMeasurements msg, data, checkId, range

displayMeasurements = (msg, measurements, checkId, range) ->
  if measurements.length == 0
    msg.send 'Zero measurements found for ' + checkId + ' in last ' + range + ' seconds.'
    return

  check = measurements[0].check

  deets = []
  deets.push measurements.length + ' measurements found for ' + check.url + ' in last ' + range + ' seconds.'
  deets.push '--------------------'
  deets.push measurementDetails m for m in measurements

  msg.send deets.join '\n'

measurementDetails = (measurement) ->
  deets = []
  deets.push 'id: ' + measurement.id
  deets.push 'timestamp: ' + measurement.t
  deets.push 'total time: ' + measurement.total_time
  deets.push 'connect time: ' + measurement.connect_time
  deets.push 'start transfer time: ' + measurement.starttransfer_time
  deets.push 'name lookup time: ' + measurement.namelookup_time
  deets.push 'location: ' + measurement.location
  deets.push 'exit status: ' + measurement.exit_status
  deets.push 'http status: ' + measurement.http_status
  deets.push 'local ip: ' + measurement.local_ip
  deets.push 'primary ip: ' + measurement.primary_ip
  deets.push '--------------------'

  return deets.join '\n'

stopMonitor = (msg) ->
  text = msg.message.text
  matches = text.match(/\bmon\b stop \b(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[1]
  return if not isValidCheckId msg, checkId
  idx = monitors.indexOf checkId
  monitors.splice idx, 1 if idx > -1
  if monitors.length == 0
    clearInterval monInterval
    monInterval = null

startMonitor = (msg) ->
  text = msg.message.text
  if text.match(/\bmon\b stop/i)
    stopMonitor msg
    return

  matches = text.match(/\bmon\b (\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[1]

  return if not isValidCheckId msg, checkId
  idx = monitors.indexOf checkId
  monitors.push checkId if idx < 0
  delay = 5000
  monInterval = setInterval processMonitors, delay, msg if not monInterval?

processMonitors = (msg) ->
  range = 300
  getSummaryData msg, checkId, range for checkId in monitors

getSummary = (msg) ->
  text = msg.message.text
  matches = text.match(/\bsummary\b \b(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[1]
  return if not isValidCheckId msg, checkId
  range = 300
  getSummaryData msg, checkId, range

getSummaryData = (msg, checkId, range) ->
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
    displaySummary msg, data, checkId, range

displaySummary = (msg, measurements, checkId, range) ->
  if measurements.length == 0
    msg.send 'Zero measurements found for ' + checkId + ' in last ' + range + ' seconds.'
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

  locs.unshift tot
  startDate = moment.unix(measurements[len-1].t)
  endDate = moment.unix(measurements[0].t)
  dateRange = startDate.format("MMM D, YYYY") + " " + startDate.format("HH:mm:ss") + " to " + endDate.format("HH:mm:ss (UTC ZZ)")
  check = measurements[0].check

  deets = []
  deets.push 'Summary for '+ check.url
  deets.push dateRange
  deets.push 'Total measurements: ' + len
  deets.push '--------------------'
  deets.push summaryDetails s for s in locs

  msg.send deets.join '\n'

summaryDetails = (locSummary) ->
  deets = []
  deets.push locSummary.loc.toUpperCase()
  deets.push '  failed: ' + locSummary.fail if locSummary.fail isnt 0
  deets.push '  5xx: ' + locSummary.http5xx if locSummary.http5xx isnt 0
  deets.push '  4xx: ' + locSummary.http4xx if locSummary.http4xx isnt 0
  deets.push '  3xx: ' + locSummary.http3xx if locSummary.http3xx isnt 0
  deets.push '  2xx: ' + locSummary.http2xx if locSummary.http2xx isnt 0
  deets.push '  1xx: ' + locSummary.http1xx if locSummary.http1xx isnt 0
#  deets.push '  success: ' + locSummary.success
#  deets.push '  avg (sec): ' + locSummary.avg
#  deets.push '  max (sec): ' + locSummary.max
#  deets.push '  min (sec): ' + locSummary.min
 # deets.push '  tot (sec): ' + locSummary.total
  return deets.join '\n'

getHelp = (msg) ->
  help = []
  help.push 'hubot canary check - get the list of URLs which have measurements taken by canary.io' 
  help.push 'hubot canary check <filter> - get filtered list of checked URLs. Coming soon!'
  help.push 'hubot canary check reset - clear the hubot canary check cache, then get again'
  help.push 'hubot canary measure <check-id> - get measurements of <check-id> for last 10 seconds'
  help.push 'hubot canary measure <check-id> <num-seconds> - get measurements of <check-id> for last <num-seconds> seconds'
  help.push 'hubot canary mon <check-id> - start monitoring <check-id>. every 5 seconds send hubot canary summary <check-id>'
  help.push 'hubot canary mon stop <check-id> - stop monitoring <check-id>'
  help.push 'hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most http status 5xx, most failed checks (non-zero exit_status), slowest avg, slowest single call, slowest total time'
  help.push 'hubot canary help - get list of hubot canary commands'

  msg.send help.join '\n'

getUnknownCommand = (msg) ->
  list = []
  list.push 'Unable to comply. Unknown command "' + msg.message.text + '"'
  list.push 'Try "hubot canary help".'

  msg.send list.join '\n'

isValidCheckId = (msg, checkId) ->
  c = checksMap[checkId]
  return true if c?
  msg.send '"' + checkId + '" is not a current check-id.\nTry "hubot canary check" for the current cached list.\nOr try "hubot canary reset" to clear the cache and retrive new list.'
  return false

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
  else
    getUnknownCommand msg

