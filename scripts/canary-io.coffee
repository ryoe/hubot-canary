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
#   hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most fails, slowest time, most successful requests
#   hubot canary help - get list of hubot canary commands
#
# Notes:
#   Have fun with it.
#
# Author:
#   ryoe
moment = require 'moment'

checks = []
checksUrl = 'http://checks.canary.io'
measuresUrl = 'https://api.canary.io/checks/XXX/measurements?range=YYY'

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

getChecks = (msg) ->
  text = msg.message.text

  if text.match(/\breset\b/i)
    checks = []

  if checks.length > 0
    #use cached checks
    displayChecks msg
    return

  apiCall msg, checksUrl, (err, body) ->
    if err
      console.log err
      msg.send body
      return

    checks = JSON.parse body
    displayChecks msg

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

  #TODO: validate checkId

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

getSummary = (msg) ->
  text = msg.message.text
  matches = text.match(/\bsummary\b \b(\S*)+\b(\s*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[1]
  range = 300

  #TODO: validate checkId

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
        fail: 0
        success: 0
    if loc.exit_status is 0
      locMap[loc.location].success++
    else
      locMap[loc.location].fail++
    if loc.total_time > locMap[loc.location].max
      locMap[loc.location].max = loc.total_time
    else locMap[loc.location].min = loc.total_time  if loc.total_time < locMap[loc.location].min
    i++

  locs = []
  for prop of locMap
    locs.push locMap[prop]
  locs.sort (a, b) ->    
    #fails first
    return b.fail - a.fail  if a.fail isnt b.fail
    #then slowest
    return b.max - a.max  if a.max isnt b.max
    #then most success
    b.success - a.success

  startDate = moment.unix(measurements[0].t)
  endDate = moment.unix(measurements[len - 1].t)
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
  deets.push '  # failed: ' + locSummary.fail if locSummary.fail isnt 0
  deets.push '  max (sec): ' + locSummary.max
  deets.push '  min (sec): ' + locSummary.min
  deets.push '  # success: ' + locSummary.success
  return deets.join '\n'

getHelp = (msg) ->
  help = []
  help.push 'hubot canary check - get the list of URLs which have measurements taken by canary.io' 
  help.push 'hubot canary check <filter> - get filtered list of checked URLs. Coming soon!'
  help.push 'hubot canary check reset - clear the hubot canary check cache, then get again'
  help.push 'hubot canary measure <check-id> - get measurements of <check-id> for last 10 seconds'
  help.push 'hubot canary measure <check-id> <num-seconds> - get measurements of <check-id> for last <num-seconds> seconds'
  help.push 'hubot canary summary <check-id> - get summary measurements of <check-id> for last 5 minutes sorted by most fails, slowest time, most successful requests'
  help.push 'hubot canary help - get list of hubot canary commands'

  msg.send help.join '\n'

getUnknownCommand = (msg) ->
  list = []
  list.push 'Unable to comply. Unknown command "' + msg.message.text + '"'
  list.push 'Try "hubot canary help".'

  msg.send list.join '\n'

module.exports = (robot) ->
  robot.respond /\bcanary\b/i, (msg) ->
    text = msg.message.text

    if text.match(/\bcheck(s)?\b/i)
      getChecks msg
    else if text.match(/\bhelp\b/i)
      getHelp msg
    else if text.match(/\bmeasure(ment)?(s)?\b/i)
      getMeasurements msg
    else if text.match(/\bsummary?(s)?\b/i)
      getSummary msg
    else
      getUnknownCommand msg
